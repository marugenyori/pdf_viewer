import Foundation

/// 選んだフォルダ（iCloud Drive の ScanSnap Home など）の中の PDF を本棚として管理する
@MainActor
final class LibraryStore: ObservableObject {
    private static let bookmarkKey = "libraryFolderBookmark"

    @Published private(set) var rootURL: URL?
    @Published private(set) var books: [Book] = []
    @Published private(set) var isScanning = false
    @Published var errorMessage: String?

    init() {
        restoreFolder()
        Task { await refresh() }
    }

    // MARK: - フォルダ

    /// ファイル選択画面で選んだフォルダを保存する
    func setFolder(_ url: URL) {
        stopAccessing()
        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = "フォルダへのアクセスが許可されませんでした。もう一度選んでください。"
            return
        }
        do {
            let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
            rootURL = url
            Task { await refresh() }
        } catch {
            url.stopAccessingSecurityScopedResource()
            errorMessage = "フォルダを記録できませんでした：\(error.localizedDescription)"
        }
    }

    private func restoreFolder() {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else {
            errorMessage = "前回選んだフォルダが見つかりません。もう一度選んでください。"
            return
        }
        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = "フォルダへのアクセスが切れました。もう一度選んでください。"
            return
        }
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: Self.bookmarkKey)
        }
        rootURL = url
    }

    private func stopAccessing() {
        rootURL?.stopAccessingSecurityScopedResource()
        rootURL = nil
    }

    // MARK: - 一覧

    func refresh() async {
        guard let root = rootURL, !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        let found = await Task.detached(priority: .userInitiated) {
            Self.scan(root: root)
        }.value
        books = found
    }

    /// フォルダの中を再帰的にたどって PDF を集める
    nonisolated private static func scan(root: URL) -> [Book] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .ubiquitousItemDownloadingStatusKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: []) else {
            return []
        }
        let rootPath = root.standardizedFileURL.path
        var result: [Book] = []
        for case let url as URL in enumerator {
            var name = url.lastPathComponent
            var realURL = url
            var placeholder = false
            if name.hasPrefix(".") {
                // 古い形式の iCloud のプレースホルダ（.名前.pdf.icloud）
                guard name.hasSuffix(".icloud") else { continue }
                name = String(name.dropFirst().dropLast(".icloud".count))
                realURL = url.deletingLastPathComponent().appendingPathComponent(name)
                placeholder = true
            }
            guard name.lowercased().hasSuffix(".pdf") else { continue }

            var downloaded = !placeholder
            if !placeholder, let values = try? url.resourceValues(forKeys: [.fileSizeKey, .ubiquitousItemDownloadingStatusKey]) {
                if let status = values.ubiquitousItemDownloadingStatus {
                    downloaded = status == .current || status == .downloaded
                }
                // 中身が空（0 バイト）の PDF は並べない（調査で、以前の補正版に 43 個あった）
                if downloaded, values.fileSize == 0 { continue }
            }

            var relative = realURL.standardizedFileURL.path
            if relative.hasPrefix(rootPath) {
                relative = String(relative.dropFirst(rootPath.count))
            }
            if relative.hasPrefix("/") { relative.removeFirst() }
            let folder = (relative as NSString).deletingLastPathComponent
            let title = (name as NSString).deletingPathExtension

            result.append(Book(url: realURL, relativePath: relative, title: title, folder: folder, isDownloaded: downloaded))
        }
        return result.sorted {
            if $0.folder != $1.folder {
                return $0.folder.localizedStandardCompare($1.folder) == .orderedAscending
            }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    // MARK: - ダウンロード

    /// iCloud にしかないファイルをダウンロードし、読める状態にする
    nonisolated static func ensureDownloaded(_ url: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            var coordinatorError: NSError?
            var readable = false
            // 読み取りの調整をすると、iCloud のファイルはダウンロードが終わるまで待ってくれる
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinatorError) { coordinated in
                readable = FileManager.default.isReadableFile(atPath: coordinated.path)
            }
            if let coordinatorError { throw coordinatorError }
            if !readable {
                throw CocoaError(.fileReadNoSuchFile)
            }
        }.value
    }
}
