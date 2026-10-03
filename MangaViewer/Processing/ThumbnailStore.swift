import UIKit

/// 本棚の表紙画像。作った画像は Caches に JPEG で保存する
actor ThumbnailStore {
    static let shared = ThumbnailStore()

    private var memory: [String: UIImage] = [:]

    private var directory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func thumbnail(for book: Book, settings: CorrectionSettings) -> UIImage? {
        if let image = memory[book.key] { return image }
        let file = directory.appendingPathComponent(book.key + ".jpg")
        if let image = UIImage(contentsOfFile: file.path) {
            memory[book.key] = image
            return image
        }
        // iCloud にしかない本は、開いてダウンロードされるまで表紙を作らない
        guard book.isDownloaded,
              let document = CGPDFDocument(book.url as CFURL), document.numberOfPages > 0,
              let raw = BookRenderer.renderPDF(document, index: 0, maxPixel: 600) else { return nil }
        let analysis = PageAnalyzer.analyze(raw)
        let rotation = settings.autoRotate && analysis.isLandscape ? 90 : 0
        var crop = NormRect.full
        if settings.trimMargins { crop = analysis.contentCrop } else if settings.removeBlackEdges { crop = analysis.edgeCrop }
        let color: ImageOps.ColorTransform? = settings.colorMode == .off ? nil :
            .init(black: analysis.black, white: analysis.white,
                  grayscale: settings.colorMode == .grayscale || (settings.colorMode == .auto && !analysis.isColor),
                  gamma: settings.inkDarkness)
        let cg = ImageOps.process(raw, crop: crop, color: color, clockwise: rotation) ?? raw
        let image = UIImage(cgImage: cg)
        if let data = image.jpegData(compressionQuality: 0.8) {
            try? data.write(to: file, options: .atomic)
        }
        memory[book.key] = image
        return image
    }

    func invalidate(_ book: Book) {
        memory[book.key] = nil
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(book.key + ".jpg"))
    }
}
