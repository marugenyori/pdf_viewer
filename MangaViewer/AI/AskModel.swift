import SwiftUI
import UIKit

/// どの AI に答えてもらうか
enum AskEngine: String, CaseIterable, Identifiable {
    /// Claude の API キーがあれば Claude、なければ iPhone 内
    case auto
    case claude
    case onDevice
    /// Apple Intelligence の ChatGPT（ショートカット経由）
    case chatGPT
    /// Apple Intelligence のクラウド AI（Private Cloud Compute。ショートカット経由）
    case appleCloud

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: "自動（キーがあれば Claude）"
        case .claude: "Claude"
        case .onDevice: "iPhone 内の AI"
        case .chatGPT: "ChatGPT（ショートカット経由）"
        case .appleCloud: "Apple のクラウド AI（ショートカット経由）"
        }
    }

    /// 実際に使う AI
    var backend: AskBackend {
        switch self {
        case .auto: ClaudeClient.hasKey ? .claude : .onDevice
        case .claude: .claude
        case .onDevice: .onDevice
        case .chatGPT: .shortcut(.chatGPT)
        case .appleCloud: .shortcut(.appleCloud)
        }
    }

    static let storageKey = "askEngine"
}

enum AskBackend: Equatable {
    case claude
    case onDevice
    /// ショートカット経由（ChatGPT か Apple のクラウド AI）
    case shortcut(ShortcutAI)
}

/// 読書中の質問と答えのやりとり
struct AskEntry: Identifiable {
    let id = UUID()
    let question: String
    let pageLabel: String
    var answer: String?
    var error: String?
    var engineName = ""
}

@MainActor
final class AskModel: ObservableObject {
    @Published private(set) var entries: [AskEntry] = []
    @Published private(set) var isAsking = false

    private static let instructions = """
    あなたは、漫画や本を読んでいる人の横にいる、物知りな読書仲間です。
    読者が今開いているページについての質問に、日本語で、短く分かりやすく答えてください。
    ページの画像や文字が渡されたときは、それを手がかりに答えてください。
    分からないことや自信のないことは、推測だと分かるように書いてください。
    まだ読んでいない先の展開（ネタバレ）は、読者がはっきり求めたときだけ書いてください。
    ページの台詞や文章を長く書き写すことはしないでください。
    作品の登場人物や筋について確かな知識がないときは、知らないとはっきり書き、作り話をしないでください。
    """

    func ask(_ question: String, book: Book, pages: [Int], images: [UIImage], engine: AskEngine) async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isAsking else { return }
        let label = pages.map { "\($0 + 1)" }.joined(separator: "・")
        entries.append(AskEntry(question: trimmed, pageLabel: label))
        let index = entries.count - 1
        isAsking = true
        defer { isAsking = false }

        // それまでのやりとりは、毎回の質問に文章としてまとめて添える（会話の続きとして答えてもらうため）
        let history = entries.dropLast().suffix(6).compactMap { entry -> String? in
            guard let answer = entry.answer else { return nil }
            return "Q（\(entry.pageLabel)ページ）: \(entry.question)\nA: \(answer)"
        }.joined(separator: "\n\n")
        var context = "本: \(book.title)\n今開いているページ: \(label) ページ目"
        if !history.isEmpty {
            context += "\n\nこれまでのやりとり:\n\(history)"
        }

        do {
            if case .shortcut(let ai) = engine.backend {
                entries[index].engineName = ai.displayName
                // ショートカット経由の AI には、AI 向けの指示文（「あなたは〜です」）を付けない。
                // Apple Intelligence の ChatGPT が「応答を提供できません」と断ったため（実機で確認）。ふつうの質問の形にする
                let pageLabelText = pages.count > 1 ? "\(label) ページ目（見開き）" : "\(label) ページ目"
                // 続けての質問（「いい人？」など）が分かるよう、直前のやりとりを普通の文として添える
                let recent = entries.dropLast().suffix(2).compactMap { entry -> String? in
                    guard let answer = entry.answer else { return nil }
                    return "わたし「\(entry.question)」→ あなた「\(answer.prefix(150))」"
                }.joined(separator: "\n")
                var prompt = "『\(book.title)』の \(pageLabelText)を読んでいます。"
                if !recent.isEmpty {
                    prompt += "\nここまでのやりとり:\n\(recent)\n続けての質問です。"
                }
                prompt += "\(trimmed)（日本語で短めに答えてください。この先の展開には触れないでください。分からないことは分からないと答えてください）"
                entries[index].answer = try await ChatGPTBridge.shared.ask(prompt: prompt, image: images.first, via: ai)
            } else if engine.backend == .claude {
                entries[index].engineName = "Claude"
                let jpegs = images.compactMap { Self.jpeg($0) }
                let text = "\(context)\n\n添付の画像は、今開いているページです。\n\n質問: \(trimmed)"
                entries[index].answer = try await ClaudeClient.ask(system: Self.instructions, text: text, images: jpegs)
            } else {
                entries[index].engineName = "iPhone 内の AI"
                // iPhone 内の AI は一度に読める量が少ない（約 4,000 トークン）ので、短くまとめて渡す。
                // それでも超えたら、これまでのやりとりを外し、ページの文字も減らしてもう一度聞く
                let pageText = await OnDeviceAI.pageText(images)
                let shortHistory = entries.dropLast().suffix(2).compactMap { entry -> String? in
                    guard let answer = entry.answer else { return nil }
                    return "Q: \(entry.question)\nA: \(answer.prefix(200))"
                }.joined(separator: "\n")
                func prompt(historyText: String, pageLimit: Int) -> String {
                    var text = "本: \(book.title)\n今開いているページ: \(label) ページ目"
                    if !historyText.isEmpty { text += "\n\nこれまでのやりとり:\n\(historyText)" }
                    if !pageText.isEmpty {
                        text += "\n\nページから読み取った文字（不正確なことがあります）:\n\(pageText.prefix(pageLimit))"
                    }
                    return text + "\n\n質問: \(trimmed)"
                }
                do {
                    entries[index].answer = try await OnDeviceAI.ask(
                        instructions: Self.instructions, prompt: prompt(historyText: shortHistory, pageLimit: 1000))
                } catch OnDeviceAI.Failure.tooLong {
                    entries[index].answer = try await OnDeviceAI.ask(
                        instructions: Self.instructions, prompt: prompt(historyText: "", pageLimit: 300))
                }
            }
        } catch {
            entries[index].error = error.localizedDescription
        }
    }

    func clear() {
        entries = []
    }

    /// 送る画像は、長辺 1568px 以下の JPEG にする（それ以上大きくしても読み取りは良くならず、料金が増えるだけ）
    private static func jpeg(_ image: UIImage) -> Data? {
        let limit: CGFloat = 1568
        let size = image.size
        let scale = min(1, limit / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.75)
    }
}
