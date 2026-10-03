import SwiftUI
import UniformTypeIdentifiers

/// 本棚（最初の画面）
struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var progress: ProgressStore
    @State private var pickingFolder = false
    @State private var showSettings = false
    @State private var openBook: Book?
    @State private var search = ""

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 160), spacing: 16)]

    var body: some View {
        NavigationStack {
            Group {
                if library.rootURL == nil {
                    welcome
                } else if library.books.isEmpty {
                    if library.isScanning {
                        ProgressView("フォルダを調べています…")
                    } else {
                        ContentUnavailableView("PDF が見つかりません", systemImage: "doc.questionmark",
                                               description: Text("選んだフォルダの中に PDF がありません。右上の … から、ほかのフォルダを選べます。"))
                    }
                } else {
                    shelf
                }
            }
            .navigationTitle("本棚")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { pickingFolder = true } label: {
                            Label("フォルダを選び直す", systemImage: "folder")
                        }
                        Button { Task { await library.refresh() } } label: {
                            Label("一覧を更新", systemImage: "arrow.clockwise")
                        }
                        Button { showSettings = true } label: {
                            Label("補正の既定値", systemImage: "slider.horizontal.3")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result {
                    library.setFolder(url)
                }
            }
            .sheet(isPresented: $showSettings) {
                DefaultSettingsView()
                    .environmentObject(settings)
            }
            .fullScreenCover(item: $openBook) { book in
                ReaderView(book: book, defaults: settings.defaults) {
                    // ダウンロードされた本の表紙を作るため、一覧を読み直す
                    Task { await library.refresh() }
                }
                .environmentObject(settings)
            }
            .alert("エラー", isPresented: Binding(get: { library.errorMessage != nil },
                                                set: { if !$0 { library.errorMessage = nil } })) {
                Button("OK") { library.errorMessage = nil }
            } message: {
                Text(library.errorMessage ?? "")
            }
        }
    }

    // MARK: - 最初の案内

    private var welcome: some View {
        VStack(spacing: 20) {
            Image(systemName: "books.vertical")
                .font(.system(.largeTitle))
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("自炊した本のフォルダを選んでください")
                .font(.headline)
            Text("「ファイル」の画面が開きます。\niCloud Drive → ScanSnap Home を開いて、右上の「開く」を押してください。中のサブフォルダの PDF もまとめて表示します。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                pickingFolder = true
            } label: {
                Label("フォルダを選ぶ", systemImage: "folder")
                    .frame(maxWidth: 260)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(32)
    }

    // MARK: - 本棚

    private var filteredBooks: [Book] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return library.books }
        return library.books.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.folder.localizedCaseInsensitiveContains(query)
        }
    }

    /// サブフォルダごとにまとめる（並びは LibraryStore で整えた順）
    private struct ShelfSection: Identifiable {
        let folder: String
        var books: [Book]
        var id: String { folder }
    }

    private var sections: [ShelfSection] {
        var result: [ShelfSection] = []
        for book in filteredBooks {
            if let last = result.last, last.folder == book.folder {
                result[result.count - 1].books.append(book)
            } else {
                result.append(ShelfSection(folder: book.folder, books: [book]))
            }
        }
        return result
    }

    private var shelf: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 20, pinnedViews: [.sectionHeaders]) {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.books) { book in
                            Button {
                                openBook = book
                            } label: {
                                BookCell(book: book, progress: progress.entry(for: book))
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    Task {
                                        await ThumbnailStore.shared.invalidate(book)
                                        await library.refresh()
                                    }
                                } label: {
                                    Label("表紙を作り直す", systemImage: "photo")
                                }
                            }
                        }
                    } header: {
                        if !section.folder.isEmpty {
                            Text(section.folder)
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 6)
                                .background(.bar)
                        }
                    }
                }
            }
            .padding()
        }
        .searchable(text: $search, prompt: "タイトルで探す")
        .refreshable { await library.refresh() }
    }
}

/// 本棚の1冊
struct BookCell: View {
    let book: Book
    let progress: ProgressStore.Entry?
    @EnvironmentObject private var settings: AppSettings
    @State private var thumbnail: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.secondary.opacity(0.15)
                .aspectRatio(0.7, contentMode: .fit)
                .overlay {
                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: book.isDownloaded ? "book.closed" : "icloud.and.arrow.down")
                            .font(.title)
                            .foregroundStyle(.secondary)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(alignment: .bottom) {
                    if let progress, progress.pageCount > 0 {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(.black.opacity(0.4))
                                Rectangle().fill(.tint)
                                    .frame(width: geo.size.width * max(0.03, progress.fraction))
                            }
                        }
                        .frame(height: 4)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                        .padding(6)
                    }
                }
                .shadow(color: .black.opacity(0.15), radius: 3, y: 2)

            Text(book.title)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let progress, progress.pageCount > 0 {
                Text("\(progress.page + 1) / \(progress.pageCount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: "\(book.id)-\(book.isDownloaded)") {
            thumbnail = await ThumbnailStore.shared.thumbnail(for: book, settings: settings.defaults)
        }
    }
}

/// アプリ全体の既定値
struct DefaultSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("ここで決めた設定は、これから初めて開く本に使われます。すでに開いた本は、読書画面の設定ボタンから本ごとに変えられます。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                CorrectionForm(settings: $settings.defaults)
            }
            .navigationTitle("補正の既定値")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
        }
    }
}
