import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

enum ImageOps {
    /// 色の管理をしない（sRGB の値のまま計算する）CIContext
    static let context = CIContext(options: [.workingColorSpace: NSNull(), .cacheIntermediates: false])

    /// 時計回りに 0/90/180/270 度回す
    static func rotate(_ image: CGImage, clockwise degrees: Int) -> CGImage? {
        let angle = ((degrees % 360) + 360) % 360
        if angle == 0 { return image }
        let w = image.width, h = image.height
        let outW = angle == 180 ? w : h
        let outH = angle == 180 ? h : w
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: outW, height: outH, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        applyRotation(ctx, clockwise: angle, width: CGFloat(w), height: CGFloat(h))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    /// 幅 width・高さ height のものを時計回りに回して描けるよう、座標系を変える（CG の y は上向き）
    static func applyRotation(_ ctx: CGContext, clockwise angle: Int, width: CGFloat, height: CGFloat) {
        switch angle {
        case 90:
            ctx.translateBy(x: 0, y: width)
            ctx.rotate(by: -.pi / 2)
        case 180:
            ctx.translateBy(x: width, y: height)
            ctx.rotate(by: .pi)
        case 270:
            ctx.translateBy(x: height, y: 0)
            ctx.rotate(by: .pi / 2)
        default:
            break
        }
    }

    /// 切り取り・色の補正・回転をまとめて行う
    static func process(_ image: CGImage, crop: NormRect, color: ColorTransform?, clockwise angle: Int,
                        skew: Double = 0) -> CGImage? {
        var ci = CIImage(cgImage: image)
        let W = Double(image.width), H = Double(image.height)

        if crop != .full {
            // CIImage は左下が原点
            let rect = CGRect(x: crop.x * W, y: (1 - crop.y - crop.h) * H, width: crop.w * W, height: crop.h * H).integral
            ci = ci.cropped(to: rect)
        }

        if abs(skew) >= 0.5 {
            // 傾き（見た目で時計回り skew 度）を、中心のまわりに反時計回りへ戻す。
            // 回して空いた角は紙の色で埋め、大きさは元のまま
            let frame = ci.extent
            let center = CGPoint(x: frame.midX, y: frame.midY)
            let turn = CGAffineTransform(translationX: center.x, y: center.y)
                .rotated(by: CGFloat(skew) * .pi / 180)
                .translatedBy(x: -center.x, y: -center.y)
            let paper = CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: frame)
            ci = ci.transformed(by: turn).composited(over: paper).cropped(to: frame)
        }

        if let color {
            let matrix = CIFilter.colorMatrix()
            matrix.inputImage = ci
            let s = (0..<3).map { 1 / max(0.05, color.white[$0] - color.black[$0]) }
            matrix.rVector = CIVector(x: s[0], y: 0, z: 0, w: 0)
            matrix.gVector = CIVector(x: 0, y: s[1], z: 0, w: 0)
            matrix.bVector = CIVector(x: 0, y: 0, z: s[2], w: 0)
            matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
            matrix.biasVector = CIVector(x: -color.black[0] * s[0], y: -color.black[1] * s[1], z: -color.black[2] * s[2], w: 0)
            ci = matrix.outputImage ?? ci

            let clamp = CIFilter.colorClamp()
            clamp.inputImage = ci
            clamp.minComponents = CIVector(x: 0, y: 0, z: 0, w: 0)
            clamp.maxComponents = CIVector(x: 1, y: 1, z: 1, w: 1)
            ci = clamp.outputImage ?? ci

            if color.grayscale {
                let mono = CIFilter.colorControls()
                mono.inputImage = ci
                mono.saturation = 0
                ci = mono.outputImage ?? ci
            }
            if abs(color.gamma - 1) > 0.01 {
                let gamma = CIFilter.gammaAdjust()
                gamma.inputImage = ci
                gamma.power = Float(color.gamma)
                ci = gamma.outputImage ?? ci
            }
        }

        let a = ((angle % 360) + 360) % 360
        if a != 0 {
            // y が上向きの座標では、時計回りは負の角度
            ci = ci.transformed(by: CGAffineTransform(rotationAngle: -CGFloat(a) * .pi / 180))
        }
        let extent = ci.extent.integral
        return context.createCGImage(ci, from: extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }

    struct ColorTransform {
        var black: [Double]
        var white: [Double]
        var grayscale: Bool
        var gamma: Double
    }
}
