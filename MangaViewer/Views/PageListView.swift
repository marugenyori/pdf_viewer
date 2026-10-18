import SwiftUI

/// ページ一覧。小さな画像を並べ、押したページへ飛ぶ。しおりを付けたページだけにも絞れる
struct PageListView: View {
    @ObservedObject var model: ReaderModel
    @Environment(\.dismiss) private var dismiss
    @State private var bookmarksOnly = false

    private let columns = [GridItem(.adaptive(minimum: 84, maximum: 120), spacing: 10)]

    private var pages: [Int] {
        bookmarksOnly ? model.state.bookmarks.sorted() : Array(0..<model.pageCount)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    if bookmarksOnly && pages.isEmpty {
                        ContentUnavailableView("しおりはまだありません", systemImage: "bookmark",
                                               description: Text("読書画面の上のしおりボタンで、表示中のページにしおりを付けられます。"))
                            .padding(.top, 40)
                    }
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(pages, id: \.self) { page in
                            Button {
                                model.go(toPage: page)
                                dismiss()
                            } label: {
                                PageThumbnailCell(model: model, page: page,
                                                  isCurrent: model.currentPages.contains(page))
                            }
                            .buttonStyle(.plain)
                            .id(page)
                        }
                    }
                    .padding()
                    // 右綴じの本は、右上から左へ並べる
                    .environment(\.layoutDirection,
                                 model.state.settings.direction == .rightToLeft ? .rightToLeft : .leftToRight)
                }
                .onAppear {
                    proxy.scrollTo(model.currentPage, anchor: .center)
                }
            }
            .navigationTitle("ページ一覧")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("表示", selection: $bookmarksOnly) {
                        Text("すべて").tag(false)
                        Text("しおり").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .onDisappear { model.clearPageThumbnails() }
    }
}

private struct PageThumbnailCell: View {
    @ObservedObject var model: ReaderModel
    let page: Int
    let isCurrent: Bool

    var body: some View {
        VStack(spacing: 4) {
            Color.secondary.opacity(0.15)
                .aspectRatio(0.62, contentMode: .fit)
                .overlay {
                    if let image = model.pageThumbnails[page] {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                    } else {
                        ProgressView()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay {
                    if isCurrent {
                        RoundedRectangle(cornerRadius: 4).stroke(.tint, lineWidth: 3)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if model.state.bookmarks.contains(page) {
                        Image(systemName: "bookmark.fill")
                            .foregroundStyle(.red)
                            .padding(4)
                    }
                }
            Text("\(page + 1)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        }
        .environment(\.layoutDirection, .leftToRight)
        .task(id: page) {
            await model.loadPageThumbnail(page)
        }
    }
}
