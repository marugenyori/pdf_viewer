import SwiftUI
import UIKit

/// 紙の端がめくれる動きでページを送る（UIPageViewController の pageCurl）。
/// 右綴じは綴じ目（spine）を右に置き、左端をつまんで右へめくる。左綴じはその逆
struct PageCurlView: UIViewControllerRepresentable {
    @ObservedObject var model: ReaderModel
    let rightToLeft: Bool
    let onTap: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let spine: UIPageViewController.SpineLocation = rightToLeft ? .max : .min
        let controller = UIPageViewController(transitionStyle: .pageCurl, navigationOrientation: .horizontal,
                                              options: [.spineLocation: NSNumber(value: spine.rawValue)])
        controller.isDoubleSided = false
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        controller.view.backgroundColor = Coordinator.paper
        // 端のタップでめくる処理は自分で行う（真ん中のタップでメニューを出すため）
        for gesture in controller.gestureRecognizers where gesture is UITapGestureRecognizer {
            gesture.isEnabled = false
        }
        context.coordinator.pageController = controller
        context.coordinator.spreadCount = model.spreads.count
        controller.setViewControllers([context.coordinator.page(at: model.spreadIndex)], direction: .forward, animated: false)
        return controller
    }

    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        context.coordinator.syncIfNeeded()
    }

    /// 1枚の紙（1ページ、または見開き）
    final class SpreadPage: UIHostingController<AnyView> {
        let index: Int

        init(index: Int, root: AnyView) {
            self.index = index
            super.init(rootView: root)
            safeAreaRegions = []
            view.backgroundColor = Coordinator.paper
        }

        required init?(coder aDecoder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        /// めくれる紙の色。補正後の紙の白に近づけ、余白も紙の一部に見えるようにする
        static let paper = UIColor(white: 0.97, alpha: 1)

        var parent: PageCurlView
        weak var pageController: UIPageViewController?
        var spreadCount = 0
        private var isTransitioning = false

        init(_ parent: PageCurlView) {
            self.parent = parent
        }

        var shownIndex: Int? {
            (pageController?.viewControllers?.first as? SpreadPage)?.index
        }

        func page(at index: Int) -> SpreadPage {
            let model = parent.model
            let spreads = model.spreads
            let pages = spreads.indices.contains(index) ? spreads[index] : []
            let view = SpreadView(model: model, pages: pages, rightToLeft: parent.rightToLeft, onTap: parent.onTap,
                                  onZoom: { [weak self] zoomed in self?.setCurlEnabled(!zoomed) })
                .environment(\.layoutDirection, .leftToRight)
                .background(Color(uiColor: Self.paper))
            return SpreadPage(index: index, root: AnyView(view))
        }

        /// 拡大中は、指で動かしたときに紙がめくれないようにする
        private func setCurlEnabled(_ enabled: Bool) {
            for gesture in pageController?.gestureRecognizers ?? [] where gesture is UIPanGestureRecognizer {
                gesture.isEnabled = enabled
            }
        }

        /// 読書画面の状態（スライダーやタップでのページ移動、見開きの切り替え）に表示を合わせる
        func syncIfNeeded() {
            guard let controller = pageController, !isTransitioning else { return }
            let target = parent.model.spreadIndex
            let count = parent.model.spreads.count
            if count != spreadCount {
                // 見開きの切り替えなどで並びが変わったら、アニメーションなしで差し替える
                spreadCount = count
                controller.setViewControllers([page(at: target)], direction: .forward, animated: false)
                return
            }
            guard let shown = shownIndex, shown != target else { return }
            // UIKit の forward は左綴じの向き。右綴じでは逆にする（下のデータソースも同じ）
            let ahead = (target > shown) != parent.rightToLeft
            let direction: UIPageViewController.NavigationDirection = ahead ? .forward : .reverse
            // 隣のページならめくる。離れたページへは一気に移る
            let animated = abs(target - shown) == 1
            isTransitioning = animated
            controller.setViewControllers([page(at: target)], direction: direction, animated: animated) { [weak self] _ in
                self?.isTransitioning = false
                self?.syncIfNeeded()
            }
        }

        // MARK: データソース

        // UIKit の「後ろ（after）」は、綴じ目の位置にかかわらず左綴じの向き（右端をつまんで左へ）だった。
        // 右綴じでは before と after を入れ替えて、左端をつまんで右へめくると次のページに進むようにする
        func pageViewController(_ pageViewController: UIPageViewController,
                                viewControllerBefore viewController: UIViewController) -> UIViewController? {
            neighbor(of: viewController, step: parent.rightToLeft ? 1 : -1)
        }

        func pageViewController(_ pageViewController: UIPageViewController,
                                viewControllerAfter viewController: UIViewController) -> UIViewController? {
            neighbor(of: viewController, step: parent.rightToLeft ? -1 : 1)
        }

        private func neighbor(of viewController: UIViewController, step: Int) -> UIViewController? {
            guard let index = (viewController as? SpreadPage)?.index else { return nil }
            let target = index + step
            guard target >= 0, target < parent.model.spreads.count else { return nil }
            return page(at: target)
        }

        // MARK: 指でめくったとき

        func pageViewController(_ pageViewController: UIPageViewController,
                                willTransitionTo pendingViewControllers: [UIViewController]) {
            isTransitioning = true
        }

        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            isTransitioning = false
            if completed, let index = shownIndex, parent.model.spreadIndex != index {
                parent.model.spreadIndex = index
            }
        }
    }
}
