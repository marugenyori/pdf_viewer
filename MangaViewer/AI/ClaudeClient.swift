import Foundation

/// Claude API（Messages API）に、ページの画像と質問を送って答えをもらう。
/// Swift の公式 SDK はないので、HTTP で直接呼ぶ
enum ClaudeClient {
    static let keyAccount = "anthropicAPIKey"
    static let model = "claude-opus-5-5"

    static var apiKey: String? {
        Keychain.get(keyAccount)
    }

    static var hasKey: Bool {
        !(apiKey ?? "").isEmpty
    }

    enum Failure: LocalizedError {
        case noKey
        case http(Int, String)
        case refused
        case empty

        var errorDescription: String? {
            switch self {
            case .noKey:
                "Claude の API キーが設定されていません。本棚の … →「設定」で入力してください。"
            case .http(401, _):
                "API キーが正しくありません。設定で入れ直してください。"
            case .http(402, _), .http(403, _):
                "API の利用枠（クレジット）が足りないか、使えない状態です。Claude Console で確認してください。"
            case .http(429, _):
                "混み合っているか、利用の上限に達しました。少し待ってからもう一度聞いてください。"
            case .http(let code, let message):
                "答えを受け取れませんでした（\(code)）。\(message)"
            case .refused:
                "この質問には答えられませんでした。聞き方を変えてみてください。"
            case .empty:
                "答えが空でした。もう一度聞いてください。"
            }
        }
    }

    /// images はページの JPEG（読む順）。text は質問と、それまでのやりとりをまとめたもの
    static func ask(system: String, text: String, images: [Data]) async throws -> String {
        guard let key = apiKey, !key.isEmpty else { throw Failure.noKey }

        var content: [[String: Any]] = images.map { data in
            ["type": "image",
             "source": ["type": "base64", "media_type": "image/jpeg", "data": data.base64EncodedString()]]
        }
        content.append(["type": "text", "text": text])

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": system,
            // 読書中の質問なので、考える量は少なめにして速く・安く答える
            "output_config": ["effort": "low"],
            // 安全のための判定で断られたときは、サーバー側で別のモデルが代わりに答える
            "fallbacks": "default",
            "messages": [["role": "user", "content": content]],
        ]

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let message = ((json["error"] as? [String: Any])?["message"] as? String) ?? ""
            throw Failure.http(status, message)
        }
        if json["stop_reason"] as? String == "refusal" {
            throw Failure.refused
        }
        let blocks = json["content"] as? [[String: Any]] ?? []
        let answer = blocks
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { throw Failure.empty }
        return answer
    }
}
