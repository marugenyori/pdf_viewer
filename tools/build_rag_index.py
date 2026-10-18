"""雑誌などの PDF から文字を取り出し、アプリの RAG 検索（誌面検索）用の索引ファイルを作る。

使い方（Windows の PowerShell）:
    pip install pymupdf
    $env:PYTHONUTF8 = "1"
    python tools/build_rag_index.py "C:\\Users\\yfb31\\Documents\\icloud同期フォルダ\\iCloudDrive\\ScanSnap Home\\Design_Wave_Magazine"

出力:
    指定したフォルダの直下に rag_index.json を作る（iCloud で iPhone に同期され、アプリが読む）。
    フォルダの中（サブフォルダも含む）の PDF すべての、ページごとの文字が入る。

文字は ScanSnap が PDF に入れた OCR（文字認識）の結果をそのまま使う。
--report を付けると、文字がほとんど取れないページの一覧を出す（OCR をやり直すかの判断用）。
"""
import argparse
import datetime
import json
import os
import re
import sys
import unicodedata

import pymupdf

INDEX_NAME = "rag_index.json"
FORMAT_VERSION = 1

# 日本語の文字（ひらがな・カタカナ・漢字・全角記号）
JA = r"[\u3000-\u303f\u3040-\u30ff\u4e00-\u9fff\uff00-\uffef]"


def clean(text: str) -> str:
    """OCR の文字を検索しやすく整える。全角英数字を半角にし（NFKC）、日本語の文字の間の空白を消す"""
    text = unicodedata.normalize("NFKC", text)
    text = re.sub(rf"(?<={JA})[ \t]+(?={JA})", "", text)
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("folder", help="索引を作るフォルダ（例：Design_Wave_Magazine）")
    ap.add_argument("--report", action="store_true", help="文字がほとんど取れないページを一覧にする")
    args = ap.parse_args()

    root = os.path.abspath(args.folder)
    pages = []
    weak = []
    files = []
    for dirpath, _, names in os.walk(root):
        for name in sorted(names):
            if name.lower().endswith(".pdf"):
                files.append(os.path.join(dirpath, name))
    files.sort()

    for path in files:
        rel = os.path.relpath(path, root).replace(os.sep, "/")
        print(f"読み取り中: {rel}", file=sys.stderr)
        try:
            doc = pymupdf.open(path)
        except Exception as e:  # 壊れた PDF があっても全体は止めない
            print(f"  開けません: {e}", file=sys.stderr)
            continue
        for i, page in enumerate(doc):
            text = clean(page.get_text())
            if len(text) < 30:
                weak.append(f"{rel} p.{i + 1}（{len(text)} 文字）")
            if text:
                pages.append({"file": rel, "page": i, "text": text})
        doc.close()

    index = {
        "version": FORMAT_VERSION,
        "created": datetime.datetime.now().isoformat(timespec="seconds"),
        "source": "ScanSnap OCR",
        "pages": pages,
    }
    out = os.path.join(root, INDEX_NAME)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(index, f, ensure_ascii=False)
    total_chars = sum(len(p["text"]) for p in pages)
    print(f"完了: {len(files)} 冊、{len(pages)} ページ、{total_chars:,} 文字 → {out}", file=sys.stderr)
    print(f"ファイルの大きさ: {os.path.getsize(out) / 1e6:.1f} MB", file=sys.stderr)
    if args.report:
        print(f"\n文字がほとんど取れないページ: {len(weak)}", file=sys.stderr)
        for w in weak[:200]:
            print("  " + w, file=sys.stderr)


if __name__ == "__main__":
    main()
