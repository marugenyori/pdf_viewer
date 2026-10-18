"""ScanSnap Home フォルダの PDF を調べて、補正の調整に使う数値をまとめる。

使い方（Windows の PowerShell）:
    pip install pymupdf numpy
    python tools/survey_scans.py "C:\\Users\\yfb31\\Documents\\icloud同期フォルダ\\iCloudDrive\\ScanSnap Home"

出力:
    docs/scan_survey.md   … 人が読む要約（数値だけ。画像は含まない）
    docs/scan_survey.json … 1冊・1ページごとの詳しい数値
    --samples フォルダ    … 指定したときだけ、見本ページの PNG を保存（リポジトリには入れない）

ページの解析は MangaViewer/Processing/PageAnalyzer.swift と同じ考え方（同じしきい値）で行う。
iCloud にしかない（ダウンロードされていない）ファイルは開くと自動でダウンロードされるので時間がかかる。
"""
import argparse
import json
import os
import statistics
import sys

import numpy as np
import pymupdf

# PageAnalyzer.swift と同じしきい値
DARK = 0.35          # 黒い縁とみなす明るさ
DARK_FRACTION = 0.85 # 行・列のうち暗い画素の割合
EDGE_MAX = 0.15      # 各辺で削る最大の割合
PAPER_LO = 0.88      # 紙の色：明るさの上位 12%
PAPER_HI = 0.995
INK_P = 0.01         # インクの色：暗いほう 1%
COLOR_CHROMA = 0.2
COLOR_FRACTION = 0.03
YELLOW_AXIS = np.array([1.0, 1.0, -2.0]) / np.sqrt(6)  # 黄 ↔ 青の軸
YELLOW_ALLOWANCE = 0.3  # 黄色みとして差し引く量の上限


def luma(rgb):
    return rgb[..., 0] * 0.299 + rgb[..., 1] * 0.587 + rgb[..., 2] * 0.114


def black_edges(L):
    h, w = L.shape
    top, bottom, left, right = 0, h, 0, w
    dark_rows = (L < DARK).mean(axis=1) > DARK_FRACTION
    while top < int(h * EDGE_MAX) and dark_rows[top]:
        top += 1
    while h - bottom < int(h * EDGE_MAX) and dark_rows[bottom - 1]:
        bottom -= 1
    dark_cols = (L[top:bottom] < DARK).mean(axis=0) > DARK_FRACTION
    while left < int(w * EDGE_MAX) and dark_cols[left]:
        left += 1
    while w - right < int(w * EDGE_MAX) and dark_cols[right - 1]:
        right -= 1
    return {"top": top / h, "bottom": (h - bottom) / h, "left": left / w, "right": (w - right) / w}, (top, bottom, left, right)


def analyze_pixels(rgb):
    L = luma(rgb)
    edges, (t, b, l, r) = black_edges(L)
    region = rgb[t:b, l:r].reshape(-1, 3)
    Lr = luma(region)
    lo, hi, ink_hi = np.quantile(Lr, [PAPER_LO, PAPER_HI, INK_P])
    paper = region[(Lr >= lo) & (Lr <= hi)].mean(axis=0)
    ink = region[Lr <= ink_hi].mean(axis=0)
    white = np.minimum(1, paper * 0.97) if luma(paper) >= 0.55 else np.ones(3)
    black = np.minimum(ink, 0.3)
    span = np.maximum(white - black, 0.35)
    mapped = np.clip((region - black) / span, 0, 1)
    ml = luma(mapped)
    mid = (ml > 0.08) & (ml < 0.95)
    c = mapped - mapped.mean(axis=1, keepdims=True)
    along = np.clip(c @ YELLOW_AXIS, 0, YELLOW_ALLOWANCE)
    c = c - along[:, None] * YELLOW_AXIS
    chroma = c.max(axis=1) - c.min(axis=1)
    colored = float(((chroma > COLOR_CHROMA) & mid).mean())
    return {
        "black_edges": {k: round(v, 3) for k, v in edges.items()},
        "paper_rgb": [round(float(x), 3) for x in paper],
        "ink_rgb": [round(float(x), 3) for x in ink],
        "paper_yellowness": round(float(paper[0] + paper[1]) / 2 - float(paper[2]), 3),
        "colored_fraction": round(colored, 4),
        "is_color": colored > COLOR_FRACTION,
        "luma_p01_p50_p99": [round(float(x), 3) for x in np.quantile(L, [0.01, 0.5, 0.99])],
    }


def image_info(doc, page):
    """ページに埋め込まれた一番大きい画像の形式（スキャン解像度・色）"""
    best = None
    for img in page.get_images(full=True):
        xref, _, w, h, bpc, cs, _, _, filt = img[:9]
        if best is None or w * h > best["w"] * best["h"]:
            best = {"w": w, "h": h, "bpc": bpc, "colorspace": cs, "filter": filt}
    if best:
        rect = page.rect
        best["dpi"] = round(best["w"] / (rect.width / 72)) if rect.width else None
    return best


def survey_book(path, samples_per_book, sample_dir):
    doc = pymupdf.open(path)
    n = doc.page_count
    pages = []
    idx = sorted(set(int(i * (n - 1) / max(1, samples_per_book - 1)) for i in range(samples_per_book))) if n else []
    for i in range(n):
        page = doc[i]
        rect = page.rect
        info = {
            "index": i,
            "size_pt": [round(rect.width), round(rect.height)],
            "pdf_rotate": page.rotation,
            "landscape": rect.width > rect.height * 1.08,
        }
        if i in idx:
            zoom = 600 / max(rect.width, rect.height)
            pix = page.get_pixmap(matrix=pymupdf.Matrix(zoom, zoom), colorspace=pymupdf.csRGB, alpha=False)
            rgb = np.frombuffer(pix.samples, dtype=np.uint8).reshape(pix.height, pix.width, 3) / 255.0
            info["analysis"] = analyze_pixels(rgb)
            info["image"] = image_info(doc, page)
            if sample_dir:
                name = f"{os.path.splitext(os.path.basename(path))[0]}_p{i + 1:04d}.png"
                pix.save(os.path.join(sample_dir, name))
        pages.append(info)
    doc.close()
    return {"pages": n, "file_mb": round(os.path.getsize(path) / 1e6, 1), "page_info": pages}


def summarize(books):
    lines = ["# スキャン調査の結果", "", "`tools/survey_scans.py` が出力。画像は含まず数値だけ。", ""]
    all_pages = [p for b in books.values() for p in b.get("page_info", [])]
    analyzed = [p for p in all_pages if "analysis" in p]
    lines += [
        f"- 冊数：{len(books)}、総ページ数：{len(all_pages)}、解析したページ：{len(analyzed)}",
        f"- 横長のページ：{sum(p['landscape'] for p in all_pages)}",
        f"- PDF の回転指定（/Rotate）の内訳：{dict(sorted(_count(p['pdf_rotate'] for p in all_pages).items()))}",
    ]
    if analyzed:
        def stat(values):
            return f"中央値 {statistics.median(values):.3f} / 最大 {max(values):.3f}"
        for side in ("top", "bottom", "left", "right"):
            lines.append(f"- 黒い縁（{side}）：{stat([p['analysis']['black_edges'][side] for p in analyzed])}")
        lines.append(f"- 紙の黄ばみ（R,G の平均 − B）：{stat([p['analysis']['paper_yellowness'] for p in analyzed])}")
        lines.append(f"- カラー判定されたページ：{sum(p['analysis']['is_color'] for p in analyzed)}")
        imgs = [p["image"] for p in analyzed if p.get("image")]
        if imgs:
            lines.append(f"- 埋め込み画像の色空間：{_count(i['colorspace'] for i in imgs)}")
            lines.append(f"- 埋め込み画像の形式：{_count(i['filter'] for i in imgs)}")
            dpis = [i["dpi"] for i in imgs if i.get("dpi")]
            if dpis:
                lines.append(f"- 解像度（dpi）：中央値 {statistics.median(dpis)}、最小 {min(dpis)}、最大 {max(dpis)}")
    lines += ["", "## 1冊ごと", "", "| 本 | ページ | MB | 横長 | /Rotate≠0 | カラー判定 |", "|---|---|---|---|---|---|"]
    for name, b in books.items():
        if "error" in b:
            lines.append(f"| {name} | 読めない：{b['error']} | | | | |")
            continue
        pi = b["page_info"]
        an = [p for p in pi if "analysis" in p]
        lines.append(f"| {name} | {b['pages']} | {b['file_mb']} | {sum(p['landscape'] for p in pi)} | "
                     f"{sum(p['pdf_rotate'] != 0 for p in pi)} | {sum(p['analysis']['is_color'] for p in an)}/{len(an)} |")
    return "\n".join(lines) + "\n"


def _count(values):
    out = {}
    for v in values:
        out[v] = out.get(v, 0) + 1
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("folder")
    ap.add_argument("--samples-per-book", type=int, default=8)
    ap.add_argument("--samples", help="見本ページの PNG を保存するフォルダ（リポジトリの外に）")
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "..", "docs"))
    args = ap.parse_args()

    if args.samples:
        os.makedirs(args.samples, exist_ok=True)
    books = {}
    for root, _, files in os.walk(args.folder):
        for f in sorted(files):
            if not f.lower().endswith(".pdf"):
                continue
            path = os.path.join(root, f)
            rel = os.path.relpath(path, args.folder)
            print(f"調査中: {rel}", file=sys.stderr)
            try:
                books[rel] = survey_book(path, args.samples_per_book, args.samples)
            except Exception as e:  # 壊れた PDF があっても全体は止めない
                books[rel] = {"error": str(e)}
    os.makedirs(args.out, exist_ok=True)
    with open(os.path.join(args.out, "scan_survey.json"), "w", encoding="utf-8") as fp:
        json.dump(books, fp, ensure_ascii=False, indent=1)
    with open(os.path.join(args.out, "scan_survey.md"), "w", encoding="utf-8") as fp:
        fp.write(summarize(books))
    print(f"完了: {len(books)} 冊", file=sys.stderr)


if __name__ == "__main__":
    main()
