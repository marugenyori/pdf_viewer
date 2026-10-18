import CoreGraphics
import Foundation
import Vision

/// ページ画像を調べて、切り取る範囲・紙とインクの色・向きを求める
enum PageAnalyzer {

    // MARK: - 画素の読み出し

    /// 縮小した RGBA の画素（上の行から順に並ぶ）
    struct Pixels {
        let width: Int
        let height: Int
        let data: [UInt8]

        init?(image: CGImage, maxSide: Int) {
            let scale = min(1, Double(maxSide) / Double(max(image.width, image.height)))
            let w = max(1, Int(Double(image.width) * scale))
            let h = max(1, Int(Double(image.height) * scale))
            var buffer = [UInt8](repeating: 0, count: w * h * 4)
            let drawn = buffer.withUnsafeMutableBytes { ptr -> Bool in
                guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                      let ctx = CGContext(data: ptr.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: w * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
                ctx.interpolationQuality = .medium
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            guard drawn else { return nil }
            width = w
            height = h
            data = buffer
        }

        @inline(__always) func rgb(_ x: Int, _ y: Int) -> (Double, Double, Double) {
            let i = (y * width + x) * 4
            return (Double(data[i]) / 255, Double(data[i + 1]) / 255, Double(data[i + 2]) / 255)
        }

        @inline(__always) func luma(_ x: Int, _ y: Int) -> Double {
            let (r, g, b) = rgb(x, y)
            return 0.299 * r + 0.587 * g + 0.114 * b
        }
    }

    /// 画素の範囲（両端を含まない right / bottom）
    struct Box {
        var left: Int
        var top: Int
        var right: Int
        var bottom: Int

        var width: Int { right - left }
        var height: Int { bottom - top }

        func normalized(in pixels: Pixels) -> NormRect {
            NormRect(x: Double(left) / Double(pixels.width),
                     y: Double(top) / Double(pixels.height),
                     w: Double(width) / Double(pixels.width),
                     h: Double(height) / Double(pixels.height))
        }
    }

    // MARK: - 解析

    /// 色と切り取り範囲を求める（回転の判定は別）
    static func analyze(_ image: CGImage) -> PageAnalysis {
        let isLandscape = Double(image.width) > Double(image.height) * 1.08
        guard let px = Pixels(image: image, maxSide: 600) else {
            return PageAnalysis(edgeCrop: .full, contentCrop: .full, black: [0, 0, 0], white: [1, 1, 1],
                                isColor: false, isLandscape: isLandscape)
        }
        let edge = findBlackEdges(px)
        let (black, white) = paperAndInk(px, in: edge)
        let isColor = detectColor(px, in: edge, black: black, white: white)
        let content = findContent(px, in: edge, black: black, white: white)
        return PageAnalysis(edgeCrop: edge.normalized(in: px), contentCrop: content.normalized(in: px),
                            black: black, white: white, isColor: isColor, isLandscape: isLandscape)
    }

    /// 外側から内側へ、ほとんどが暗い行・列（スキャナの背景や影）を削る
    private static func findBlackEdges(_ px: Pixels) -> Box {
        let maxRows = px.height * 15 / 100
        let maxCols = px.width * 15 / 100

        func rowIsDark(_ y: Int, _ x0: Int, _ x1: Int) -> Bool {
            var dark = 0
            for x in x0..<x1 where px.luma(x, y) < 0.35 { dark += 1 }
            return Double(dark) > Double(x1 - x0) * 0.85
        }
        func colIsDark(_ x: Int, _ y0: Int, _ y1: Int) -> Bool {
            var dark = 0
            for y in y0..<y1 where px.luma(x, y) < 0.35 { dark += 1 }
            return Double(dark) > Double(y1 - y0) * 0.85
        }

        var box = Box(left: 0, top: 0, right: px.width, bottom: px.height)
        while box.top < maxRows, rowIsDark(box.top, 0, px.width) { box.top += 1 }
        while px.height - box.bottom < maxRows, rowIsDark(box.bottom - 1, 0, px.width) { box.bottom -= 1 }
        while box.left < maxCols, colIsDark(box.left, box.top, box.bottom) { box.left += 1 }
        while px.width - box.right < maxCols, colIsDark(box.right - 1, box.top, box.bottom) { box.right -= 1 }

        // 縁と紙の境目のぼやけた線も消すため、削った辺は少しだけ余分に削る
        let extraX = max(1, px.width / 200)
        let extraY = max(1, px.height / 200)
        if box.left > 0 { box.left += extraX }
        if box.right < px.width { box.right -= extraX }
        if box.top > 0 { box.top += extraY }
        if box.bottom < px.height { box.bottom -= extraY }

        if box.width < px.width / 2 || box.height < px.height / 2 {
            return Box(left: 0, top: 0, right: px.width, bottom: px.height)
        }
        return box
    }

    /// 紙の色（明るい側）とインクの色（暗い側）を求める
    private static func paperAndInk(_ px: Pixels, in box: Box) -> ([Double], [Double]) {
        var histogram = [Int](repeating: 0, count: 256)
        for y in box.top..<box.bottom {
            for x in box.left..<box.right {
                histogram[min(255, Int(px.luma(x, y) * 255))] += 1
            }
        }
        let total = histogram.reduce(0, +)
        func percentile(_ p: Double) -> Double {
            let target = Int(Double(total) * p)
            var sum = 0
            for (i, n) in histogram.enumerated() {
                sum += n
                if sum > target { return Double(i) / 255 }
            }
            return 1
        }
        let paperLo = percentile(0.88)
        let paperHi = percentile(0.995)
        let inkHi = percentile(0.03)  // インクが灰色寄り（中央 0.24）なので、少し広めに取って黒側を強めに引き伸ばす

        var paper = [0.0, 0.0, 0.0], paperN = 0.0
        var ink = [0.0, 0.0, 0.0], inkN = 0.0
        for y in box.top..<box.bottom {
            for x in box.left..<box.right {
                let (r, g, b) = px.rgb(x, y)
                let l = 0.299 * r + 0.587 * g + 0.114 * b
                if l >= paperLo && l <= paperHi {
                    paper[0] += r; paper[1] += g; paper[2] += b; paperN += 1
                }
                if l <= inkHi {
                    ink[0] += r; ink[1] += g; ink[2] += b; inkN += 1
                }
            }
        }
        var white = paperN > 0 ? paper.map { $0 / paperN } : [1, 1, 1]
        var black = inkN > 0 ? ink.map { $0 / inkN } : [0, 0, 0]

        // 暗いページ（全面ベタなど）で紙の色を見誤ったときは、白はいじらない
        let whiteLuma = 0.299 * white[0] + 0.587 * white[1] + 0.114 * white[2]
        if whiteLuma < 0.55 { white = [1, 1, 1] }
        // 紙がほんの少し灰色でも真っ白になるよう、少し手前で白にする
        white = white.map { min(1, $0 * 0.97) }
        // インクは暗いものだけを黒とみなす
        black = black.map { min($0, 0.3) }
        for i in 0..<3 where white[i] - black[i] < 0.35 {
            black[i] = max(0, white[i] - 0.35)
        }
        return (black, white)
    }

    @inline(__always) private static func mapped(_ v: Double, _ i: Int, _ black: [Double], _ white: [Double]) -> Double {
        min(1, max(0, (v - black[i]) / (white[i] - black[i])))
    }

    /// 黄ばみの方向（黄 ↔ 青の軸）の単位ベクトル (1, 1, -2) / √6
    private static let yellowAxis = (1 / 6.0.squareRoot(), 1 / 6.0.squareRoot(), -2 / 6.0.squareRoot())
    /// 黄色みとして差し引く量の上限。これを超える黄色はインクの色とみなす
    private static let yellowAllowance = 0.3

    /// 紙の黄ばみを取り除いたあとも、はっきり色の付いた画素が一定以上あればカラーページ。
    /// 黄ばみの強い本は、紙を白にそろえても中間の灰色に黄色みが残り、白黒ページがカラーと誤判定された
    /// （調査で第25・31・37巻など）。そこで黄色の方向の色みを一定量まで差し引いてから判定する
    private static func detectColor(_ px: Pixels, in box: Box, black: [Double], white: [Double]) -> Bool {
        var colored = 0
        var counted = 0
        for y in stride(from: box.top, to: box.bottom, by: 2) {
            for x in stride(from: box.left, to: box.right, by: 2) {
                let (r0, g0, b0) = px.rgb(x, y)
                let r = mapped(r0, 0, black, white)
                let g = mapped(g0, 1, black, white)
                let b = mapped(b0, 2, black, white)
                counted += 1
                let l = 0.299 * r + 0.587 * g + 0.114 * b
                guard l > 0.08 && l < 0.95 else { continue }
                let mean = (r + g + b) / 3
                var c = (r - mean, g - mean, b - mean)
                let along = c.0 * yellowAxis.0 + c.1 * yellowAxis.1 + c.2 * yellowAxis.2
                let removed = min(max(along, 0), yellowAllowance)
                c = (c.0 - removed * yellowAxis.0, c.1 - removed * yellowAxis.1, c.2 - removed * yellowAxis.2)
                if max(c.0, c.1, c.2) - min(c.0, c.1, c.2) > 0.2 { colored += 1 }
            }
        }
        return counted > 0 && Double(colored) / Double(counted) > 0.03
    }

    /// 白い余白を詰めた範囲。インクのある行・列が出てくるまで内側へ進む
    private static func findContent(_ px: Pixels, in box: Box, black: [Double], white: [Double]) -> Box {
        func isInk(_ x: Int, _ y: Int) -> Bool {
            let (r, g, b) = px.rgb(x, y)
            let l = 0.299 * mapped(r, 0, black, white) + 0.587 * mapped(g, 1, black, white) + 0.114 * mapped(b, 2, black, white)
            return l < 0.5
        }
        func rowHasInk(_ y: Int, _ x0: Int, _ x1: Int) -> Bool {
            let need = max(2, (x1 - x0) * 3 / 1000)
            var n = 0
            for x in x0..<x1 where isInk(x, y) {
                n += 1
                if n >= need { return true }
            }
            return false
        }
        func colHasInk(_ x: Int, _ y0: Int, _ y1: Int) -> Bool {
            let need = max(2, (y1 - y0) * 3 / 1000)
            var n = 0
            for y in y0..<y1 where isInk(x, y) {
                n += 1
                if n >= need { return true }
            }
            return false
        }

        let maxRows = box.height * 20 / 100
        let maxCols = box.width * 20 / 100
        var c = box
        while c.top - box.top < maxRows, !rowHasInk(c.top, box.left, box.right) { c.top += 1 }
        while box.bottom - c.bottom < maxRows, !rowHasInk(c.bottom - 1, box.left, box.right) { c.bottom -= 1 }
        while c.left - box.left < maxCols, !colHasInk(c.left, c.top, c.bottom) { c.left += 1 }
        while box.right - c.right < maxCols, !colHasInk(c.right - 1, c.top, c.bottom) { c.right -= 1 }

        // ぎりぎりで切ると窮屈なので、少しだけ余白を残す
        let padX = box.width * 15 / 1000
        let padY = box.height * 15 / 1000
        c.left = max(box.left, c.left - padX)
        c.right = min(box.right, c.right + padX)
        c.top = max(box.top, c.top - padY)
        c.bottom = min(box.bottom, c.bottom + padY)
        if c.width < box.width / 2 || c.height < box.height / 2 { return box }
        return c
    }

    // MARK: - 向きの判定

    /// 横向きのページを、文字認識のしやすさで 90° と 270° のどちらに回すか判定する（時計回りの角度、自信があるか）。
    /// 調査では逆さま（180°）のページはなく、縦長のページは回さなくてよいので、横長のページだけを調べる
    static func detectRotation(_ image: CGImage) -> (Int, Bool) {
        let isLandscape = Double(image.width) > Double(image.height) * 1.08
        guard isLandscape else { return (0, true) }
        let candidates = [90, 270]
        let scores = candidates.map { angle -> Double in
            guard let rotated = ImageOps.rotate(image, clockwise: angle) else { return 0 }
            return textScore(rotated)
        }
        let (a, b) = (scores[0], scores[1])
        let confident = max(a, b) >= 6 && max(a, b) > min(a, b) * 1.5
        return (a >= b ? 90 : 270, confident)
    }

    /// 読み取れた文字の量（確からしさ × 文字数の合計）
    private static func textScore(_ image: CGImage) -> Double {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ja-JP", "en-US"]
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return 0
        }
        var score = 0.0
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first, candidate.confidence >= 0.4 else { continue }
            score += Double(candidate.confidence) * Double(candidate.string.count)
        }
        return score
    }
}
