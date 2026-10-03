import Foundation

/// 正規化した矩形（左上が原点、0〜1）
struct NormRect: Codable, Equatable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double

    static let full = NormRect(x: 0, y: 0, w: 1, h: 1)
}

/// 1ページを解析した結果（元の向きの画像に対する値）
struct PageAnalysis: Codable, Equatable {
    /// 解析方法を変えたら上げる。古い結果は捨てて解析し直す
    static let currentVersion = 1

    var version = PageAnalysis.currentVersion
    /// 黒い縁だけを除いた範囲
    var edgeCrop: NormRect
    /// 黒い縁と白い余白を除いた範囲
    var contentCrop: NormRect
    /// インクの色（R, G, B：0〜1）。これを黒にする
    var black: [Double]
    /// 紙の色（R, G, B：0〜1）。これを白にする
    var white: [Double]
    /// カラーのページか
    var isColor: Bool
    /// 横長のページか
    var isLandscape: Bool
    /// 文字から判定した回転角（時計回り、0/90/180/270）。nil はまだ判定していない
    var autoRotation: Int?
    /// 回転の判定に自信があるか
    var rotationConfident = false
}

/// 1冊ごとに保存する状態
struct BookState: Codable {
    var settings: CorrectionSettings
    var lastPage = 0
    /// 手動で回したページ（ページ番号 → 時計回りの角度）
    var rotationOverrides: [Int: Int] = [:]
    var analyses: [Int: PageAnalysis] = [:]
}

enum BookStateStore {
    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Books", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func fileURL(for book: Book) -> URL {
        directory.appendingPathComponent(book.key + ".json")
    }

    static func load(for book: Book, defaults: CorrectionSettings) -> BookState {
        if let data = try? Data(contentsOf: fileURL(for: book)),
           var state = try? JSONDecoder().decode(BookState.self, from: data) {
            state.analyses = state.analyses.filter { $0.value.version == PageAnalysis.currentVersion }
            return state
        }
        return BookState(settings: defaults)
    }

    static func save(_ state: BookState, for book: Book) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL(for: book), options: .atomic)
    }
}
