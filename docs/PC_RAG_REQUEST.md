# PC の Claude への依頼：Design Wave Magazine の誌面検索（RAG）用の索引を作る

アプリ「自炊ビューア」に、雑誌のバックナンバーを全文検索して、AI がその誌面をもとに答える機能（RAG）を入れました。
アプリは、PC で作った索引ファイル `rag_index.json` を iCloud 経由で読みます。その索引を作ってください。

## やること

1. リポジトリを最新にする（`git pull`）
2. 索引を作る
   ```powershell
   pip install pymupdf
   $env:PYTHONUTF8 = "1"
   python tools/build_rag_index.py "C:\Users\yfb31\Documents\icloud同期フォルダ\iCloudDrive\ScanSnap Home\Design_Wave_Magazine" --report
   ```
   - `Design_Wave_Magazine` フォルダの直下に `rag_index.json` ができる。iCloud で iPhone に同期され、アプリの本棚の右上に虫めがねボタンが出る
3. **文字の質を確かめる**（いちばん大事）
   - 索引の文字は、ScanSnap が PDF に入れた OCR（文字認識）の結果をそのまま使っている。雑誌でどれくらい正しく読めているかは、まだ誰も確かめていない
   - 何冊かの何ページかを選び、ページの画像と `rag_index.json` の文字を見比べる（本文・見出し・図の中の文字・表・ソースコード）
   - `--report` で出る「文字がほとんど取れないページ」の数と中身（広告・写真だけのページなら問題ない）
4. 文字の質が低いときは、OCR をやり直して索引を作り直す
   - 例：Windows の OCR、tesseract（`jpn` と `jpn_vert`）、ほかの OCR など。日本語の縦書き・横書きが混ざる誌面なので、いくつか試して良いものを選ぶ
   - やり直す場合は、`tools/build_rag_index.py` に OCR のやり方を足すか、別のスクリプトを作る。**出力の形（下の「索引の形式」）は変えない**
5. 結果を `docs/PC_RAG_REPORT.md` に書いて、push する

## 索引の形式（アプリが読む形。変えないこと）

```json
{
  "version": 1,
  "created": "2026-10-18T19:00:00",
  "source": "ScanSnap OCR",
  "pages": [
    {"file": "20260112_xxx.pdf", "page": 0, "text": "ページの文字..."}
  ]
}
```

- `file`：索引ファイルのあるフォルダからの相対パス（`/` 区切り）。アプリはこれで本棚の本と結び付ける
- `page`：0 から数えたページ番号
- `text`：NFKC で整えた文字（全角英数字は半角）。日本語の文字の間の空白は消す（`clean()` を参照）
- `source`：OCR をやり直したら、その方法を書く

## 守ってほしいこと

- **`rag_index.json` はリポジトリに入れない**（雑誌の本文そのものなので）。`.gitignore` に入れてある。置くのは iCloud の雑誌フォルダだけ
- 元の PDF は読むだけ。変更・移動・削除しない
- 雑誌のファイル名が崩れている（`20260112_支援する_003.pdf` など）。名前を付け直すと、アプリの読んだ位置やしおりはリセットされるが、索引は作り直せばよい。名前を直すかどうかは持ち主に確認する

## 報告に書いてほしいこと（`docs/PC_RAG_REPORT.md`）

- 冊数・ページ数・文字数・ファイルの大きさ
- 文字の質（見比べた例を言葉で。誤字の多さ、取れていない部分）
- OCR をやり直したか、その方法
- 検索で困りそうな点（表記ゆれ、ソースコードの崩れ、図の中の文字など）
