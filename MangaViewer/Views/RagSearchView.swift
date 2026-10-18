import SwiftUI

/// 読み込んだ索引を、アプリを開いているあいだ覚えておく（大きいので毎回読み直さない）
@MainActor
final class RagStore {
    static let shared = RagStore()
    private var cache: [URL: (date: Date, index: RagIndex)] = [:]

    func load(_ files: [RagIndexFile]) async throws -> [RagIndex] {
        var result: [RagIndex] = []
        for file in files {
            try await LibraryStore.ensureDownloaded(file.url)
            let date = (try? file.url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if let cached = cache[file.url], cached.date == date {
                result.append(cached.index)
                continue
            }
            let url = file.url
            let folder = file.folder
            let index = try await Task.detached(priority: .userInitiated) {
                try RagIndex.load(from: url, folder: folder)
            }.value
            cache[file.url] = (date, index)
            result.append(index)
        }
        return result
    }
}

/// 誌面検索（RAG）。キーワードで探すか、AI に質問して誌面をもとに答えてもらう
struct RagSearchView: View {
    let open: (Book, Int) -> Void
    @EnvironmentObject private var library: LibraryStore
    @AppStorage(AskEngine.storageKey) private var engineRaw = AskEngine.auto.rawValue
    @Environment(\.dismiss) private var dismiss

    @State private var indexes: [RagIndex] = []
    @State private var loadError: String?
    @State private var isLoading = true
    @State private var query = ""
    @State private var hits: [RagIndex.Hit] = []
    @State private var answer: RagAssistant.Answer?
    @State private var answerError: String?
    @State private var isAnswering = false

    private var engine: AskEngine { AskEngine(rawValue: engineRaw) ?? .auto }

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("索引を読み込んでいます…")
                    }
                } else if let loadError {
                    Label(loadError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                } else {
                    Section {
                        Text("\(indexes.map { $0.folder.isEmpty ? "本棚" : $0.folder }.joined(separator: "、"))（\(indexes.reduce(0) { $0 + $1.pages.count }) ページ）から探します。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button {
                            askAI()
                        } label: {
                            Label(isAnswering ? "考えています…" : "AI に聞く（誌面をもとに答える）", systemImage: "sparkles")
                        }
                        .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || isAnswering)
                    }
                    if let answer {
                        answerSection(answer)
                    }
                    if let answerError {
                        Label(answerError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    if !hits.isEmpty {
                        Section("キーワードに当たったページ（\(hits.count)）") {
                            ForEach(hits) { hit in
                                hitRow(hit)
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "言葉や質問を入力")
            .onSubmit(of: .search) { runKeywordSearch() }
            .onChange(of: query) { _, value in
                if value.isEmpty { hits = [] }
            }
            .navigationTitle("誌面を検索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .task { await loadIndexes() }
        }
    }

    private func answerSection(_ answer: RagAssistant.Answer) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(answer.text)
                    .textSelection(.enabled)
                if !answer.engineName.isEmpty {
                    Text(answer.engineName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(Array(answer.sources.enumerated()), id: \.element.id) { i, hit in
                hitRow(hit, number: i + 1)
            }
        } header: {
            Text("AI の答え")
        }
    }

    private func hitRow(_ hit: RagIndex.Hit, number: Int? = nil) -> some View {
        let book = book(for: hit)
        return Button {
            if let book { open(book, hit.page.page) }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if let number {
                        Text("[\(number)]").font(.caption.monospacedDigit()).foregroundStyle(.tint)
                    }
                    Text(book?.title ?? hit.page.file)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Text("\(hit.page.page + 1) ページ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(hit.snippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .disabled(book == nil)
    }

    private func book(for hit: RagIndex.Hit) -> Book? {
        library.books.first { $0.relativePath == hit.relativePath }
    }

    private func loadIndexes() async {
        guard indexes.isEmpty else { return }
        do {
            indexes = try await RagStore.shared.load(library.ragIndexes)
            if indexes.isEmpty { loadError = "索引ファイル（rag_index.json）が見つかりません。" }
        } catch {
            loadError = "索引を読み込めませんでした。\(error.localizedDescription)"
        }
        isLoading = false
    }

    private func runKeywordSearch() {
        let text = query
        let current = indexes
        Task {
            hits = await Task.detached(priority: .userInitiated) {
                RagAssistant.keywordSearch(text, indexes: current)
            }.value
        }
    }

    private func askAI() {
        let question = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        isAnswering = true
        answer = nil
        answerError = nil
        Task {
            do {
                answer = try await RagAssistant.answer(question: question, indexes: indexes, engine: engine)
            } catch {
                answerError = error.localizedDescription
            }
            isAnswering = false
        }
    }
}
