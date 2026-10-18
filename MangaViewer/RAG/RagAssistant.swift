import Foundation

/// 誌面検索（RAG）。質問から検索キーワードを作り、索引で探し、当たったページの文字をもとに AI が答える
enum RagAssistant {
    struct Answer {
        var text: String
        var sources: [RagIndex.Hit]
        var engineName: String
    }

    private static let keywordInstructions = """
    あなたは、技術雑誌のバックナンバーを全文検索するための検索語を作る係です。
    質問に答えるのに役立つページを探すための検索語を、5〜8個、JSON の文字列の配列だけで答えてください。
    表記ゆれ（英語と日本語、略語と正式名、カタカナの書き方の違い）も別々の語として入れてください。
    カタカナは「インターフェース」「インタフェイス」のような書き方の違い、英語は「USB」「universal serial bus」のような言い方の違いも入れてください。
    検索語は2文字以上の、その話題に特有の言葉にしてください（「方法」「について」のような一般的な言葉は入れない）。
    例: ["USB", "エニュメレーション", "enumeration", "ディスクリプタ", "descriptor"]
    """

    private static let answerInstructions = """
    あなたは、技術雑誌のバックナンバーに詳しい調べ物の相棒です。
    渡された誌面の抜き出しだけを根拠に、日本語で分かりやすく答えてください。
    抜き出しは OCR（文字認識）の結果なので、濁点の誤り（「ビット」が「ピット」）、形の似た漢字の誤り、
    図やソースコードの部分の意味のない文字の並びが混ざっています。誤りは文脈で読み替え、意味のない部分は無視してください。
    根拠にした誌面は、文の終わりに [番号] の形で示してください（番号は渡した抜き出しの番号）。
    抜き出しに答えがないときは、そう伝えたうえで、近い内容が載っている号やページを挙げてください。
    抜き出しの文章を長く書き写すことはしないでください。
    """

    static func answer(question: String, indexes: [RagIndex], engine: AskEngine) async throws -> Answer {
        let backend = engine.backend
        let useClaude = backend == .claude

        // 1. 検索キーワードを作る（AI が使えなければ、質問の言葉そのものを使う）。
        //    ショートカット経由の AI は、ショートカットを2回呼ぶことになるので、検索語は作らせない
        var keywords = plainKeywords(question)
        if !backend.isShortcut,
           let generated = try? await generateKeywords(question, useClaude: useClaude), !generated.isEmpty {
            keywords = generated + keywords
        }

        // 2. 索引で探す
        let hits = indexes.flatMap { $0.search(keywords, limit: 20) }
            .sorted { $0.score > $1.score }
        let top = Array(hits.prefix(backend == .claude ? 8 : backend.isShortcut ? 4 : 3))
        guard !top.isEmpty else {
            return Answer(text: "誌面から関係しそうなページが見つかりませんでした。言葉を変えて聞いてみてください。（検索語: \(keywords.joined(separator: "、"))）",
                          sources: [], engineName: "")
        }

        // 3. 当たったページの文字をもとに答える
        // iPhone 内の AI は一度に読める量が少ないので、抜き出しを短くする
        // ChatGPT へはショートカットの URL で渡すので、こちらも長くしすぎない
        let limit = backend == .claude ? 3000 : backend.isShortcut ? 1200 : 450
        let excerpts = top.enumerated().map { i, hit in
            "[\(i + 1)] \(hit.page.file) の \(hit.page.page + 1) ページ\n\(String(hit.page.text.prefix(limit)))"
        }.joined(separator: "\n\n")
        let prompt = "誌面の抜き出し:\n\(excerpts)\n\n質問: \(question)"
        if useClaude {
            let text = try await ClaudeClient.ask(system: answerInstructions, text: prompt, images: [])
            return Answer(text: text, sources: top, engineName: "Claude")
        }
        if case .shortcut(let ai) = backend {
            let text = try await ChatGPTBridge.shared.ask(prompt: "\(answerInstructions)\n\n\(prompt)", image: nil, via: ai)
            return Answer(text: text, sources: top, engineName: ai.displayName)
        }
        let text = try await OnDeviceAI.ask(instructions: answerInstructions, prompt: prompt)
        return Answer(text: text, sources: top, engineName: "iPhone 内の AI")
    }

    /// キーワード検索だけ（AI を使わない）
    static func keywordSearch(_ query: String, indexes: [RagIndex]) -> [RagIndex.Hit] {
        indexes.flatMap { $0.search(plainKeywords(query), limit: 50) }.sorted { $0.score > $1.score }
    }

    /// 空白や句読点で区切った言葉
    static func plainKeywords(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func generateKeywords(_ question: String, useClaude: Bool) async throws -> [String] {
        let raw: String
        if useClaude {
            raw = try await ClaudeClient.ask(system: keywordInstructions, text: question, images: [])
        } else {
            raw = try await OnDeviceAI.ask(instructions: keywordInstructions, prompt: question)
        }
        guard let start = raw.firstIndex(of: "["), let end = raw.lastIndex(of: "]"), start < end,
              let data = String(raw[start...end]).data(using: .utf8),
              let words = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return words
    }
}
