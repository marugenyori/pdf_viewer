# 引き継ぎ書：自炊ビューア（2026-10-18）

自宅の Windows PC で作業する Claude（Claude Code）への引き継ぎです。持ち主にも読める書き方にしてあります。
作業メモ全体は、リポジトリ直下の `CLAUDE.md` にあります（返答は日本語、手順は番号付き、など）。

## 1. 頼みたいこと（ひとことで）

**`ScanSnap Home` フォルダの中身を実際に見て、アプリの自動補正をその本に合わせて調整してほしい。**

アプリはクラウド上の Claude が書いたものです。クラウドからは持ち主の PC も iCloud Drive も見えないので、本の中身を一度も見ずに、持ち主の説明だけで作っています。

- 本のある場所：`C:\Users\yfb31\Documents\icloud同期フォルダ\iCloudDrive\ScanSnap Home`
- 持ち主の説明：1冊＝1つの PDF。自炊の質が低く、ページが**回転している**（横向き・逆さま）、**色や明るさがばらばら**、**余白や黒い縁**が残っている

## 2. いまの状態

| 項目 | 状態 |
|---|---|
| コード | `main` に1コミット（`301aaeb`）。SwiftUI、iOS 17、外部ライブラリなし |
| CI のビルド（署名なし） | ✅ 成功（Actions の実行 #1） |
| 実機での動作 | **未確認**（TestFlight にまだ出していない） |
| Apple 側の登録（App ID・App Store Connect）と Secrets | 持ち主に案内済み。**済んだかどうかは未確認** |
| リポジトリ名 | GitHub で `pdf_viwer` から `pdf_viewer` に変わったらしい（古い URL は転送される） |

TestFlight に必要なもの：Bundle ID `com.marugenyori.mangaviewer` の App ID、App Store Connect のアプリ、Secrets 5つ（`APPLE_TEAM_ID`、`BUNDLE_ID`、`ASC_KEY_ID`、`ASC_ISSUER_ID`、`ASC_KEY_P8`。`BUNDLE_ID` 以外は `claud_code` と同じ値）。

## 3. 確かめていない前提（ここを実物で確認してほしい）

アプリはこれらの前提で作っています。違っていたら、コードを直す必要があります。

1. **形式**：1冊＝1つの PDF で、1ページ＝1枚のスキャン画像
   - JPEG のフォルダや ZIP が混ざっている場合は、読み込みの部分（`LibraryStore` と `BookRenderer`）に対応を足す
   - 見開きのまま 1 枚にスキャンしたページ（横長の画像に 2 ページ分）がある場合、今のアプリは「横向きにスキャンされたページ」とみなして 90° 回してしまう。**ここがいちばん心配**。あれば、左右に分ける機能が必要
2. **回転**：90°・180°・270° の回転だけで、数度の傾きはない（持ち主は「少しの傾き」を補正対象に選ばなかった）
   - 回転が PDF の `/Rotate` 指定によるものか、画像そのものが回っているのかも見ておく
3. **黒い縁**：ページの外側に、ほぼ真っ黒（明るさ 0.35 未満）の帯がある
4. **色**：白黒のページが主で、紙が黄ばんでいる、または濃さがばらつく。カラーページは表紙や口絵くらい

## 4. 調べ方

### 4-1. 準備

```powershell
git clone https://github.com/marugenyori/pdf_viewer.git
cd pdf_viewer
pip install pymupdf numpy
$env:PYTHONUTF8 = "1"   # 日本語のファイル名・パスを正しく扱うため
```

iCloud にしかないファイル（エクスプローラーで雲のマーク）は、開いたときにダウンロードされるので時間がかかります。先に ScanSnap Home フォルダを右クリック →「このデバイス上に常に保持する」にしておくと早く進みます。

### 4-2. 全体の数値を取る

```powershell
python tools/survey_scans.py "C:\Users\yfb31\Documents\icloud同期フォルダ\iCloudDrive\ScanSnap Home" --samples "$env:USERPROFILE\Desktop\scan_samples"
```

- `docs/scan_survey.md`：要約（冊数、横長ページの数、`/Rotate` の内訳、黒い縁の幅、紙の黄ばみ、カラー判定、埋め込み画像の形式と dpi）
- `docs/scan_survey.json`：1ページごとの数値
- デスクトップの `scan_samples`：1冊あたり 8 ページの見本 PNG（長辺 600px）

解析は `PageAnalyzer.swift` と同じしきい値で行うので、「アプリならこのページをどう判定するか」がわかります。

### 4-3. 見本を目で見る

`scan_samples` の PNG を何枚か開いて（Claude なら Read で画像として読めます）、3 の前提と見比べてください。特に次の点を見ます。

- 横長のページは「横向きにスキャンされた 1 ページ」なのか「見開き 2 ページ」なのか
- 黒い縁の色（真っ黒か、灰色か、影のようなグラデーションか）と幅
- 紙の色のばらつき、裏写り、カラーページの割合

## 5. 調整する場所

| やりたいこと | 場所 |
|---|---|
| 黒い縁のしきい値（明るさ 0.35、割合 85%、各辺 15% まで） | `MangaViewer/Processing/PageAnalyzer.swift` の `findBlackEdges` |
| 紙とインクの色（上位 12%、下位 1%、白にする位置 0.97） | 同 `paperAndInk` |
| カラーページの判定（色の濃さ 0.2、割合 3%） | 同 `detectColor` |
| 余白を詰める（各辺 20% まで、残す余白 1.5%） | 同 `findContent` |
| 向きの判定（Vision の文字認識） | 同 `detectRotation`、使う側は `ReaderModel.rotation(for:)` |
| 補正のかけ方（切り取り・色・回転） | `MangaViewer/Processing/ImageOps.swift` の `process` |
| 設定の既定値 | `MangaViewer/Models/CorrectionSettings.swift` |

- `tools/survey_scans.py` のしきい値は `PageAnalyzer.swift` と同じ値にしてある。**片方を変えたら、もう片方も変える**
- 解析方法を変えたら `PageAnalysis.currentVersion`（`Models/BookState.swift`）を 1 上げる。そうしないと、アプリに保存された古い解析結果が使われ続ける

## 6. 守ってほしいこと

- **PDF や見本画像（PNG）はリポジトリに入れない**（市販の漫画をスキャンしたもので、著作物のため）。コミットしてよいのは `docs/scan_survey.md` と `.json` の数値だけ。ファイル名（書名）が入るので、リポジトリは非公開のままにする
- PC には Xcode がないので、Swift のビルド確認は `main` に push して GitHub Actions で行う。エラーは実行結果ページの「ビルド結果」に出る
- コミットの前に `git status` を見て、画像や PDF が混ざっていないか確かめる

## 7. 終わったら

1. 調べた結果（前提が合っていたか、何を変えたか）を、この下の「8. 自宅での調査結果」に書き足す
2. `main` に push して、CI のビルドが通ることを確かめる
3. ビルドが通ったら、Actions → iOS Build → Run workflow →「TestFlight にアップロードする」にチェックして実行（Apple 側の登録と Secrets が済んでいれば）
4. iPhone の TestFlight で入れて、実際の本で次を確かめる
   - フォルダを選べるか（iCloud Drive → ScanSnap Home）
   - 横向き・逆さまのページが直るか。直らないページは、回転ボタンで直せるか
   - 「補正前を表示」と見比べて、色・縁・余白がよくなっているか

## 8. 自宅での調査結果

（ここに書き足す）
