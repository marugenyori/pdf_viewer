import Foundation

/// PC で作った索引ファイル（rag_index.json）。フォルダの中の PDF の、ページごとの文字が入っている
struct RagIndex {
    static let fileName = "rag_index.json"

    struct Page {
        /// 索引ファイルのあるフォルダからの相対パス
        let file: String
        let page: Int
        let text: String
        /// 検索用（小文字にしたもの）。1万ページを何度もなめるので、NSString のまま持つ（Swift の String より速い）
        let folded: NSString
    }

    struct Hit: Identifiable {
        let page: Page
        let score: Double
        let snippet: String
        /// 索引ファイルのあるフォルダ
        let folder: String
        var id: String { "\(folder)/\(page.file)#\(page.page)" }

        /// 選んだフォルダからの、その本の相対パス
        var relativePath: String {
            folder.isEmpty ? page.file : folder + "/" + page.file
        }
    }

    /// 索引ファイルのあるフォルダ（選んだフォルダからの相対パス。直下なら空）
    let folder: String
    let created: String
    let pages: [Page]

    private struct FileFormat: Decodable {
        struct Entry: Decodable {
            let file: String
            let page: Int
            let text: String
        }
        let version: Int
        let created: String?
        let pages: [Entry]
    }

    static func load(from url: URL, folder: String) throws -> RagIndex {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let decoded = try JSONDecoder().decode(FileFormat.self, from: data)
        let pages = decoded.pages.map {
            Page(file: $0.file, page: $0.page, text: $0.text, folded: Self.fold($0.text) as NSString)
        }
        return RagIndex(folder: folder, created: decoded.created ?? "", pages: pages)
    }

    /// 全角・半角や大文字・小文字の違いをなくす（索引の文字は PC で NFKC 済み）
    static func fold(_ text: String) -> String {
        text.precomposedStringWithCompatibilityMapping.lowercased()
    }

    /// 選んだフォルダからの、その本の相対パス
    func relativePath(of page: Page) -> String {
        folder.isEmpty ? page.file : folder + "/" + page.file
    }

    /// キーワードで探す。たくさんのキーワードに当たり、珍しいキーワードに当たるページほど上にする
    func search(_ keywords: [String], limit: Int = 30) -> [Hit] {
        let terms = Array(Set(keywords.map { Self.fold($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 || $0.unicodeScalars.contains { $0.value > 0x2FFF } }))
        guard !terms.isEmpty, !pages.isEmpty else { return [] }

        var counts = [[Int]](repeating: [], count: pages.count)
        var documentFrequency = [Int](repeating: 0, count: terms.count)
        for (p, page) in pages.enumerated() {
            let row = terms.map { Self.occurrences(of: $0, in: page.folded) }
            counts[p] = row
            for (t, n) in row.enumerated() where n > 0 { documentFrequency[t] += 1 }
        }
        let total = Double(pages.count)
        let idf = documentFrequency.map { log((total + 1) / (Double($0) + 0.5)) }

        var hits: [Hit] = []
        for (p, row) in counts.enumerated() {
            var score = 0.0
            var matched = 0
            for (t, n) in row.enumerated() where n > 0 {
                score += idf[t] * (1 + log(Double(n)))
                matched += 1
            }
            guard matched > 0 else { continue }
            // 複数のキーワードがそろうページを強く上げる
            score *= 1 + Double(matched - 1) * 0.5
            let firstTerm = terms.indices.filter { row[$0] > 0 }.max { idf[$0] < idf[$1] }.map { terms[$0] } ?? terms[0]
            hits.append(Hit(page: pages[p], score: score, snippet: Self.snippet(of: pages[p], around: firstTerm), folder: folder))
        }
        return Array(hits.sorted { $0.score > $1.score }.prefix(limit))
    }

    private static func occurrences(of term: String, in text: NSString) -> Int {
        var count = 0
        var searchRange = NSRange(location: 0, length: text.length)
        while true {
            let found = text.range(of: term, options: .literal, range: searchRange)
            guard found.location != NSNotFound else { break }
            count += 1
            if count >= 50 { break }
            let next = found.location + max(1, found.length)
            searchRange = NSRange(location: next, length: text.length - next)
        }
        return count
    }

    /// 当たった言葉のまわりを少しだけ切り出す
    private static func snippet(of page: Page, around term: String) -> String {
        let folded = page.folded
        let found = folded.range(of: term, options: .literal)
        guard found.location != NSNotFound else { return String(page.text.prefix(80)) }
        let start = max(0, found.location - 40)
        let end = min(folded.length, start + 120)
        let body = folded.substring(with: NSRange(location: start, length: end - start))
            .replacingOccurrences(of: "\n", with: " ")
        return (start > 0 ? "…" : "") + body + (end < folded.length ? "…" : "")
    }
}
