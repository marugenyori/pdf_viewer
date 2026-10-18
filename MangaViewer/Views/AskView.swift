import SwiftUI

/// 読書中に、今のページについて AI に質問する画面
struct AskView: View {
    @ObservedObject var reader: ReaderModel
    @ObservedObject var ask: AskModel
    @AppStorage(AskEngine.storageKey) private var engineRaw = AskEngine.auto.rawValue
    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @FocusState private var focused: Bool

    private var engine: AskEngine {
        AskEngine(rawValue: engineRaw) ?? .auto
    }

    private let suggestions = ["このページのあらすじは？", "このキャラは誰？", "この言葉の意味は？", "ここまでの流れをまとめて"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if ask.entries.isEmpty {
                                intro
                            }
                            ForEach(ask.entries) { entry in
                                EntryView(entry: entry, isLatest: entry.id == ask.entries.last?.id,
                                          isAsking: ask.isAsking)
                                    .id(entry.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: ask.entries.count) { _, _ in
                        if let last = ask.entries.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                    }
                }
                Divider()
                inputBar
            }
            .navigationTitle("質問する")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("答える AI", selection: $engineRaw) {
                            ForEach(AskEngine.allCases) { engine in
                                Text(engine.label).tag(engine.rawValue)
                            }
                        }
                        if !ask.entries.isEmpty {
                            Button(role: .destructive) { ask.clear() } label: {
                                Label("やりとりを消す", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今開いているページ（\(reader.currentPages.map { "\($0 + 1)" }.joined(separator: "・")) ページ目）について質問できます。")
                .font(.callout)
            Text(engineNote)
                .font(.caption)
                .foregroundStyle(.secondary)
            FlowChips(items: suggestions) { send($0) }
        }
    }

    private var engineNote: String {
        switch engine {
        case .claude:
            return "Claude に、ページの画像と質問を送ります（通信が必要。API の料金がかかります）。"
        case .onDevice:
            return "iPhone の中だけで答えます。ページの文字を読み取って渡すので、絵の内容についての答えは苦手です。"
        case .chatGPT:
            return "ショートカット「\(ChatGPTBridge.shared.shortcutName)」を使って、Apple Intelligence の ChatGPT に聞きます。いったんショートカットのアプリに移り、答えが出たらこのアプリに戻ります。"
        case .auto:
            return ClaudeClient.hasKey
                ? "Claude に、ページの画像と質問を送ります（通信が必要。API の料金がかかります）。"
                : "Claude の API キーがないので、iPhone の中の AI で答えます。"
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("気になることを書いてください", text: $question, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit { send(question) }
            Button {
                send(question)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title)
            }
            .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || ask.isAsking)
        }
        .padding()
    }

    private func send(_ text: String) {
        let images = reader.currentPages.compactMap { reader.images[$0] }
        let pages = reader.currentPages
        question = ""
        Task {
            await ask.ask(text, book: reader.book, pages: pages, images: images, engine: engine)
        }
    }
}

private struct EntryView: View {
    let entry: AskEntry
    let isLatest: Bool
    let isAsking: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer(minLength: 40)
                Text(entry.question)
                    .padding(10)
                    .background(Color.accentColor.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
            }
            if let answer = entry.answer {
                VStack(alignment: .leading, spacing: 4) {
                    Text(answer)
                        .textSelection(.enabled)
                    Text("\(entry.engineName)・\(entry.pageLabel) ページ")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            } else if let error = entry.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            } else if isLatest && isAsking {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("考えています…").font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// 質問の例を、押せる小さなボタンとして並べる
private struct FlowChips: View {
    let items: [String]
    let onTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button(item) { onTap(item) }
                    .buttonStyle(.bordered)
                    .font(.callout)
            }
        }
    }
}

/// 設定画面の「質問（AI）」の項目
struct AskSettingsSection: View {
    @AppStorage(AskEngine.storageKey) private var engineRaw = AskEngine.auto.rawValue
    /// ChatGPTBridge.shortcutNameKey と同じ
    @AppStorage("chatGPTShortcutName") private var shortcutName = 
    @State private var keyInput = ""
    @State private var hasKey = ClaudeClient.hasKey

    var body: some View {
        Section {
            Picker("答える AI", selection: $engineRaw) {
                ForEach(AskEngine.allCases) { engine in
                    Text(engine.label).tag(engine.rawValue)
                }
            }
            if hasKey {
                HStack {
                    Label("Claude の API キー：保存済み", systemImage: "key.fill")
                    Spacer()
                    Button("削除", role: .destructive) {
                        Keychain.set(nil, for: ClaudeClient.keyAccount)
                        hasKey = false
                    }
                }
            } else {
                SecureField("Claude の API キー（sk-ant-…）", text: $keyInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("キーを保存") {
                    Keychain.set(keyInput.trimmingCharacters(in: .whitespacesAndNewlines), for: ClaudeClient.keyAccount)
                    keyInput = ""
                    hasKey = ClaudeClient.hasKey
                }
                .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            TextField("ChatGPT 用のショートカットの名前（\(ChatGPTBridge.defaultShortcutName)）", text: $shortcutName)
                .textInputAutocapitalization(.never)
            let device = OnDeviceAI.status
            Label(device.available ? "iPhone 内の AI：使えます" : "iPhone 内の AI：\(device.reason)",
                  systemImage: device.available ? "checkmark.circle" : "xmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("質問（AI）")
        } footer: {
            Text("Claude を使うと、ページの画像と質問を Anthropic に送ります。キーは console.anthropic.com で作り、この iPhone のキーチェーンにだけ保存します（Claude のサブスクとは別の、使った分だけの料金です）。iPhone 内の AI は無料で、通信もしません。ChatGPT は、Apple Intelligence の ChatGPT を使うショートカットを経由して聞きます（先にショートカットを作っておく必要があります）。")
        }
    }
}
