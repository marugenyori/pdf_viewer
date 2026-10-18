import Foundation

/// 色の補正のしかた
enum ColorMode: String, Codable, CaseIterable, Identifiable {
    /// 紙の色を白に、インクを黒にそろえ、白黒のページは白黒に、カラーのページはカラーのまま
    case auto
    /// すべてのページを白黒にする
    case grayscale
    /// 紙と黒の色はそろえるが、白黒にはしない
    case color
    /// 色は変えない
    case off

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: "自動（白黒ページは白黒に）"
        case .grayscale: "すべて白黒"
        case .color: "色をそろえる（カラーのまま）"
        case .off: "補正しない"
        }
    }
}

/// 読む方向
enum ReadingDirection: String, Codable, CaseIterable, Identifiable {
    case rightToLeft
    case leftToRight

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rightToLeft: "右綴じ（漫画）"
        case .leftToRight: "左綴じ"
        }
    }
}

/// 1冊ごとの補正と表示の設定
struct CorrectionSettings: Codable, Equatable {
    /// 横向き・逆さまのページを自動で回転する
    var autoRotate = true
    var colorMode: ColorMode = .auto
    /// スキャン範囲の外の黒い縁・影を切り取る。
    /// 調査では ScanSnap が紙の形で切り抜いていて縁も余白もほとんどなかったので、絵を削らないよう既定はオフ
    var removeBlackEdges = false
    /// 白い余白を詰める（既定はオフ。理由は上と同じ）
    var trimMargins = false
    /// 黒の濃さ（ガンマ）。1 でそのまま、大きいほど中間の灰色が濃くなる
    var inkDarkness: Double = 1.1
    var direction: ReadingDirection = .rightToLeft
    /// 横向きのときに見開きで表示する
    var spreadInLandscape = true
    /// 見開きのとき、1ページ目（表紙）だけを単独で表示する
    var coverAlone = true
}

/// アプリ全体の既定値（新しく開いた本に使う）
@MainActor
final class AppSettings: ObservableObject {
    private static let key = "defaultCorrectionSettings"

    @Published var defaults: CorrectionSettings {
        didSet { save() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let value = try? JSONDecoder().decode(CorrectionSettings.self, from: data) {
            defaults = value
        } else {
            defaults = CorrectionSettings()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(defaults) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
