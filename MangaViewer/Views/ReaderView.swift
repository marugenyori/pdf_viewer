import SwiftUI

/// 1冊を読む画面
struct ReaderView: View {
    @StateObject private var model: ReaderModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var showControls = false
    @State private var showSettings = false
    @State private var sliderValue: Double = 0
    var onClose: () -> Void = {}

    init(book: Book, defaults: CorrectionSettings, onClose: @escaping () -> Void = {}) {
        _model = StateObject(wrappedValue: ReaderModel(book: book, defaults: defaults))
        self.onClose = onClose
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                switch model.phase {
                case .loading(let message):
                    VStack(spacing: 12) {
                        ProgressView().tint(.white)
                        Text(message).font(.callout).foregroundStyle(.white)
                    }
                case .failed(let message):
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                        Text(message).multilineTextAlignment(.center)
                        Button("閉じる") { close() }
                            .buttonStyle(.borderedProminent)
                    }
                    .foregroundStyle(.white)
                    .padding()
                case .ready:
                    pager
                        .ignoresSafeArea()
                }

                if showControls || isFailedOrLoading {
                    controls
                }
            }
            .onAppear { model.setLandscape(geo.size.width > geo.size.height) }
            .onChange(of: geo.size) { _, size in
                model.setLandscape(size.width > size.height)
            }
        }
        .statusBarHidden(!showControls)
        .persistentSystemOverlays(showControls ? .automatic : .hidden)
        .task { await model.open() }
        .onDisappear { model.close() }
        .sheet(isPresented: $showSettings) {
            ReaderSettingsView(model: model)
                .environmentObject(settings)
        }
        .preferredColorScheme(.dark)
    }

    private var isFailedOrLoading: Bool {
        if case .ready = model.phase { return false }
        return true
    }

    private var isRightToLeft: Bool {
        model.state.settings.direction == .rightToLeft
    }

    // MARK: - ページめくり

    @ViewBuilder
    private var pager: some View {
        if model.state.settings.pageTurn == .curl {
            curlPager
        } else {
            slidePager
        }
    }

    /// 紙をめくる動き。めくれる紙は画面全体ではなく、本のページの大きさだけにする
    private var curlPager: some View {
        GeometryReader { geo in
            let aspect = model.spreadMode ? model.pageAspect * 2 : model.pageAspect
            let fit = Self.aspectFit(aspect: aspect, in: geo.size)
            ZStack {
                // 本の外側（黒いところ）のタップも、めくる・メニューを出すに使う
                Color.black
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        handleTap(location.x / max(1, geo.size.width))
                    }
                PageCurlView(model: model, rightToLeft: isRightToLeft, onTap: handleTap)
                    // 綴じ目の位置は作るときにしか決められないので、読む方向を変えたら作り直す
                    .id(model.state.settings.direction)
                    .frame(width: fit.width, height: fit.height)
            }
        }
    }

    /// 縦横比 aspect（幅 ÷ 高さ）の長方形を、size の中にいっぱいに収めた大きさ
    private static func aspectFit(aspect: CGFloat, in size: CGSize) -> CGSize {
        guard aspect > 0, size.width > 0, size.height > 0 else { return size }
        if size.width / size.height > aspect {
            return CGSize(width: size.height * aspect, height: size.height)
        }
        return CGSize(width: size.width, height: size.width / aspect)
    }

    private var slidePager: some View {
        let spreads = model.spreads
        return TabView(selection: $model.spreadIndex) {
            ForEach(spreads.indices, id: \.self) { index in
                SpreadView(model: model, pages: spreads[index], rightToLeft: isRightToLeft, onTap: handleTap)
                    .environment(\.layoutDirection, .leftToRight)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        // 右綴じは、右から左へめくれるように並びを反転させる
        .environment(\.layoutDirection, isRightToLeft ? .rightToLeft : .leftToRight)
        .id("\(spreads.count)-\(model.state.settings.direction.rawValue)")
    }

    /// 画面の左右の端をタップするとページをめくる。真ん中はメニューの表示・非表示
    private func handleTap(_ x: CGFloat) {
        if x < 0.3 {
            model.step(isRightToLeft ? 1 : -1)
        } else if x > 0.7 {
            model.step(isRightToLeft ? -1 : 1)
        } else {
            withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() }
            sliderValue = Double(model.currentPage)
        }
    }

    // MARK: - メニュー

    private var controls: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Button { close() } label: {
                    Image(systemName: "xmark").font(.title3.weight(.semibold))
                }
                Text(model.book.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if case .ready = model.phase {
                    rotateMenu
                    Button { showSettings = true } label: {
                        Image(systemName: "slider.horizontal.3").font(.title3)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)

            Spacer()

            if case .ready = model.phase {
                bottomBar
            }
        }
        .foregroundStyle(.white)
        .transition(.opacity)
    }

    private var rotateMenu: some View {
        Menu {
            Button { model.rotateCurrent(by: 90) } label: {
                Label("右に90°回す", systemImage: "rotate.right")
            }
            Button { model.rotateCurrent(by: -90) } label: {
                Label("左に90°回す", systemImage: "rotate.left")
            }
            Button { model.rotateCurrent(by: 180) } label: {
                Label("180°回す", systemImage: "arrow.2.squarepath")
            }
            if model.currentHasManualRotation {
                Button(role: .destructive) { model.resetCurrentRotation() } label: {
                    Label("手動の回転を取り消す", systemImage: "arrow.uturn.backward")
                }
            }
        } label: {
            Image(systemName: "rotate.right").font(.title3)
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            Toggle(isOn: $model.bypass) {
                Text("補正前を表示（比べる）").font(.subheadline)
            }
            .tint(.orange)

            HStack(spacing: 12) {
                Text(pageLabel)
                    .font(.subheadline.monospacedDigit())
                    .frame(minWidth: 80, alignment: .leading)
                if model.pageCount > 1 {
                    Slider(value: $sliderValue, in: 0...Double(model.pageCount - 1), step: 1, onEditingChanged: { editing in
                        if !editing { model.go(toPage: Int(sliderValue)) }
                    })
                    // 右綴じでは、スライダーも右が1ページ目
                    .environment(\.layoutDirection, isRightToLeft ? .rightToLeft : .leftToRight)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .onChange(of: model.spreadIndex) { _, _ in
            sliderValue = Double(model.currentPage)
        }
    }

    private var pageLabel: String {
        let pages = model.currentPages.map { $0 + 1 }
        let shown = pages.count == 2 ? "\(pages[0])-\(pages[1])" : "\(pages.first ?? 1)"
        return "\(shown) / \(model.pageCount)"
    }

    private func close() {
        model.close()
        onClose()
        dismiss()
    }
}

/// 1ページ、または見開きの2ページ
struct SpreadView: View {
    @ObservedObject var model: ReaderModel
    let pages: [Int]
    let rightToLeft: Bool
    let onTap: (CGFloat) -> Void
    /// 拡大したか（紙をめくる動きのとき、拡大中はめくれないようにするため）
    var onZoom: ((Bool) -> Void)? = nil

    var body: some View {
        if pages.count == 1, let page = pages.first {
            if let image = model.images[page] {
                ZoomableImageView(image: image, onTap: onTap, onZoom: onZoom)
                    .overlay(alignment: .bottomTrailing) {
                        if model.isSideways(page) {
                            // 横向きだったページは、向きの判定を間違えることがあるので、すぐ直せるボタンを出す
                            Button {
                                model.flipSideways(page)
                            } label: {
                                Label("上下を反対に", systemImage: "arrow.triangle.2.circlepath")
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(.ultraThinMaterial, in: Capsule())
                            }
                            .foregroundStyle(.white)
                            .padding(16)
                        }
                    }
            } else {
                placeholder
            }
        } else {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    // 右綴じでは、先に読むページを右側に置く
                    ForEach(rightToLeft ? pages.reversed() : pages, id: \.self) { page in
                        Group {
                            if let image = model.images[page] {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                            } else {
                                placeholder
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: alignment(for: page))
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { location in
                    onTap(location.x / max(1, geo.size.width))
                }
            }
        }
    }

    /// 見開きの2枚が中央でくっつくように寄せる
    private func alignment(for page: Int) -> Alignment {
        let leftSide = rightToLeft ? page == pages.last : page == pages.first
        return leftSide ? .trailing : .leading
    }

    private var placeholder: some View {
        ProgressView()
            .tint(.gray)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
