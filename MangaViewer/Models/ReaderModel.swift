import SwiftUI
import UIKit

/// 読書画面の状態。ページ画像の作成と、前後ページの先読みを受け持つ
@MainActor
final class ReaderModel: ObservableObject {
    enum Phase {
        case loading(String)
        case failed(String)
        case ready
    }

    let book: Book
    @Published private(set) var phase: Phase = .loading("準備しています…")
    @Published private(set) var state: BookState
    @Published private(set) var images: [Int: UIImage] = [:]
    @Published private(set) var pageCount = 0
    /// 表示中の「見開き（または1ページ）」の番号
    @Published var spreadIndex = 0 {
        didSet { spreadChanged() }
    }
    /// 補正前の画像を表示する（比べるため）
    @Published var bypass = false {
        didSet { if bypass != oldValue { invalidateAll() } }
    }
    @Published private(set) var isLandscape = false

    private var renderer: BookRenderer?
    private var loadTask: Task<Void, Never>?
    /// 設定を変えたら増やす。古い設定で作った画像を捨てるため
    private var generation = 0
    private let maxPixel: CGFloat = 2000

    init(book: Book, defaults: CorrectionSettings) {
        self.book = book
        self.state = BookStateStore.load(for: book, defaults: defaults)
    }

    // MARK: - 開く・閉じる

    func open() async {
        guard renderer == nil else { return }
        if !book.isDownloaded {
            phase = .loading("iCloud からダウンロードしています…")
        }
        do {
            try await LibraryStore.ensureDownloaded(book.url)
        } catch {
            phase = .failed("ファイルを読み込めませんでした。\n\(error.localizedDescription)")
            return
        }
        let url = book.url
        let renderer = await Task.detached { BookRenderer(url: url) }.value
        guard let renderer else {
            phase = .failed("PDF を開けませんでした。")
            return
        }
        self.renderer = renderer
        pageCount = renderer.pageCount
        let start = min(max(0, state.lastPage), pageCount - 1)
        spreadIndex = indexOfSpread(containing: start)
        phase = .ready
        scheduleLoading()
    }

    func close() {
        loadTask?.cancel()
        saveState()
    }

    private func saveState() {
        guard pageCount > 0 else { return }
        BookStateStore.save(state, for: book)
        ProgressStore.shared.update(book: book, page: state.lastPage, pageCount: pageCount)
    }

    // MARK: - 見開き

    var spreadMode: Bool {
        isLandscape && state.settings.spreadInLandscape
    }

    /// 見開きごとのページ番号（読む順）
    var spreads: [[Int]] {
        guard pageCount > 0 else { return [] }
        guard spreadMode else { return (0..<pageCount).map { [$0] } }
        var result: [[Int]] = []
        var i = 0
        if state.settings.coverAlone {
            result.append([0])
            i = 1
        }
        while i < pageCount {
            result.append(i + 1 < pageCount ? [i, i + 1] : [i])
            i += 2
        }
        return result
    }

    var currentPages: [Int] {
        let all = spreads
        guard all.indices.contains(spreadIndex) else { return [] }
        return all[spreadIndex]
    }

    var currentPage: Int { currentPages.first ?? 0 }

    private func indexOfSpread(containing page: Int) -> Int {
        spreads.firstIndex { $0.contains(page) } ?? 0
    }

    func setLandscape(_ landscape: Bool) {
        guard landscape != isLandscape else { return }
        let page = currentPage
        isLandscape = landscape
        spreadIndex = indexOfSpread(containing: page)
    }

    func go(toPage page: Int) {
        let target = indexOfSpread(containing: min(max(0, page), pageCount - 1))
        if target != spreadIndex { spreadIndex = target }
    }

    func step(_ delta: Int) {
        let target = spreadIndex + delta
        guard spreads.indices.contains(target) else { return }
        withAnimation(.easeInOut(duration: 0.25)) { spreadIndex = target }
    }

    private func spreadChanged() {
        guard pageCount > 0 else { return }
        state.lastPage = currentPage
        ProgressStore.shared.update(book: book, page: state.lastPage, pageCount: pageCount)
        scheduleLoading()
    }

    // MARK: - 回転

    /// 実際に使う回転角（時計回り）
    func rotation(for page: Int) -> Int {
        if let manual = state.rotationOverrides[page] { return manual }
        // 1ページ目は、カバーを広げた全体を横長のまま1枚にスキャンしたもの。回さない
        guard page > 0, state.settings.autoRotate, let analysis = state.analyses[page] else { return 0 }
        // 横長のページは文字認識で 90° か 270° を選ぶ。判定に自信がなくても、わずかでも読めたほうを使う。
        // 調査では同じ本の中でも 90° と 270° が半々ほど混ざっていたので、ほかのページの向きには合わせない
        return analysis.autoRotation ?? (analysis.isLandscape ? 90 : 0)
    }

    /// 横向きにスキャンされていたページか（1ページ目のカバーは除く）
    func isSideways(_ page: Int) -> Bool {
        page > 0 && state.analyses[page]?.isLandscape == true
    }

    /// 横向きのページの向きを反対にする（90° ↔ 270°）。自動判定を間違えたとき用
    func flipSideways(_ page: Int) {
        state.rotationOverrides[page] = (rotation(for: page) + 180) % 360
        images[page] = nil
        generation += 1
        saveState()
        scheduleLoading()
    }

    /// 表示中のページを時計回りに回す
    func rotateCurrent(by degrees: Int) {
        for page in currentPages {
            let angle = ((rotation(for: page) + degrees) % 360 + 360) % 360
            state.rotationOverrides[page] = angle
            images[page] = nil
        }
        generation += 1
        saveState()
        scheduleLoading()
    }

    /// 表示中のページの手動の回転を取り消す
    func resetCurrentRotation() {
        for page in currentPages {
            state.rotationOverrides[page] = nil
            images[page] = nil
        }
        generation += 1
        saveState()
        scheduleLoading()
    }

    var currentHasManualRotation: Bool {
        currentPages.contains { state.rotationOverrides[$0] != nil }
    }

    // MARK: - 設定

    func updateSettings(_ settings: CorrectionSettings) {
        guard settings != state.settings else { return }
        let page = currentPage
        state.settings = settings
        invalidateAll()
        spreadIndex = indexOfSpread(containing: page)
        saveState()
    }

    /// 解析結果を捨てて、最初からやり直す
    func reanalyze() {
        state.analyses = [:]
        invalidateAll()
        saveState()
    }

    private func invalidateAll() {
        generation += 1
        images = [:]
        scheduleLoading()
    }

    // MARK: - 読み込み

    /// 今のページ → 次のページ → 前のページの順に作る
    private func scheduleLoading() {
        guard renderer != nil, pageCount > 0 else { return }
        loadTask?.cancel()
        let all = spreads
        var order: [Int] = []
        for offset in [0, 1, 2, -1, 3] {
            let i = spreadIndex + offset
            if all.indices.contains(i) { order.append(contentsOf: all[i]) }
        }
        let keep = Set(order)
        images = images.filter { keep.contains($0.key) }

        loadTask = Task { [weak self] in
            for page in order {
                if Task.isCancelled { return }
                await self?.load(page: page)
            }
            self?.saveState()
        }
    }

    private func load(page: Int) async {
        guard images[page] == nil, let renderer else { return }
        let generation = self.generation
        let settings = state.settings
        var analysis = state.analyses[page]
        if !bypass {
            let wantsRotation = page > 0 && settings.autoRotate && state.rotationOverrides[page] == nil && analysis?.autoRotation == nil
            if analysis == nil || wantsRotation {
                analysis = await renderer.analyze(page: page, existing: analysis, detectRotation: wantsRotation)
                if Task.isCancelled && analysis == nil { return }
                if let analysis { state.analyses[page] = analysis }
            }
        }
        let rotation = bypass ? 0 : self.rotation(for: page)
        let image = await renderer.render(page: page, maxPixel: maxPixel, analysis: analysis, rotation: rotation,
                                          settings: settings, bypass: bypass)
        guard generation == self.generation, let image else { return }
        images[page] = image
    }
}
