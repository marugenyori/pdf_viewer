import Foundation
import UIKit
import Vision
#if canImport(FoundationModels)
import FoundationModels
#endif

/// iPhone の中だけで動く AI（Apple Intelligence。iOS 26 以降・対応機種のみ）。
/// 画像は読めないので、ページの文字を読み取って一緒に渡す
enum OnDeviceAI {
    enum Failure: LocalizedError {
        case unavailable(String)

        var errorDescription: String? {
            switch self {
            case .unavailable(let reason): reason
            }
        }
    }

    /// 使えるか。使えないときは理由
    static var status: (available: Bool, reason: String) {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return (true, "")
            case .unavailable(.deviceNotEligible):
                return (false, "この iPhone は Apple Intelligence に対応していません（iPhone 15 Pro 以降が必要）。")
            case .unavailable(.appleIntelligenceNotEnabled):
                return (false, "設定アプリ →「Apple Intelligence と Siri」で Apple Intelligence をオンにしてください。")
            case .unavailable(.modelNotReady):
                return (false, "Apple Intelligence の準備中です（モデルのダウンロード中）。しばらくしてから使ってください。")
            case .unavailable:
                return (false, "Apple Intelligence が使えない状態です。")
            }
        }
        #endif
        return (false, "iPhone 内の AI には iOS 26 以降が必要です。")
    }

    static func ask(instructions: String, prompt: String) async throws -> String {
        let current = status
        guard current.available else { throw Failure.unavailable(current.reason) }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #endif
        throw Failure.unavailable(current.reason)
    }

    /// ページの文字を読み取る（漫画の縦書きは読み取りにくいので、取れた分だけ）
    static func pageText(_ images: [UIImage]) async -> String {
        await Task.detached(priority: .userInitiated) {
            images.compactMap { image -> String? in
                guard let cg = image.cgImage else { return nil }
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["ja-JP", "en-US"]
                request.usesLanguageCorrection = true
                try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
                let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                return lines.isEmpty ? nil : lines.joined(separator: "\n")
            }.joined(separator: "\n---\n")
        }.value
    }
}
