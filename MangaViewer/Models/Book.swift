import CryptoKit
import Foundation

/// 本棚に並ぶ1冊（PDF 1ファイル）
struct Book: Identifiable, Hashable {
    /// 実際のファイルの場所（iCloud にしかない場合も、ダウンロード後の名前の URL）
    let url: URL
    /// 選んだフォルダからの相対パス（本の識別に使う）
    let relativePath: String
    let title: String
    /// サブフォルダ名（直下なら空）
    let folder: String
    /// この iPhone にダウンロード済みか
    let isDownloaded: Bool

    var id: String { relativePath }

    /// 保存ファイル名に使うキー
    var key: String {
        let digest = SHA256.hash(data: Data(relativePath.utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}
