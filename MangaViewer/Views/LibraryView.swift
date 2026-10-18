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
                    FolderShelfView(path: "") { openBook = $0 }
                }
            }
            .navigationTitle("本棚")
            .navigationDestination(for: FolderRoute.self) { route in
                FolderShelfView(path: route.path) { openBook = $0 }
            }
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
            Text("「ファイル」の画面が開きます。\niCloud Drive → ScanSnap Home を開いて、右上の「開く」を押してください。中のサブフォルダは、そのままフォルダとして並びます。")
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

}

/// 本棚の1冊
struct BookCell: View {
    let book: Book
    let progress: ProgressStore.Entry?
    @EnvironmentObject private var settings: AppSettings
    @State private var isLoading = false
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
                    } else if isLoading {
                        ProgressView()
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
            // iCloud にしかない本は、表紙を作るために一時的にダウンロードするので時間がかかる
            isLoading = !book.isDownloaded
            thumbnail = await ThumbnailStore.shared.thumbnail(for: book, settings: settings.defaults)
            isLoading = false
        }
    }
}

/// アプリ全体の既定値
struct DefaultSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @AppStorage(CoverDownloader.cellularKey) private var coverOnCellular = false
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
                Section {
                    Toggle("モバイル通信でも表紙をダウンロード", isOn: $coverOnCellular)
                } header: {
                    Text("表紙")
                } footer: {
                    Text("iCloud にしかない本は、表紙を作るために1冊まるごと（約 70MB）ダウンロードし、作り終えたら iPhone から消します（iCloud には残ります）。ふだんは Wi-Fi のときだけ行います。")
                }
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
