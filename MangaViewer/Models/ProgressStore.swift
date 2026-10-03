import Foundation

/// 本ごとの「どこまで読んだか」。本棚で一覧表示するため、軽い値だけを UserDefaults に置く
@MainActor
final class ProgressStore: ObservableObject {
    static let shared = ProgressStore()

    struct Entry: Equatable {
        var page: Int
        var pageCount: Int

        var fraction: Double {
            pageCount > 1 ? Double(page) / Double(pageCount - 1) : 0
        }
    }

    private static let key = "readingProgress"
    @Published private(set) var entries: [String: Entry] = [:]

    private init() {
        let raw = UserDefaults.standard.dictionary(forKey: Self.key) as? [String: [Int]] ?? [:]
        for (k, v) in raw where v.count == 2 {
            entries[k] = Entry(page: v[0], pageCount: v[1])
        }
    }

    func entry(for book: Book) -> Entry? {
        entries[book.key]
    }

    func update(book: Book, page: Int, pageCount: Int) {
        let entry = Entry(page: page, pageCount: pageCount)
        guard entries[book.key] != entry else { return }
        entries[book.key] = entry
        let raw = entries.mapValues { [$0.page, $0.pageCount] }
        UserDefaults.standard.set(raw, forKey: Self.key)
    }
}
