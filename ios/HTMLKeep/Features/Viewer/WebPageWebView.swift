import SwiftUI
import UIKit
import WebKit

struct WebPageWebView: UIViewRepresentable {
    let page: WebPage
    let entryURL: URL
    let entryHTML: String?
    let readAccessURL: URL
    let reloadToken: UUID
    let pageZoom: CGFloat
    let onLoadStateChange: (ViewerLoadState) -> Void
    let onRequestDismiss: () -> Void
    let onRuntimeStorageChange: () -> Void
    let onLocalFileNavigation: (URL) -> Void
    let onExternalNavigationFailure: (URL) -> Void
    let onUnsupportedNewWindowRequest: () -> Void
    let onScrollOffsetChange: (CGFloat) -> Void
    let onTopOverlayPreferenceChange: (Bool) -> Void
    let onWebViewReady: (WKWebView) -> Void
    let viewportBackground: ViewerViewportBackground

    private static let scrollMetricsMessageName = "htmlAnywhereScrollMetrics"
    private static let topOverlayPreferenceMessageName = "htmlAnywhereTopOverlayPreference"

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.ignoresViewportScaleLimits = false
        configuration.websiteDataStore = WebPageRuntimeStorage.websiteDataStore(for: page)

        configuration.userContentController.add(
            context.coordinator,
            name: WebPageRuntimeStorage.localStorageMessageName
        )
        configuration.userContentController.add(
            context.coordinator,
            name: Self.scrollMetricsMessageName
        )
        configuration.userContentController.add(
            context.coordinator,
            name: Self.topOverlayPreferenceMessageName
        )

        let scrollMetricsScript = WKUserScript(
            source: Self.scrollMetricsScript(messageName: Self.scrollMetricsMessageName),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        configuration.userContentController.addUserScript(scrollMetricsScript)

        let runtimeStorageScript = WKUserScript(
            source: Self.runtimeStorageScript(projectFolderURL: readAccessURL),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        configuration.userContentController.addUserScript(runtimeStorageScript)

        let topOverlayPreferenceScript = WKUserScript(
            source: Self.topOverlayPreferenceScript(messageName: Self.topOverlayPreferenceMessageName),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        configuration.userContentController.addUserScript(topOverlayPreferenceScript)

        let webView = ViewerWKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.pageZoom = pageZoom
        webView.allowsBackForwardNavigationGestures = false
        webView.applyViewportBackground(viewportBackground)
        webView.scrollView.delegate = context.coordinator
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        configureNonZoomingWebView(webView)
        context.coordinator.attachBrowserSmartZoomFallback(to: webView)
        webView.applyViewportInsetsIfNeeded(force: true)

        load(in: webView)
        onWebViewReady(webView)
        return webView
    }

    private func configureNonZoomingWebView(_ webView: WKWebView) {
        let scrollView = webView.scrollView
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 1
        scrollView.zoomScale = 1
        scrollView.bouncesZoom = false
        scrollView.pinchGestureRecognizer?.isEnabled = false
        scrollView.scrollsToTop = false
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onLoadStateChange = onLoadStateChange
        context.coordinator.onRequestDismiss = onRequestDismiss
        context.coordinator.onRuntimeStorageChange = onRuntimeStorageChange
        context.coordinator.onLocalFileNavigation = onLocalFileNavigation
        context.coordinator.onExternalNavigationFailure = onExternalNavigationFailure
        context.coordinator.onUnsupportedNewWindowRequest = onUnsupportedNewWindowRequest
        context.coordinator.onScrollOffsetChange = onScrollOffsetChange
        context.coordinator.onTopOverlayPreferenceChange = onTopOverlayPreferenceChange
        context.coordinator.projectFolderURL = readAccessURL
        context.coordinator.virtualEntryURL = entryHTML == nil ? nil : entryURL
        if abs(webView.pageZoom - pageZoom) > 0.001 {
            webView.pageZoom = pageZoom
        }
        if let viewerWebView = webView as? ViewerWKWebView {
            viewerWebView.applyViewportBackground(viewportBackground)
            viewerWebView.applyViewportInsetsIfNeeded()
        }
        if !Self.hasSameFilePathAndQuery(context.coordinator.loadedEntryURL, entryURL) ||
            context.coordinator.reloadToken != reloadToken {
            load(in: webView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onLoadStateChange: onLoadStateChange,
            onRequestDismiss: onRequestDismiss,
            onRuntimeStorageChange: onRuntimeStorageChange,
            onLocalFileNavigation: onLocalFileNavigation,
            onExternalNavigationFailure: onExternalNavigationFailure,
            onUnsupportedNewWindowRequest: onUnsupportedNewWindowRequest,
            onScrollOffsetChange: onScrollOffsetChange,
            onTopOverlayPreferenceChange: onTopOverlayPreferenceChange,
            projectFolderURL: readAccessURL
        )
    }

    private func load(in webView: WKWebView) {
        if let coordinator = webView.navigationDelegate as? Coordinator {
            coordinator.loadedEntryURL = entryURL
            coordinator.reloadToken = reloadToken
            coordinator.projectFolderURL = readAccessURL
            coordinator.virtualEntryURL = entryHTML == nil ? nil : entryURL
        }
        if let entryHTML {
            webView.loadHTMLString(entryHTML, baseURL: readAccessURL)
        } else {
            webView.loadFileURL(entryURL, allowingReadAccessTo: readAccessURL)
        }
    }

    private static func hasSameFilePathAndQuery(_ lhs: URL?, _ rhs: URL) -> Bool {
        guard let lhs else { return false }
        return URL(fileURLWithPath: lhs.path).standardizedFileURL.path ==
            URL(fileURLWithPath: rhs.path).standardizedFileURL.path &&
            URLComponents(url: lhs, resolvingAgainstBaseURL: false)?.percentEncodedQuery ==
            URLComponents(url: rhs, resolvingAgainstBaseURL: false)?.percentEncodedQuery
    }

    private final class ViewerWKWebView: WKWebView {
        private let viewportBackgroundView = ViewerViewportBackgroundView()

        func applyViewportBackground(_ background: ViewerViewportBackground) {
            isOpaque = false
            backgroundColor = .clear
            scrollView.isOpaque = false
            scrollView.backgroundColor = .clear
            viewportBackgroundView.background = background
            if viewportBackgroundView.superview == nil {
                insertSubview(viewportBackgroundView, at: 0)
                sendSubviewToBack(viewportBackgroundView)
            }
            if !viewportBackgroundView.frame.isApproximatelyEqual(to: bounds) {
                viewportBackgroundView.frame = bounds
            }
        }

        func applyViewportInsetsIfNeeded(force: Bool = false) {
            let topInset = max(safeAreaInsets.top, 0)
            let scrollView = self.scrollView
            let previousInset = scrollView.contentInset
            let insetDidChange = abs(previousInset.top - topInset) > 0.5 || abs(previousInset.bottom) > 0.5
            guard force || insetDidChange else {
                return
            }

            let wasAtAdjustedTop = scrollView.contentOffset.y <= -previousInset.top + 1
            let wasAtUnadjustedTop = abs(previousInset.top - topInset) < 0.5 && abs(scrollView.contentOffset.y) < 1 && topInset > 0
            let normalizedOffsetY = max(scrollView.contentOffset.y + previousInset.top, 0)

            var nextInset = previousInset
            nextInset.top = topInset
            nextInset.bottom = 0
            scrollView.contentInset = nextInset
            let previousIndicatorInsets = scrollView.verticalScrollIndicatorInsets
            scrollView.verticalScrollIndicatorInsets = UIEdgeInsets(
                top: topInset,
                left: previousIndicatorInsets.left,
                bottom: 0,
                right: previousIndicatorInsets.right
            )

            let shouldKeepAtTop = wasAtAdjustedTop || wasAtUnadjustedTop
            let nextOffsetY = shouldKeepAtTop ? -topInset : normalizedOffsetY - topInset
            if abs(scrollView.contentOffset.y - nextOffsetY) > 0.5 {
                scrollView.setContentOffset(
                    CGPoint(x: scrollView.contentOffset.x, y: nextOffsetY),
                    animated: false
                )
            }
        }

        func alignContentOffsetToTopInsetIfNeeded() {
            let topInset = scrollView.contentInset.top
            guard topInset > 0,
                  abs(scrollView.contentOffset.y) < 1,
                  !scrollView.isTracking,
                  !scrollView.isDragging,
                  !scrollView.isDecelerating else {
                return
            }

            scrollView.setContentOffset(
                CGPoint(x: scrollView.contentOffset.x, y: -topInset),
                animated: false
            )
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            applyViewportInsetsIfNeeded(force: true)
        }

        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()
            applyViewportInsetsIfNeeded(force: true)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            if !viewportBackgroundView.frame.isApproximatelyEqual(to: bounds) {
                viewportBackgroundView.frame = bounds
            }
            sendSubviewToBack(viewportBackgroundView)
            applyViewportInsetsIfNeeded()
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var loadedEntryURL: URL?
        var reloadToken: UUID?
        var onLoadStateChange: (ViewerLoadState) -> Void
        var onRequestDismiss: () -> Void
        var onRuntimeStorageChange: () -> Void
        var onLocalFileNavigation: (URL) -> Void
        var onExternalNavigationFailure: (URL) -> Void
        var onUnsupportedNewWindowRequest: () -> Void
        var onScrollOffsetChange: (CGFloat) -> Void
        var onTopOverlayPreferenceChange: (Bool) -> Void
        var projectFolderURL: URL
        var virtualEntryURL: URL?
        private weak var webView: WKWebView?
        private var doubleTapObserver: UITapGestureRecognizer?
        private var lastStableContentOffset: CGPoint = .zero
        private var browserTapSuppressionDeadline: CFTimeInterval = 0
        private var browserTapSuppressionOffset: CGPoint?

        init(
            onLoadStateChange: @escaping (ViewerLoadState) -> Void,
            onRequestDismiss: @escaping () -> Void,
            onRuntimeStorageChange: @escaping () -> Void,
            onLocalFileNavigation: @escaping (URL) -> Void,
            onExternalNavigationFailure: @escaping (URL) -> Void,
            onUnsupportedNewWindowRequest: @escaping () -> Void,
            onScrollOffsetChange: @escaping (CGFloat) -> Void,
            onTopOverlayPreferenceChange: @escaping (Bool) -> Void,
            projectFolderURL: URL
        ) {
            self.onLoadStateChange = onLoadStateChange
            self.onRequestDismiss = onRequestDismiss
            self.onRuntimeStorageChange = onRuntimeStorageChange
            self.onLocalFileNavigation = onLocalFileNavigation
            self.onExternalNavigationFailure = onExternalNavigationFailure
            self.onUnsupportedNewWindowRequest = onUnsupportedNewWindowRequest
            self.onScrollOffsetChange = onScrollOffsetChange
            self.onTopOverlayPreferenceChange = onTopOverlayPreferenceChange
            self.projectFolderURL = projectFolderURL
        }

        func attachBrowserSmartZoomFallback(to webView: WKWebView) {
            self.webView = webView
            lastStableContentOffset = webView.scrollView.contentOffset
            onScrollOffsetChange(normalizedTopScrollOffset(for: webView.scrollView))

            guard doubleTapObserver == nil else {
                return
            }

            // Fallback only: public WebKit viewport controls should prevent zoom first. This observer
            // does not cancel HTML touches; it only restores native smart-zoom offset drift.
            let observer = UITapGestureRecognizer(target: self, action: #selector(handleBrowserDoubleTap(_:)))
            observer.numberOfTapsRequired = 2
            observer.cancelsTouchesInView = false
            observer.delaysTouchesBegan = false
            observer.delaysTouchesEnded = false
            observer.delegate = self
            webView.addGestureRecognizer(observer)
            doubleTapObserver = observer
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            onLoadStateChange(.loading)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let finishedEntryURL = virtualEntryURL ?? webView.url
            loadedEntryURL = finishedEntryURL
            if let viewerWebView = webView as? ViewerWKWebView {
                viewerWebView.applyViewportInsetsIfNeeded(force: true)
                viewerWebView.alignContentOffsetToTopInsetIfNeeded()
            }
            webView.scrollView.zoomScale = 1
            lastStableContentOffset = webView.scrollView.contentOffset
            onScrollOffsetChange(normalizedTopScrollOffset(for: webView.scrollView))
            webView.evaluateJavaScript("window.__htmlAnywhereCaptureLocalStorage && window.__htmlAnywhereCaptureLocalStorage();")
            onLoadStateChange(.loaded)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.targetFrame?.isMainFrame != false,
                  let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            guard url.isFileURL else {
                if Self.shouldOpenExternally(url) {
                    decisionHandler(.cancel)
                    openExternally(url)
                } else {
                    decisionHandler(.allow)
                }
                return
            }

            guard Self.isDescendant(url, of: projectFolderURL) else {
                decisionHandler(.cancel)
                return
            }

            if url.fragment != nil,
               Self.hasSameFilePathAndQuery(url, webView.url) {
                decisionHandler(.allow)
                return
            }

            guard let target = Self.localHTMLNavigationTarget(for: url, in: projectFolderURL) else {
                decisionHandler(.allow)
                return
            }

            if Self.isSameNavigationURL(target.loadURL, loadedEntryURL) {
                decisionHandler(.allow)
                return
            }

            decisionHandler(.cancel)
            onLocalFileNavigation(target.loadURL)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            guard navigationAction.targetFrame == nil else {
                return nil
            }

            guard let url = navigationAction.request.url else {
                onUnsupportedNewWindowRequest()
                return nil
            }

            if url.isFileURL {
                openLocalFileNavigation(url, in: webView)
            } else if Self.shouldOpenExternally(url) {
                openExternally(url)
            } else {
                onUnsupportedNewWindowRequest()
            }
            return nil
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == WebPageWebView.scrollMetricsMessageName {
                if let body = message.body as? [String: Any],
                   let offsetY = body["offsetY"] as? NSNumber {
                    onScrollOffsetChange(max(CGFloat(truncating: offsetY), 0))
                }
                return
            }

            if message.name == WebPageWebView.topOverlayPreferenceMessageName {
                guard let body = message.body as? [String: Any] else {
                    return
                }

                if let prefersTopSafeArea = body["prefersTopSafeArea"] as? Bool {
                    onTopOverlayPreferenceChange(prefersTopSafeArea)
                } else if let prefersTopSafeArea = body["prefersTopSafeArea"] as? NSNumber {
                    onTopOverlayPreferenceChange(prefersTopSafeArea.boolValue)
                }
                return
            }

            guard message.name == WebPageRuntimeStorage.localStorageMessageName,
                  let body = message.body as? [String: Any],
                  let rawItems = body["items"] as? [String: Any] else {
                return
            }

            var items: [String: String] = [:]
            for (key, value) in rawItems {
                if let value = value as? String {
                    items[key] = value
                } else if let value = value as? CustomStringConvertible {
                    items[key] = value.description
                }
            }

            let bootstrapState = WebPageRuntimeStorage.localStorageBootstrapState(in: projectFolderURL)
            guard !items.isEmpty || bootstrapState.hasSnapshot else {
                return
            }
            if WebPageRuntimeStorage.saveLocalStorageItems(items, in: projectFolderURL) {
                onRuntimeStorageChange()
            }
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            nil
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let hasRealVerticalScrollRange = hasRealVerticalScrollRange(in: scrollView)
            onScrollOffsetChange(hasRealVerticalScrollRange ? normalizedTopScrollOffset(for: scrollView) : 0)

            guard !restoreBrowserTapOffsetIfNeeded(in: scrollView) else {
                return
            }

            if scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating {
                lastStableContentOffset = scrollView.contentOffset
            } else if browserTapSuppressionOffset == nil {
                lastStableContentOffset = scrollView.contentOffset
            }
        }

        func scrollViewWillEndDragging(
            _ scrollView: UIScrollView,
            withVelocity velocity: CGPoint,
            targetContentOffset: UnsafeMutablePointer<CGPoint>
        ) {
            guard !hasRealVerticalScrollRange(in: scrollView) else {
                return
            }

            targetContentOffset.pointee.y = topInsetAnchoredOffsetY(for: scrollView)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            guard !decelerate else {
                return
            }

            restoreTopInsetAnchorForShortDocumentIfNeeded(in: scrollView, animated: true)
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            restoreTopInsetAnchorForShortDocumentIfNeeded(in: scrollView, animated: true)
        }

        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            if !hasRealVerticalScrollRange(in: scrollView) {
                lastStableContentOffset = scrollView.contentOffset
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            gestureRecognizer === doubleTapObserver
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            gestureRecognizer === doubleTapObserver
        }

        @objc private func handleBrowserDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let scrollView = webView?.scrollView else {
                return
            }

            browserTapSuppressionOffset = lastStableContentOffset
            browserTapSuppressionDeadline = CACurrentMediaTime() + 0.45
            restoreBrowserTapOffset(in: scrollView)

            [0.02, 0.08, 0.18, 0.32].forEach { delay in
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak scrollView] in
                    guard let self, let scrollView else {
                        return
                    }
                    self.restoreBrowserTapOffsetIfNeeded(in: scrollView)
                }
            }
        }

        @discardableResult
        private func restoreBrowserTapOffsetIfNeeded(in scrollView: UIScrollView) -> Bool {
            guard
                browserTapSuppressionDeadline > CACurrentMediaTime(),
                browserTapSuppressionOffset != nil,
                !scrollView.isTracking,
                !scrollView.isDragging,
                !scrollView.isDecelerating
            else {
                if browserTapSuppressionDeadline <= CACurrentMediaTime() {
                    browserTapSuppressionOffset = nil
                }
                return false
            }

            restoreBrowserTapOffset(in: scrollView)
            return true
        }

        private func restoreBrowserTapOffset(in scrollView: UIScrollView) {
            guard let targetOffset = browserTapSuppressionOffset else {
                return
            }

            scrollView.setZoomScale(1, animated: false)
            if scrollView.contentOffset != targetOffset {
                scrollView.setContentOffset(targetOffset, animated: false)
            }
        }

        private func openExternally(_ url: URL) {
            UIApplication.shared.open(url, options: [:]) { [weak self] success in
                guard !success else {
                    return
                }
                DispatchQueue.main.async {
                    self?.onExternalNavigationFailure(url)
                }
            }
        }

        private func openLocalFileNavigation(_ url: URL, in webView: WKWebView) {
            guard Self.isDescendant(url, of: projectFolderURL) else {
                onUnsupportedNewWindowRequest()
                return
            }

            guard let target = Self.localHTMLNavigationTarget(for: url, in: projectFolderURL) else {
                webView.loadFileURL(url, allowingReadAccessTo: projectFolderURL)
                return
            }

            guard !Self.isSameNavigationURL(target.loadURL, loadedEntryURL) else {
                return
            }

            onLocalFileNavigation(target.loadURL)
        }

        private static func isHTMLFileURL(_ url: URL) -> Bool {
            let fileExtension = url.pathExtension.lowercased()
            return fileExtension == "html" || fileExtension == "htm"
        }

        private struct LocalHTMLNavigationTarget {
            var entryURL: URL
            var loadURL: URL
        }

        private static let directoryEntryHTMLFileNames = [
            "index.html",
            "index.htm",
            "default.html",
            "default.htm"
        ]

        private static func localHTMLNavigationTarget(
            for url: URL,
            in projectFolderURL: URL,
            fileManager: FileManager = .default
        ) -> LocalHTMLNavigationTarget? {
            let fileSystemURL = fileSystemURL(for: url)
            if isHTMLFileURL(fileSystemURL) {
                return LocalHTMLNavigationTarget(
                    entryURL: fileSystemURL,
                    loadURL: fileURL(fileSystemURL, carryingNavigationStateFrom: url)
                )
            }

            guard let directoryEntryURL = directoryEntryHTMLURL(
                for: fileSystemURL,
                in: projectFolderURL,
                fileManager: fileManager
            ) else {
                return nil
            }

            return LocalHTMLNavigationTarget(
                entryURL: directoryEntryURL,
                loadURL: fileURL(directoryEntryURL, carryingNavigationStateFrom: url)
            )
        }

        private static func fileSystemURL(for url: URL) -> URL {
            URL(fileURLWithPath: url.path, isDirectory: url.hasDirectoryPath).standardizedFileURL
        }

        private static func fileURL(_ fileURL: URL, carryingNavigationStateFrom navigationURL: URL) -> URL {
            guard var components = URLComponents(url: fileURL, resolvingAgainstBaseURL: false),
                  let navigationComponents = URLComponents(url: navigationURL, resolvingAgainstBaseURL: false) else {
                return fileURL
            }

            components.query = navigationComponents.query
            components.fragment = navigationComponents.fragment
            return components.url ?? fileURL
        }

        private static func directoryEntryHTMLURL(
            for url: URL,
            in projectFolderURL: URL,
            fileManager: FileManager
        ) -> URL? {
            let isExistingDirectory = isExistingDirectory(url, fileManager: fileManager)
            guard isExistingDirectory || url.hasDirectoryPath || url.pathExtension.isEmpty else {
                return nil
            }

            for fileName in directoryEntryHTMLFileNames {
                let candidateURL = url.appendingPathComponent(fileName, isDirectory: false).standardizedFileURL
                guard isDescendant(candidateURL, of: projectFolderURL),
                      isExistingRegularFile(candidateURL, fileManager: fileManager) else {
                    continue
                }
                return candidateURL
            }

            return nil
        }

        private static func isExistingDirectory(_ url: URL, fileManager: FileManager) -> Bool {
            var isDirectory = ObjCBool(false)
            return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }

        private static func isExistingRegularFile(_ url: URL, fileManager: FileManager) -> Bool {
            var isDirectory = ObjCBool(false)
            return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
        }

        private static func isDescendant(_ url: URL, of rootURL: URL) -> Bool {
            let rootPath = rootURL.standardizedFileURL.path
            let candidatePath = url.standardizedFileURL.path
            return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
        }

        private static func hasSameFilePathAndQuery(_ lhs: URL, _ rhs: URL?) -> Bool {
            guard let rhs else { return false }
            return fileSystemURL(for: lhs).path == fileSystemURL(for: rhs).path &&
                URLComponents(url: lhs, resolvingAgainstBaseURL: false)?.percentEncodedQuery ==
                URLComponents(url: rhs, resolvingAgainstBaseURL: false)?.percentEncodedQuery
        }

        private static func isSameNavigationURL(_ lhs: URL, _ rhs: URL?) -> Bool {
            guard let rhs else { return false }
            let lhsComponents = URLComponents(url: lhs, resolvingAgainstBaseURL: false)
            let rhsComponents = URLComponents(url: rhs, resolvingAgainstBaseURL: false)
            return fileSystemURL(for: lhs).path == fileSystemURL(for: rhs).path &&
                lhsComponents?.percentEncodedQuery == rhsComponents?.percentEncodedQuery &&
                lhsComponents?.percentEncodedFragment == rhsComponents?.percentEncodedFragment
        }

        private static func shouldOpenExternally(_ url: URL) -> Bool {
            guard let scheme = url.scheme?.lowercased() else {
                return false
            }

            let webKitInternalSchemes: Set<String> = [
                "about",
                "blob",
                "data",
                "javascript"
            ]
            return !webKitInternalSchemes.contains(scheme)
        }

        private func normalizedTopScrollOffset(for scrollView: UIScrollView) -> CGFloat {
            max(scrollView.contentOffset.y + scrollView.adjustedContentInset.top, 0)
        }

        private func hasRealVerticalScrollRange(in scrollView: UIScrollView) -> Bool {
            scrollView.contentSize.height > scrollView.bounds.height + 1
        }

        private func topInsetAnchoredOffsetY(for scrollView: UIScrollView) -> CGFloat {
            -scrollView.adjustedContentInset.top
        }

        private func restoreTopInsetAnchorForShortDocumentIfNeeded(
            in scrollView: UIScrollView,
            animated: Bool
        ) {
            guard !hasRealVerticalScrollRange(in: scrollView),
                  !scrollView.isTracking,
                  !scrollView.isDragging,
                  !scrollView.isDecelerating else {
                return
            }

            let topOffsetY = topInsetAnchoredOffsetY(for: scrollView)
            guard abs(scrollView.contentOffset.y - topOffsetY) > 0.5 else {
                return
            }

            scrollView.setContentOffset(
                CGPoint(x: scrollView.contentOffset.x, y: topOffsetY),
                animated: animated
            )
            lastStableContentOffset = CGPoint(x: scrollView.contentOffset.x, y: topOffsetY)
            onScrollOffsetChange(0)
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            onLoadStateChange(.failed(error.localizedDescription))
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            onLoadStateChange(.failed(error.localizedDescription))
        }
    }
}

private extension CGRect {
    func isApproximatelyEqual(to other: CGRect) -> Bool {
        abs(origin.x - other.origin.x) < 0.5 &&
            abs(origin.y - other.origin.y) < 0.5 &&
            abs(size.width - other.size.width) < 0.5 &&
            abs(size.height - other.size.height) < 0.5
    }
}
