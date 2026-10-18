import SwiftUI
import UIKit

/// ピンチ・ダブルタップで拡大できる画像。1回のタップは横位置（0〜1）を知らせる
struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage
    var onTap: (CGFloat) -> Void
    var onZoom: ((Bool) -> Void)? = nil

    func makeUIView(context: Context) -> ZoomScrollView {
        ZoomScrollView()
    }

    func updateUIView(_ view: ZoomScrollView, context: Context) {
        view.onTap = onTap
        view.onZoom = onZoom
        if view.imageView.image !== image {
            view.imageView.image = image
            view.setZoomScale(1, animated: false)
        }
    }
}

final class ZoomScrollView: UIScrollView, UIScrollViewDelegate {
    let imageView = UIImageView()
    var onTap: ((CGFloat) -> Void)?
    var onZoom: ((Bool) -> Void)?
    private var isZoomed = false
    private var lastSize: CGSize = .zero

    init() {
        super.init(frame: .zero)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 4
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        backgroundColor = .clear
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
        singleTap.require(toFail: doubleTap)
        addGestureRecognizer(singleTap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != lastSize {
            lastSize = bounds.size
            setZoomScale(1, animated: false)
            imageView.frame = bounds
            contentSize = bounds.size
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        let zoomed = zoomScale > 1.01
        if zoomed != isZoomed {
            isZoomed = zoomed
            onZoom?(zoomed)
        }
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if zoomScale > 1.01 {
            setZoomScale(1, animated: true)
        } else {
            let point = gesture.location(in: imageView)
            let scale: CGFloat = 2.5
            let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                            width: size.width, height: size.height), animated: true)
        }
    }

    @objc private func handleSingleTap(_ gesture: UITapGestureRecognizer) {
        guard bounds.width > 0 else { return }
        let x = gesture.location(in: self).x - contentOffset.x
        onTap?(x / bounds.width)
    }
}
