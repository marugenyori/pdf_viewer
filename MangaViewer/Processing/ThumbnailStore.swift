import UIKit

/// 本棚の表紙画像。作った画像は Caches に JPEG で保存する
actor ThumbnailStore {
    static let shared = ThumbnailStore()

    private var memory: [String: UIImage] = [:]
    /// 作成中の表紙（同じ本を二重にダウンロードしないため）
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    private var directory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func thumbnail(for book: Book, settings: CorrectionSettings) async -> UIImage? {
        if let image = memory[book.key] { return image }
        let file = directory.appendingPathComponent(book.key + ".jpg")
        if let image = UIImage(contentsOfFile: file.path) {
            memory[book.key] = image
            return image
        }
        if let running = inFlight[book.key] { return await running.value }
        // 画面から消えた本のためには、ダウンロードを始めない
        if Task.isCancelled { return nil }

        let task = Task.detached(priority: .utility) { () -> UIImage? in
            await Self.makeCover(for: book, settings: settings)
        }
        inFlight[book.key] = task
        let image = await task.value
        inFlight[book.key] = nil
        if let image {
            if let data = image.jpegData(compressionQuality: 0.8) {
                try? data.write(to: file, options: .atomic)
            }
            memory[book.key] = image
        }
        return image
    }

    /// 表紙を作る。iCloud にしかない本は一時的にダウンロードし、作り終えたら iPhone から消す
    private static func makeCover(for book: Book, settings: CorrectionSettings) async -> UIImage? {
        let wasLocal = CoverDownloader.isLocal(book.url)
        if !wasLocal {
            guard CoverDownloader.mayDownload, await CoverDownloader.download(book.url) else { return nil }
        }
        defer {
            if !wasLocal { CoverDownloader.evict(book) }
        }
        return render(book: book, settings: settings)
    }

    private static func render(book: Book, settings: CorrectionSettings) -> UIImage? {
        guard let document = CGPDFDocument(book.url as CFURL), document.numberOfPages > 0,
              let raw = BookRenderer.renderPDF(document, index: 0, maxPixel: 600) else { return nil }
        let analysis = PageAnalyzer.analyze(raw)
        var crop = NormRect.full
        if settings.trimMargins { crop = analysis.contentCrop } else if settings.removeBlackEdges { crop = analysis.edgeCrop }
        if analysis.isLandscape {
            // 1ページ目はカバーを広げた全体（左から 折り返し・裏表紙・背・表表紙・折り返し、約 1049×498pt）。
            // 表表紙（約 303pt 幅＝全体の 0.29）は右の折り返しの左にある。折り返しの幅は推定（全体の約 0.2）
            crop = NormRect(x: 0.51, y: crop.y, w: 0.29, h: crop.h)
        }
        let color: ImageOps.ColorTransform? = settings.colorMode == .off ? nil :
            .init(black: analysis.black, white: analysis.white,
                  grayscale: settings.colorMode == .grayscale || (settings.colorMode != .color && !analysis.isColor),
                  gamma: settings.inkDarkness)
        let cg = ImageOps.process(raw, crop: crop, color: color, clockwise: 0) ?? raw
        return UIImage(cgImage: cg)
    }

    func invalidate(_ book: Book) {
        memory[book.key] = nil
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(book.key + ".jpg"))
    }
}
