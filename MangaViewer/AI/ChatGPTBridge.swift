import SwiftUI
import UIKit

/// Apple Intelligence の ChatGPT に、ショートカット経由で質問する。
/// アプリから ChatGPT を直接呼ぶ方法は Apple が用意していないので、
/// 持ち主が作ったショートカット（「モデルを使用」で ChatGPT を選んだもの）を x-callback-url で呼び、
/// 答えを mangaviewer:// で受け取る。ページの画像はクリップボードに入れて渡す
/// ショートカット経由で使う AI。どのモデルを使うかは、ショートカットの「モデルを使用」で決まる
enum ShortcutAI: Equatable {
    case chatGPT
    /// Apple のクラウド AI（Private Cloud Compute）
    case appleCloud

    var displayName: String {
        switch self {
        case .chatGPT: "ChatGPT"
        case .appleCloud: "Apple のクラウド AI"
        }
    }

    var nameKey: String {
        switch self {
        case .chatGPT: "chatGPTShortcutName"
        case .appleCloud: "appleCloudShortcutName"
        }
    }

    var defaultName: String {
        switch self {
        case .chatGPT: "自炊ビューアに質問"
        case .appleCloud: "自炊ビューアに質問（Apple）"
        }
    }

    /// 設定で変えた名前（空なら既定の名前）
    var name: String {
        let saved = UserDefaults.standard.string(forKey: nameKey) ?? ""
        return saved.isEmpty ? defaultName : saved
    }
}

extension AskBackend {
    var isShortcut: Bool {
        if case .shortcut = self { return true }
        return false
    }
}

@MainActor
final class ChatGPTBridge {
    static let shared = ChatGPTBridge()

    enum Failure: LocalizedError {
        case cannotOpen
        case cancelled
        case shortcutError(String)
        case noAnswer
        case busy

        var errorDescription: String? {
            switch self {
            case .cannotOpen:
                "ショートカットのアプリを開けませんでした。"
            case .cancelled:
                "ショートカットが途中で止められました。"
            case .shortcutError(let message):
                "ショートカットでエラーが出ました。\(message)\nショートカットの名前が設定と同じか、「モデルを使用」でモデルを選んでいるか確かめてください。"
            case .noAnswer:
                "答えを受け取れませんでした。ショートカットの最後に「出力を停止」を置き、「応答」を出力するようにしてください。"
            case .busy:
                "前の質問の答えを待っています。"
            }
        }
    }

    private var waiting: CheckedContinuation<String, Error>?

    /// ショートカットを呼び、答えが返ってくるまで待つ
    func ask(prompt: String, image: UIImage?, via ai: ShortcutAI) async throws -> String {
        guard waiting == nil else { throw Failure.busy }
        if let image {
            UIPasteboard.general.image = image
        } else {
            // 前にコピーした画像が、関係のない質問に添付されないようにする
            UIPasteboard.general.items = []
        }
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "x-callback-url"
        components.path = "/run-shortcut"
        components.queryItems = [
            URLQueryItem(name: "name", value: ai.name),
            URLQueryItem(name: "input", value: "text"),
            URLQueryItem(name: "text", value: prompt),
            URLQueryItem(name: "x-success", value: "mangaviewer://chatgpt/success"),
            URLQueryItem(name: "x-cancel", value: "mangaviewer://chatgpt/cancel"),
            URLQueryItem(name: "x-error", value: "mangaviewer://chatgpt/error"),
        ]
        guard let url = components.url else { throw Failure.cannotOpen }
        return try await withCheckedThrowingContinuation { continuation in
            waiting = continuation
            UIApplication.shared.open(url) { [weak self] opened in
                guard !opened else { return }
                Task { @MainActor in self?.finish(.failure(Failure.cannotOpen)) }
            }
        }
    }

    /// mangaviewer:// で戻ってきたとき（アプリ全体の onOpenURL から呼ぶ）
    func handle(_ url: URL) {
        guard url.scheme == "mangaviewer", url.host == "chatgpt" else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        switch url.path {
        case "/success":
            if let result = value("result"), !result.isEmpty {
                finish(.success(result))
            } else if let copied = UIPasteboard.general.string, !copied.isEmpty {
                // ショートカットが答えをクリップボードにコピーする作りのとき
                finish(.success(copied))
            } else {
                finish(.failure(Failure.noAnswer))
            }
        case "/cancel":
            finish(.failure(Failure.cancelled))
        default:
            finish(.failure(Failure.shortcutError(value("errorMessage") ?? "")))
        }
    }

    private func finish(_ result: Result<String, Error>) {
        guard let continuation = waiting else { return }
        waiting = nil
        continuation.resume(with: result)
    }
}
