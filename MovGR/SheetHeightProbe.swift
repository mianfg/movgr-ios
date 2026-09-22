import SwiftUI
import UIKit

/// Reports how much of the screen the native sheet currently covers, using the
/// presentation layer of the moving container so chrome can follow the finger.
struct SheetHeightProbe: UIViewRepresentable {
    var onHeight: (CGFloat) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onHeight = onHeight
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.onHeight = onHeight
    }

    final class ProbeView: UIView {
        var onHeight: ((CGFloat) -> Void)?
        private var lastHeight: CGFloat = 0
        private var displayLink: CADisplayLink?
        private lazy var proxy = TickProxy(view: self)

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
            isOpaque = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            makeSheetTranslucent()
            tuneSheetScrolling()
            if window != nil {
                let link = CADisplayLink(target: proxy, selector: #selector(TickProxy.tick))
                link.add(to: .main, forMode: .common)
                displayLink = link
                report()
            } else {
                displayLink?.invalidate()
                displayLink = nil
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            makeSheetTranslucent()
            tuneSheetScrolling()
            report()
        }

        @objc fileprivate func report() {
            makeSheetTranslucent()
            guard let height = coveredHeight() else { return }
            guard abs(height - lastHeight) > 0.15 else { return }
            lastHeight = height
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                onHeight?(height)
            }
        }

        /// Visible card height from the bottom of the screen, including live drag transforms.
        private func coveredHeight() -> CGFloat? {
            guard let window else { return nil }
            guard let moving = movingSheetContainer() else { return nil }
            let card = visualCard(in: moving) ?? moving
            let movingLayer = moving.layer.presentation() ?? moving.layer
            let cardInMoving = moving.convert(card.bounds, from: card)
            let inWindow = movingLayer.convert(cardInMoving, to: window.layer)
            let inScreen = window.convert(inWindow, to: nil)
            let screenMaxY = window.windowScene?.screen.bounds.maxY ?? window.bounds.maxY
            let raw = screenMaxY - inScreen.minY
            let maxH = (window.windowScene?.screen.bounds.height ?? window.bounds.height) - 48
            guard raw.isFinite else { return nil }
            return min(max(raw, 80), maxH)
        }

        private func movingSheetContainer() -> UIView? {
            var view: UIView? = self
            while let current = view {
                let name = NSStringFromClass(type(of: current))
                if name.contains("DropShadowView") {
                    return current
                }
                view = current.superview
            }
            var responder: UIResponder? = self
            while let current = responder {
                if let controller = current as? UIViewController,
                   controller.sheetPresentationController != nil {
                    return controller.view.superview ?? controller.view
                }
                responder = current.next
            }
            return nil
        }

        private func visualCard(in container: UIView) -> UIView? {
            func score(_ view: UIView) -> CGFloat {
                let name = NSStringFromClass(type(of: view))
                if name.contains("Dimming") { return -1 }
                if name.contains("Platter") { return 1_000 + view.bounds.height }
                if view is UIVisualEffectView { return 500 + view.bounds.height }
                if view.backgroundColor != nil || !view.subviews.isEmpty {
                    return view.bounds.height
                }
                return 0
            }
            let candidates = container.subviews.filter { $0.bounds.height > 80 && score($0) >= 0 }
            return candidates.max(by: { score($0) < score($1) })
        }

        /// Keep list scrolling at every detent. Rubber-band at the edges still
        /// resizes the sheet; mid-list scrolling does not.
        private func tuneSheetScrolling() {
            var responder: UIResponder? = self
            while let current = responder {
                if let controller = current as? UIViewController,
                   let sheet = controller.sheetPresentationController {
                    sheet.prefersScrollingExpandsWhenScrolledToEdge = true
                    break
                }
                responder = current.next
            }
            var root: UIView? = self
            while let current = root {
                if current.superview == nil || NSStringFromClass(type(of: current)).contains("DropShadowView") {
                    enableListBounce(in: current)
                    break
                }
                root = current.superview
            }
        }

        private func enableListBounce(in view: UIView) {
            if let scroll = view as? UIScrollView {
                scroll.bounces = true
                scroll.alwaysBounceVertical = true
            }
            view.subviews.forEach(enableListBounce)
        }

        private func makeSheetTranslucent() {
            backgroundColor = .clear
            isOpaque = false
            var view: UIView? = self
            while let current = view {
                let name = NSStringFromClass(type(of: current))
                if name.contains("DropShadowView") || name.contains("Platter") || name.contains("Dimming") {
                    break
                }
                if !(current is UIVisualEffectView) {
                    current.backgroundColor = .clear
                    current.isOpaque = false
                }
                view = current.superview
            }
        }
    }

    private final class TickProxy: NSObject {
        weak var view: ProbeView?
        init(view: ProbeView) { self.view = view }

        @objc func tick() {
            view?.report()
        }
    }
}
