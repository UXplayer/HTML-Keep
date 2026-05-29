import SwiftUI
import UIKit

struct HomeSearchScrollMetrics: Equatable {
    let isAtTop: Bool
    let topOverscrollDistance: CGFloat
    let isActivelyDragging: Bool
    let didEndDragging: Bool

    static func == (lhs: HomeSearchScrollMetrics, rhs: HomeSearchScrollMetrics) -> Bool {
        lhs.isAtTop == rhs.isAtTop
            && abs(lhs.topOverscrollDistance - rhs.topOverscrollDistance) < homeSearchScrollMetricTolerance
            && lhs.isActivelyDragging == rhs.isActivelyDragging
            && lhs.didEndDragging == rhs.didEndDragging
    }
}

@MainActor
final class HomeSearchScrollController: ObservableObject {
    private weak var scrollView: UIScrollView?
    private var lockedContentOffset: CGPoint?
    private var originalBounces: Bool?
    private var originalAlwaysBounceVertical: Bool?

    var isLocked: Bool {
        lockedContentOffset != nil
    }

    func attach(_ scrollView: UIScrollView) {
        self.scrollView = scrollView
        scrollView.alwaysBounceVertical = true
        enforceLockIfNeeded()
    }

    func detach(_ scrollView: UIScrollView) {
        guard self.scrollView === scrollView else { return }
        unlock()
        self.scrollView = nil
    }

    func lockAtRestingTop() {
        guard let scrollView else { return }
        if lockedContentOffset == nil {
            originalBounces = scrollView.bounces
            originalAlwaysBounceVertical = scrollView.alwaysBounceVertical
        }
        let restingTopOffset = CGPoint(
            x: scrollView.contentOffset.x,
            y: -scrollView.adjustedContentInset.top
        )
        lockedContentOffset = restingTopOffset
        scrollView.bounces = false
        scrollView.alwaysBounceVertical = false
        scrollView.setContentOffset(restingTopOffset, animated: false)
    }

    func enforceLockIfNeeded() {
        guard let scrollView,
              let lockedContentOffset else {
            return
        }
        if abs(scrollView.contentOffset.x - lockedContentOffset.x) > homeSearchScrollMetricTolerance
            || abs(scrollView.contentOffset.y - lockedContentOffset.y) > homeSearchScrollMetricTolerance {
            scrollView.setContentOffset(lockedContentOffset, animated: false)
        }
    }

    func unlock() {
        guard let scrollView,
              lockedContentOffset != nil else {
            clearLockState()
            return
        }

        if let originalBounces {
            scrollView.bounces = originalBounces
        }
        if let originalAlwaysBounceVertical {
            scrollView.alwaysBounceVertical = originalAlwaysBounceVertical
        }
        clearLockState()
    }

    private func clearLockState() {
        lockedContentOffset = nil
        originalBounces = nil
        originalAlwaysBounceVertical = nil
    }
}

struct HomeSearchScrollObserver: UIViewRepresentable {
    let scrollController: HomeSearchScrollController
    let onChange: (HomeSearchScrollMetrics) -> Void

    func makeUIView(context _: Context) -> ObserverView {
        let view = ObserverView()
        view.scrollController = scrollController
        view.onChange = onChange
        return view
    }

    func updateUIView(_ uiView: ObserverView, context _: Context) {
        uiView.scrollController = scrollController
        uiView.onChange = onChange
        uiView.installIfPossible()
    }

    static func dismantleUIView(_ uiView: ObserverView, coordinator _: ()) {
        uiView.uninstall()
    }

    final class ObserverView: UIView {
        weak var scrollController: HomeSearchScrollController?
        var onChange: ((HomeSearchScrollMetrics) -> Void)?
        private weak var observedScrollView: UIScrollView?
        private var contentOffsetObservation: NSKeyValueObservation?
        private var adjustedContentInsetObservation: NSKeyValueObservation?
        private var lastMetrics: HomeSearchScrollMetrics?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            installOnNextRunLoop()
        }

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            installOnNextRunLoop()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            installIfPossible()
        }

        func installIfPossible() {
            guard window != nil,
                  let scrollView = nearestScrollView(),
                  observedScrollView !== scrollView else {
                if let observedScrollView {
                    emitMetrics(for: observedScrollView)
                }
                return
            }

            uninstall()
            observedScrollView = scrollView
            scrollController?.attach(scrollView)
            scrollView.panGestureRecognizer.addTarget(self, action: #selector(handlePanGesture(_:)))
            contentOffsetObservation = scrollView.observe(\.contentOffset, options: [.initial, .new]) { [weak self] scrollView, _ in
                self?.emitMetrics(for: scrollView)
            }
            adjustedContentInsetObservation = scrollView.observe(\.adjustedContentInset, options: [.new]) { [weak self] scrollView, _ in
                self?.emitMetrics(for: scrollView)
            }
        }

        func uninstall() {
            if let observedScrollView {
                observedScrollView.panGestureRecognizer.removeTarget(self, action: #selector(handlePanGesture(_:)))
                scrollController?.detach(observedScrollView)
            }
            contentOffsetObservation?.invalidate()
            adjustedContentInsetObservation?.invalidate()
            contentOffsetObservation = nil
            adjustedContentInsetObservation = nil
            observedScrollView = nil
            lastMetrics = nil
        }

        private func installOnNextRunLoop() {
            DispatchQueue.main.async { [weak self] in
                self?.installIfPossible()
            }
        }

        @objc private func handlePanGesture(_ recognizer: UIPanGestureRecognizer) {
            guard let scrollView = recognizer.view as? UIScrollView ?? observedScrollView else {
                return
            }
            emitMetrics(for: scrollView)
        }

        private func nearestScrollView() -> UIScrollView? {
            var current = superview
            while let view = current {
                if let scrollView = view as? UIScrollView {
                    return scrollView
                }
                if let scrollView = firstScrollView(in: view) {
                    return scrollView
                }
                current = view.superview
            }
            return window.flatMap { firstScrollView(in: $0) }
        }

        private func firstScrollView(in view: UIView) -> UIScrollView? {
            for subview in view.subviews {
                if let scrollView = subview as? UIScrollView {
                    return scrollView
                }
                if let scrollView = firstScrollView(in: subview) {
                    return scrollView
                }
            }
            return nil
        }

        private func emitMetrics(for scrollView: UIScrollView) {
            scrollController?.enforceLockIfNeeded()
            let distanceFromTop = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
            let panState = scrollView.panGestureRecognizer.state
            let isPanChanging = panState == .began || panState == .changed
            let isDirectUserDrag = scrollView.isTracking
                && !scrollView.isDecelerating
                && (scrollView.isDragging || isPanChanging)
            let metrics = HomeSearchScrollMetrics(
                isAtTop: distanceFromTop <= homeSearchTopTolerance,
                topOverscrollDistance: max(-distanceFromTop, 0),
                isActivelyDragging: isDirectUserDrag,
                didEndDragging: panState == .ended || panState == .cancelled || panState == .failed
            )
            guard metrics != lastMetrics else { return }
            lastMetrics = metrics
            DispatchQueue.main.async { [weak self] in
                self?.onChange?(metrics)
            }
        }
    }
}
