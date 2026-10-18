# このリポジトリについて（Claude 向けの作業メモ）

自炊した漫画（ScanSnap Home で作った PDF）を読む iOS アプリ「自炊ビューア」（SwiftUI）と、それを Mac なしでビルド・配信する GitHub Actions の設定が入っています。
持ち主は Mac を持っておらず、Windows PC と iPhone から作業します。ビルドの確認も配信も、すべて GitHub Actions（macOS ランナー）で行います。
仕組みは `marugenyori/claud_code`（PCIe学習アプリ）と同じです。

## 返答のしかた

- **日本語**で、専門用語には短い説明を添える
- 持ち主が自分で操作する手順（Apple Developer、App Store Connect、GitHub の Secrets など）は、画面の項目名どおりに番号付きで書く
- パスワード・API キー・`.p8` の中身は、チャットに貼ってもらわない。GitHub や Apple の画面に直接入力してもらう

## 本のある場所

- Windows では `C:\Users\yfb31\Documents\icloud同期フォルダ\iCloudDrive\ScanSnap Home`。iPhone では「ファイル」→ iCloud Drive → ScanSnap Home
- 1冊＝1つの PDF。スキャンの質が低く、ページが横向き・逆さま、色や濃さがページごとにばらばら、黒い縁や余白が残っている
- アプリはこのフォルダをファイル選択画面で選んでもらい、ブックマーク（security-scoped bookmark）で覚える。PDF はコピーせず、その場で読む。iCloud にしかないファイルは開くときに `NSFileCoordinator` でダウンロードする

## 構成

| パス | 内容 |
|---|---|
| `MangaViewer/App/` | `@main` の App |
| `MangaViewer/Models/` | 本棚（`LibraryStore`）、本ごとの状態の保存（`BookState`）、読書画面の状態（`ReaderModel`）、設定 |
| `MangaViewer/Processing/` | PDF の描画（`BookRenderer`）、ページの解析（`PageAnalyzer`）、補正（`ImageOps`）、表紙（`ThumbnailStore`） |
| `MangaViewer/Views/` | 本棚、読書画面、拡大表示、設定。ページ送りは「紙をめくる」（`PageCurlView`、UIPageViewController の pageCurl。右綴じは綴じ目を右に置く）と「スライド」（TabView）の2通り |
| `MangaViewer.xcodeproj/` | フォルダ同期方式。`MangaViewer/` にファイルを置くだけでビルド対象になる |
| `.github/workflows/ios-build.yml` | ビルド確認と TestFlight 配信 |
| `tools/survey_scans.py` | 本のフォルダを調べて、補正の数値をまとめる（PC で実行。`PageAnalyzer` と同じしきい値） |
| `docs/HANDOFF.md` | PC の Claude への依頼：自炊 PDF の中身を調べて報告書にする |

- iOS 17 以上、Swift 5 モード、外部ライブラリなし（PDF は `CGPDFDocument`、補正は Core Image、向きの判定は Vision）

## 自動補正のしくみ（`PageAnalyzer`）

ページごとに、元の向きのまま長辺 1000px で描いて解析し、結果を本ごとの JSON（Application Support/Books）に保存する。

1. **黒い縁**：外側から、85% 以上が暗い行・列を削る（各辺 15% まで）。既定はオフ
2. **色**：明るいほう上位 12% の平均を紙の色、暗いほう 3% の平均をインクの色（インクが灰色寄りなので広めに）とし、色ごとに「インク→黒、紙→白」に引き伸ばす。黄ばみもここで消える。その後も色の付いた画素が 3% を超えればカラーページ。ただし黄色の方向の色み（黄↔青の軸）は 0.3 まで差し引いてから数える（黄ばみのむらで白黒ページがカラーと誤判定されたため）
3. **余白**：インクのある行・列が出てくるまで内側へ（各辺 20% まで）。少し余白を残す。既定はオフ
4. **向き**：横長のページだけ、90°/270° の2通りで文字認識（Vision、日本語）をして、読み取れた文字の多いほうにする（差がなければ 90°）。縦長のページと1ページ目（カバー全体の横長スキャン）は回さない。横向きだったページには「上下を反対に」ボタンを出す
5. **色のモード**：「カラーは巻頭だけ」を選ぶと、9ページ目以降は必ず白黒にする（黄ばみの強い本向け）

## 実物の調査でわかったこと（2026-10、PC の Claude が全 126 ファイルを調査）

- 見開きを1枚にしたページはない。2ページ目以降の横長（約 2%）は1ページ分が横向きに入っているだけで、90° と 270° が同じ本の中でも半々ほど混ざる。回っているのは画像そのもので、`/Rotate` は使われていない
- 1ページ目は全冊とも、カバーを広げた全体の横長スキャン。逆さま（180°）のページはない
- ScanSnap が紙の形で切り抜くので、黒い縁や余白はほとんどない
- 問題は色：黄ばみが本ごとに大きく違い、インクは灰色寄り
- 紙詰まりで大きく傾いたり端が欠けたりしたページがある（第34巻 65〜71ページ、第61巻 95〜102ページ）。傾きの補正はまだない
- フォルダには漫画（ジョジョ 63 冊）のほか、雑誌 53 個、技術書・語学書 9 冊もある

- 解析方法を変えたら `PageAnalysis.currentVersion` を上げる（古い結果は捨てて解析し直す）
- 回転は「時計回りの角度」で統一。手動で回したページ（`rotationOverrides`）は自動判定より優先

## ビルドと配信

- `main` に push すると、署名なしのシミュレータ向けビルドが自動で走る（エラーは実行結果ページの「ビルド結果」にまとまる）
- TestFlight へ出すとき：Actions → iOS Build → Run workflow →「TestFlight にアップロードする」にチェック
- ビルド番号は Actions の実行番号が自動で入る
- 必要な Secrets：`APPLE_TEAM_ID`、`BUNDLE_ID`、`ASC_KEY_ID`、`ASC_ISSUER_ID`、`ASC_KEY_P8`
- Bundle ID はビルド設定 `APP_BUNDLE_ID` で渡す（既定値 `com.marugenyori.mangaviewer`、実際は Secrets の `BUNDLE_ID`）。`PRODUCT_BUNDLE_IDENTIFIER` をコマンドラインで上書きしない
- App Group などの Capability は使っていない。足すときは Apple Developer の Identifiers で App ID にも設定が必要

## コードを変えるときの注意

- **複数行文字列（`"""`）**：中の行が、閉じる `"""` より左に出るとコンパイルエラーになる
- **排他アクセスエラー**：配列を書き換えているクロージャの中から、同じ構造体・クラスのプロパティを読まない（`PageAnalyzer.Pixels` の init はローカル変数で組み立ててから代入している）
- PDF や見本画像はリポジトリに入れない（市販の漫画のスキャンで、著作物のため）。入れてよいのは `docs/scan_survey.*` の数値だけ
- 文字サイズは固定値（`.system(size:)`）を避け、`.body` や `.caption` などを使う
