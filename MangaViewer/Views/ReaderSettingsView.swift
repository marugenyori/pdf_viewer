import SwiftUI

/// 読書中に開く、この本の補正と表示の設定
struct ReaderSettingsView: View {
    @ObservedObject var model: ReaderModel
    @EnvironmentObject private var appSettings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var draft = CorrectionSettings()
    @State private var savedAsDefault = false

    var body: some View {
        NavigationStack {
            Form {
                CorrectionForm(settings: $draft)

                Section {
                    Button("この設定をほかの本の既定にする") {
                        appSettings.defaults = draft
                        savedAsDefault = true
                    }
                    .disabled(savedAsDefault)
                    Button("この本の自動判定をやり直す") {
                        model.reanalyze()
                        dismiss()
                    }
                } footer: {
                    Text("自動判定（向き・切り取り・色）の結果は本ごとに保存しています。うまくいかないときにやり直してください。手動で回したページはそのままです。")
                }
            }
            .navigationTitle("この本の設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
            .onAppear { draft = model.state.settings }
            .onChange(of: draft) { _, value in
                model.updateSettings(value)
                savedAsDefault = false
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// 補正と表示の設定項目（本ごとの設定と、アプリの既定で共通）
struct CorrectionForm: View {
    @Binding var settings: CorrectionSettings

    var body: some View {
        Section {
            Toggle("横向き・逆さまのページを自動で回す", isOn: $settings.autoRotate)
        } header: {
            Text("向き")
        } footer: {
            Text("横長のページは縦に、逆さまのページは文字の読み取りやすさで判定して回します。判定を間違えたページは、読書画面の回転ボタンで直せます（手動で直した向きは保存されます）。")
        }

        Section {
            Picker("色", selection: $settings.colorMode) {
                ForEach(ColorMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            VStack(alignment: .leading) {
                HStack {
                    Text("黒の濃さ")
                    Spacer()
                    Text(String(format: "%.2f", settings.inkDarkness))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $settings.inkDarkness, in: 0.7...1.8, step: 0.05)
            }
            .disabled(settings.colorMode == .off)
        } header: {
            Text("色・明るさ")
        } footer: {
            Text("ページごとに紙の色を白に、インクの色を黒にそろえるので、黄ばみや濃さのばらつきが目立たなくなります。")
        }

        Section("余白") {
            Toggle("黒い縁・影を消す", isOn: $settings.removeBlackEdges)
            Toggle("白い余白を詰める", isOn: $settings.trimMargins)
        }

        Section("表示") {
            Picker("読む方向", selection: $settings.direction) {
                ForEach(ReadingDirection.allCases) { direction in
                    Text(direction.label).tag(direction)
                }
            }
            Toggle("横向きのときは見開きで表示", isOn: $settings.spreadInLandscape)
            Toggle("見開きで表紙を単独で表示", isOn: $settings.coverAlone)
                .disabled(!settings.spreadInLandscape)
            Picker("めくり方", selection: $settings.pageTurn) {
                ForEach(PageTurnStyle.allCases) { style in
                    Text(style.label).tag(style)
                }
            }
            Toggle("めくるときに軽く振動", isOn: $settings.pageTurnHaptics)
        }
    }
}
