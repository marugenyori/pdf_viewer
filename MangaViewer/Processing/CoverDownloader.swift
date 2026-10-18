import Foundation
import Network

/// iCloud にしかない本の表紙を作るため、PDF を一時的にダウンロードする。
/// iCloud はファイルの一部だけを取り出せないので、1冊まるごと（約 70MB）落として表紙を作り、
/// 作り終えたら iPhone から消して（iCloud には残る）容量を空ける。ダウンロードは1冊ずつ順番に行う
enum CoverDownloader {
    /// モバイル通信でも表紙のためにダウンロードするか（設定画面で変える）
    static let cellularKey = "coverDownloadOnCellular"

    private static let queue = DispatchQueue(label: "cover-download", qos: .utility)

    /// この iPhone にファイルの中身があるか
    static func isLocal(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
              let status = values.ubiquitousItemDownloadingStatus else { return true }
        return status == .current || status == .downloaded
    }

    /// 今の通信で、表紙のためのダウンロードをしてよいか
    static var mayDownload: Bool {
        NetworkMonitor.shared.isConnected
            && (NetworkMonitor.shared.isUnmetered || UserDefaults.standard.bool(forKey: cellularKey))
    }

    /// ダウンロードが終わるまで待つ（1冊ずつ）
    static func download(_ url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                var readable = false
                var error: NSError?
                NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { coordinated in
                    readable = FileManager.default.isReadableFile(atPath: coordinated.path)
                }
                continuation.resume(returning: error == nil && readable)
            }
        }
    }

    /// 表紙を作り終えたファイルを iPhone から消す（読書中の本は消さない）
    static func evict(_ book: Book) {
        guard !OpenBooks.shared.contains(book.key) else { return }
        try? FileManager.default.evictUbiquitousItem(at: book.url)
    }
}

/// 読書画面で開いている本。表紙のために落としたファイルを消すとき、開いている本は消さない
final class OpenBooks: @unchecked Sendable {
    static let shared = OpenBooks()
    private let lock = NSLock()
    private var keys = Set<String>()

    func insert(_ key: String) {
        lock.lock(); defer { lock.unlock() }
        keys.insert(key)
    }

    func remove(_ key: String) {
        lock.lock(); defer { lock.unlock() }
        keys.remove(key)
    }

    func contains(_ key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return keys.contains(key)
    }
}

/// 通信の種類（Wi-Fi か、モバイル通信か）を見張る
final class NetworkMonitor: @unchecked Sendable {
    static let shared = NetworkMonitor()
    private let monitor = NWPathMonitor()

    private init() {
        monitor.start(queue: DispatchQueue(label: "network-monitor"))
    }

    var isConnected: Bool {
        monitor.currentPath.status == .satisfied
    }

    /// 通信量を気にしなくてよい回線（Wi-Fi など。モバイル通信や省データモードではない）
    var isUnmetered: Bool {
        let path = monitor.currentPath
        return path.status == .satisfied && !path.isExpensive && !path.isConstrained
    }
}
