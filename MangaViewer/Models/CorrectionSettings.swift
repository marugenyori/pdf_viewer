import Foundation
import SwiftUI

/// 色の補正のしかた
enum ColorMode: String, Codable, CaseIterable, Identifiable {
    /// 紙の色を白に、インクを黒にそろえ、白黒のページは白黒に、カラーのページはカラーのまま
    case auto
    /// 巻頭の数ページ（カバー・表紙・口絵）だけ自動で、あとは白黒にする。
    /// 黄ばみの強い本で、白黒ページがカラーと判定されてしまうときのため
    case frontColorOnly
    /// すべてのページを白黒にする
    case grayscale
    /// 紙と黒の色はそろえるが、白黒にはしない
    case color
    /// 色は変えない
    case off

    var id: String { rawValue }

    /// frontColorOnly のとき、カラーのままにしてよいページ数（カバー・表紙・口絵）
    static let frontColorPages = 8

    var label: String {
        switch self {
        case .auto: "自動（白黒ページは白黒に）"
        case .frontColorOnly: "カラーは巻頭だけ（漫画向け）"
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

/// ページのめくり方
enum PageTurnStyle: String, Codable, CaseIterable, Identifiable {
    /// 紙の端がめくれる（ブックアプリのような動き）
    case curl
    /// 横に滑る
    case slide

    var id: String { rawValue }

    var label: String {
        switch self {
        case .curl: "紙をめくる"
        case .slide: "スライド"
        }
    }
}

/// 読書画面の背景（本の外側）の色
enum ReaderBackground: String, Codable, CaseIterable, Identifiable {
    case black
    case gray
    case cream
    case white

    var id: String { rawValue }

    var label: String {
        switch self {
        case .black: "黒"
        case .gray: "グレー"
        case .cream: "生成り"
        case .white: "白"
        }
    }

    var color: Color {
        switch self {
        case .black: Color.black
        case .gray: Color(white: 0.22)
        case .cream: Color(red: 0.93, green: 0.90, blue: 0.83)
        case .white: Color.white
        }
    }

    /// 背景が明るいか（読み込み中の表示などの色を変えるため）
    var isLight: Bool { self == .cream || self == .white }
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
    var inkDarkness: Double = 1.2
    var direction: ReadingDirection = .rightToLeft
    /// 横向きのときに見開きで表示する
    var spreadInLandscape = true
    /// 見開きのとき、1ページ目（表紙）だけを単独で表示する
    var coverAlone = true
    var pageTurn: PageTurnStyle = .curl
    /// ページをめくったときに軽く振動させる
    var pageTurnHaptics = true
    /// 紙詰まりなどで傾いたページをまっすぐにする
    var deskew = true
    var background: ReaderBackground = .black

    init() {}

    /// 項目を足しても、前に保存した設定が読めるよう、無い項目は既定値にする
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CorrectionSettings()
        autoRotate = try c.decodeIfPresent(Bool.self, forKey: .autoRotate) ?? d.autoRotate
        colorMode = try c.decodeIfPresent(ColorMode.self, forKey: .colorMode) ?? d.colorMode
        removeBlackEdges = try c.decodeIfPresent(Bool.self, forKey: .removeBlackEdges) ?? d.removeBlackEdges
        trimMargins = try c.decodeIfPresent(Bool.self, forKey: .trimMargins) ?? d.trimMargins
        inkDarkness = try c.decodeIfPresent(Double.self, forKey: .inkDarkness) ?? d.inkDarkness
        direction = try c.decodeIfPresent(ReadingDirection.self, forKey: .direction) ?? d.direction
        spreadInLandscape = try c.decodeIfPresent(Bool.self, forKey: .spreadInLandscape) ?? d.spreadInLandscape
        coverAlone = try c.decodeIfPresent(Bool.self, forKey: .coverAlone) ?? d.coverAlone
        pageTurn = try c.decodeIfPresent(PageTurnStyle.self, forKey: .pageTurn) ?? d.pageTurn
        pageTurnHaptics = try c.decodeIfPresent(Bool.self, forKey: .pageTurnHaptics) ?? d.pageTurnHaptics
        deskew = try c.decodeIfPresent(Bool.self, forKey: .deskew) ?? d.deskew
        background = try c.decodeIfPresent(ReaderBackground.self, forKey: .background) ?? d.background
    }
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
