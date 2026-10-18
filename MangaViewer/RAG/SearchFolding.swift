import Foundation

/// 検索のときに文字の違いをならす。OCR の誤りと表記ゆれで取りこぼさないため（docs/PC_RAG_REPORT.md）
/// - 濁点・半濁点を落とす（OCR が「ビット」を「ピット」、「ボード」を「ボート」と読み違えるため）
/// - 小さい字を大きい字にする（「ソリューション」が「ソリユーション」になるため）
/// - 長音「ー」を落とす（「インターフェース」「インタフェース」をそろえるため）
/// - 英字を小文字にする
enum SearchFolding {
    /// 濁点・半濁点付きのかな → 元のかな、小さいかな → 大きいかな
    private static let kanaTable: [UInt32: UInt32] = {
        var table: [UInt32: UInt32] = [:]
        for v in UInt32(0x3041)...UInt32(0x30FF) {
            guard let scalar = Unicode.Scalar(v) else { continue }
            let parts = Array(String(scalar).decomposedStringWithCanonicalMapping.unicodeScalars)
            if parts.count == 2, parts[1].value == 0x3099 || parts[1].value == 0x309A {
                table[v] = parts[0].value
            }
        }
        let small: [(UInt32, UInt32)] = [
            (0x3041, 0x3042), (0x3043, 0x3044), (0x3045, 0x3046), (0x3047, 0x3048), (0x3049, 0x304A),
            (0x3063, 0x3064), (0x3083, 0x3084), (0x3085, 0x3086), (0x3087, 0x3088), (0x308E, 0x308F),
            (0x30A1, 0x30A2), (0x30A3, 0x30A4), (0x30A5, 0x30A6), (0x30A7, 0x30A8), (0x30A9, 0x30AA),
            (0x30C3, 0x30C4), (0x30E3, 0x30E4), (0x30E5, 0x30E6), (0x30E7, 0x30E8), (0x30EE, 0x30EF),
            (0x30F5, 0x30AB), (0x30F6, 0x30B1),
        ]
        for (from, to) in small { table[from] = to }
        // 濁点を落としたあとに小さい字になるもの（例：ヴ→ウ）はないが、念のため2段目も引く
        for (key, value) in table { if let next = table[value] { table[key] = next } }
        return table
    }()

    /// 落とす文字：長音、単独の濁点・半濁点
    private static let dropped: Set<UInt32> = [0x30FC, 0x3099, 0x309A, 0x309B, 0x309C]

    /// 索引の文字をならす（索引は PC で NFKC 済み）
    static func fold(_ text: String) -> String {
        var map: [Int]? = nil
        return fold(text, map: &map)
    }

    /// 検索語をならす（全角英数字なども半角にそろえる）
    static func foldQuery(_ text: String) -> String {
        fold(text.precomposedStringWithCompatibilityMapping)
    }

    /// map を渡すと、ならした文字の位置（UTF-16）→ 元の文字の位置（UTF-16）の対応を入れる
    static func fold(_ text: String, map: inout [Int]?) -> String {
        var out = String.UnicodeScalarView()
        var offset = 0
        let wantsMap = map != nil
        var positions: [Int] = []
        for scalar in text.unicodeScalars {
            let width = scalar.utf16.count
            defer { offset += width }
            var v = scalar.value
            if dropped.contains(v) { continue }
            if v >= 0x41 && v <= 0x5A {
                v += 0x20
            } else if let mapped = kanaTable[v] {
                v = mapped
            }
            guard let folded = Unicode.Scalar(v) else { continue }
            out.append(folded)
            if wantsMap {
                for _ in 0..<folded.utf16.count { positions.append(offset) }
            }
        }
        if wantsMap { map = positions }
        return String(out)
    }
}
