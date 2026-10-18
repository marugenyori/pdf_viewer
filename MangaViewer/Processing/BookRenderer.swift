import CoreGraphics
import Foundation
import UIKit

/// 1冊の PDF からページ画像を作る。PDF の読み込みは同時に1つずつ行う
actor BookRenderer {
    private let document: CGPDFDocument
    nonisolated let pageCount: Int

    init?(url: URL) {
        guard let document = CGPDFDocument(url as CFURL), document.numberOfPages > 0 else { return nil }
        self.document = document
        self.pageCount = document.numberOfPages
    }

    /// ページを解析する。detectRotation が true なら文字で向きも判定する
    func analyze(page index: Int, existing: PageAnalysis?, detectRotation: Bool) -> PageAnalysis? {
        var result = existing
        if result == nil {
            guard let raw = Self.renderPDF(document, index: index, maxPixel: 1000) else { return nil }
            result = PageAnalyzer.analyze(raw)
            if result?.isLandscape == false {
                // 縦長のページは回さない（文字認識もしない）
                result?.autoRotation = 0
                result?.rotationConfident = true
            } else if detectRotation {
                let (angle, confident) = PageAnalyzer.detectRotation(raw)
                result?.autoRotation = angle
                result?.rotationConfident = confident
            }
        } else if detectRotation, result?.autoRotation == nil {
            guard let raw = Self.renderPDF(document, index: index, maxPixel: 1000) else { return result }
            let (angle, confident) = PageAnalyzer.detectRotation(raw)
            result?.autoRotation = angle
            result?.rotationConfident = confident
        }
        return result
    }

    /// 補正したページ画像を作る。bypass が true なら補正せずにそのまま
    func render(page index: Int, maxPixel: CGFloat, analysis: PageAnalysis?, rotation: Int,
                settings: CorrectionSettings, bypass: Bool) -> UIImage? {
        guard let analysis, !bypass else {
            guard let raw = Self.renderPDF(document, index: index, maxPixel: maxPixel) else { return nil }
            return UIImage(cgImage: raw)
        }
        let crop: NormRect
        if settings.trimMargins {
            crop = analysis.contentCrop
        } else if settings.removeBlackEdges {
            crop = analysis.edgeCrop
        } else {
            crop = .full
        }
        // 切り取ったあとの長辺が maxPixel 前後になるよう、元のページは大きめに描く
        let fraction = max(0.3, max(crop.w, crop.h))
        let rawMax = min(4000, maxPixel / CGFloat(fraction))
        guard let raw = Self.renderPDF(document, index: index, maxPixel: rawMax) else { return nil }

        let color: ImageOps.ColorTransform?
        switch settings.colorMode {
        case .off:
            color = nil
        case .auto:
            color = .init(black: analysis.black, white: analysis.white, grayscale: !analysis.isColor, gamma: settings.inkDarkness)
        case .frontColorOnly:
            let mayBeColor = index < ColorMode.frontColorPages && analysis.isColor
            color = .init(black: analysis.black, white: analysis.white, grayscale: !mayBeColor, gamma: settings.inkDarkness)
        case .grayscale:
            color = .init(black: analysis.black, white: analysis.white, grayscale: true, gamma: settings.inkDarkness)
        case .color:
            color = .init(black: analysis.black, white: analysis.white, grayscale: false, gamma: settings.inkDarkness)
        }
        guard let processed = ImageOps.process(raw, crop: crop, color: color, clockwise: rotation) else {
            return UIImage(cgImage: raw)
        }
        return UIImage(cgImage: processed)
    }

    /// PDF のページを、長辺が maxPixel の画像にする（PDF 自体の回転指定も反映）
    static func renderPDF(_ document: CGPDFDocument, index: Int, maxPixel: CGFloat) -> CGImage? {
        guard let page = document.page(at: index + 1) else { return nil }
        let box = page.getBoxRect(.mediaBox)
        guard box.width > 0, box.height > 0 else { return nil }
        let angle = ((Int(page.rotationAngle) % 360) + 360) % 360
        let sideways = angle == 90 || angle == 270
        let shownW = sideways ? box.height : box.width
        let shownH = sideways ? box.width : box.height
        let scale = maxPixel / max(shownW, shownH)
        let w = max(1, Int((shownW * scale).rounded()))
        let h = max(1, Int((shownH * scale).rounded()))

        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .high
        ctx.scaleBy(x: scale, y: scale)
        ImageOps.applyRotation(ctx, clockwise: angle, width: box.width, height: box.height)
        ctx.translateBy(x: -box.minX, y: -box.minY)
        ctx.drawPDFPage(page)
        return ctx.makeImage()
    }
}
