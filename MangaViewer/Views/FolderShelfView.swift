import SwiftUI

/// 本棚で開くフォルダ（選んだフォルダからの相対パス。空ならいちばん上）
struct FolderRoute: Hashable {
    let path: String
}

/// 本棚の1階層。サブフォルダと、このフォルダ直下の本を並べる
struct FolderShelfView: View {
    let path: String
    let open: (Book) -> Void
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var progress: ProgressStore
    @State private var search = ""

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 160), spacing: 16)]

    struct Subfolder: Identifiable {
        let name: String
        let path: String
        /// サブフォルダの中（さらに下の階層も含む）の本
        var books: [Book]
        var id: String { path }
    }

    /// このフォルダ以下（下の階層も含む）の本
    private var subtree: [Book] {
        guard !path.isEmpty else { return library.books }
        return library.books.filter { $0.folder == path || $0.folder.hasPrefix(path + "/") }
    }

    private var subfolders: [Subfolder] {
        var byPath: [String: Subfolder] = [:]
        for book in subtree where book.folder != path {
            let rest = path.isEmpty ? book.folder : String(book.folder.dropFirst(path.count + 1))
            let name = rest.split(separator: "/").first.map(String.init) ?? rest
            let child = path.isEmpty ? name : path + "/" + name
            byPath[child, default: Subfolder(name: name, path: child, books: [])].books.append(book)
        }
        return byPath.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var books: [Book] {
        subtree.filter { $0.folder == path }
    }

    private var searchResults: [Book] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return subtree.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.folder.localizedCaseInsensitiveContains(query)
        }
    }

    private var title: String {
        path.isEmpty ? "本棚" : (path as NSString).lastPathComponent
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                if search.trimmingCharacters(in: .whitespaces).isEmpty {
                    ForEach(subfolders) { folder in
                        NavigationLink(value: FolderRoute(path: folder.path)) {
                            FolderCell(folder: folder)
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(books) { book in
                        bookButton(book)
                    }
                } else {
                    // 検索中は、下の階層の本もまとめて表示する
                    ForEach(searchResults) { book in
                        bookButton(book)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(title)
        .searchable(text: $search, prompt: path.isEmpty ? "タイトルで探す" : "このフォルダの中で探す")
        .refreshable { await library.refresh() }
        .overlay {
            if !path.isEmpty && subtree.isEmpty && !library.isScanning {
                ContentUnavailableView("本がありません", systemImage: "folder",
                                       description: Text("このフォルダは移動したか、名前が変わったようです。"))
            }
        }
    }

    private func bookButton(_ book: Book) -> some View {
        Button {
            open(book)
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
}

/// 本棚のフォルダ。中の最初の本の表紙を、本を重ねたように見せる
struct FolderCell: View {
    let folder: FolderShelfView.Subfolder
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var progress: ProgressStore
    @State private var thumbnail: UIImage?

    /// 読み終わった本の数（最後のページまで進んだもの）
    private var finishedCount: Int {
        folder.books.filter { book in
            guard let entry = progress.entry(for: book), entry.pageCount > 0 else { return false }
            return entry.page >= entry.pageCount - 1
        }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                // 後ろに2冊重なっているように見せる
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.25))
                    .offset(x: 6, y: -6)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.35))
                    .offset(x: 3, y: -3)
                Color.secondary.opacity(0.15)
                    .overlay {
                        if let thumbnail {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(systemName: "folder")
                                .font(.title)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .aspectRatio(0.7, contentMode: .fit)
            .padding(.top, 6)
            .padding(.trailing, 6)
            .overlay(alignment: .bottomLeading) {
                Label("\(folder.books.count)", systemImage: "folder.fill")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(6)
            }
            .shadow(color: .black.opacity(0.15), radius: 3, y: 2)

            Text(folder.name)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(finishedCount > 0 ? "\(folder.books.count)冊・\(finishedCount)冊読了" : "\(folder.books.count)冊")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .task(id: folder.books.first?.id) {
            // 表紙は、ダウンロード済みの最初の本から作る
            guard let book = folder.books.first(where: \.isDownloaded) ?? folder.books.first else { return }
            thumbnail = await ThumbnailStore.shared.thumbnail(for: book, settings: settings.defaults)
        }
    }
}
