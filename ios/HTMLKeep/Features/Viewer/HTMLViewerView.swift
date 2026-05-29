import SwiftUI
import UIKit

private let viewerTopChromeFadeDistance: CGFloat = 72

struct HTMLViewerView: View {
    let page: WebPage
    let entry: WebPageEntry
    var deletedPage: DeletedWebPage? = nil
    let onRenameProject: (WebPage, String) -> Void
    let onDeletePage: () -> Void
    var onRestoreDeletedPage: (() -> Bool)? = nil
    var onPermanentlyDeletePage: (() -> Void)? = nil
    let onRuntimeStorageChanged: () -> Void
    var onActivityChanged: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(WebPageLibrary.self) private var library
    @State private var loadState: ViewerLoadState = .loading
    @State private var reloadToken = UUID()
    @State private var isActionsPopoverPresented = false
    @State private var sharePayload: SharePayload?
    @State private var isPreparingShare = false
    @State private var isSharePreparationOverlayVisible = false
    @State private var sharePreparationID: UUID?
    @State private var shareErrorMessage: String?
    @State private var isRenameAlertPresented = false
    @State private var draftProjectTitle = ""
    @State private var isClearCacheAlertPresented = false
    @State private var isPermanentDeleteAlertPresented = false
    @State private var isRestoreErrorPresented = false
    @State private var clearCacheErrorMessage: String?
    @State private var webViewIdentity = UUID()
    @State private var activeEntryID: WebPageEntry.ID?
    @State private var webContentOffsetY: CGFloat = 0
    @State private var webContentHasTopPinnedOverlay = false

    var body: some View {
        ZStack {
            Color(uiColor: topChromeBackgroundColor)
                .ignoresSafeArea()

            if entryExists {
                WebPageWebView(
                    page: page,
                    entryURL: entryURL,
                    entryHTML: entryHTML,
                    readAccessURL: folderURL,
                    reloadToken: reloadToken,
                    onLoadStateChange: handleLoadStateChange,
                    onRequestDismiss: dismissViewer,
                    onRuntimeStorageChange: onRuntimeStorageChanged,
                    onLocalFileNavigation: handleLocalFileNavigation,
                    onScrollOffsetChange: handleWebScrollOffsetChange,
                    onTopOverlayPreferenceChange: handleTopOverlayPreferenceChange,
                    viewportBackground: viewportBackground
                )
                .id(webViewIdentity)
                .ignoresSafeArea(edges: webViewIgnoredSafeAreaEdges)
            } else {
                missingState
                    .padding(20)
            }

            if case .loading = loadState, entryExists {
                VStack {
                    ProgressView()
                        .padding(12)
                        .background(.thinMaterial, in: Capsule())
                        .padding(.top, 12)
                    Spacer()
                }
            }

            if isPhoneLandscape {
                floatingBackButton
            }

            if isSharePreparationOverlayVisible {
                sharePreparationOverlay
            }
        }
        .navigationTitle(currentProject.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isPhoneLandscape)
        .toolbar(isPhoneLandscape ? .hidden : .visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if entryExists && !isPhoneLandscape && !isRecentlyDeletedViewer {
                    Button {
                        isActionsPopoverPresented = true
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AppStrings.localized("更多操作"))
                    .popover(
                        isPresented: $isActionsPopoverPresented,
                        attachmentAnchor: .rect(.bounds),
                        arrowEdge: .top
                    ) {
                        actionsPopover
                    }
                }
            }
        }
        .background(
            entryDirectoryInstaller
        )
        .background(
            navigationBarChromeInstaller
        )
        .sheet(item: $sharePayload) { payload in
            ActivityShareSheet(activityItems: [payload.url])
        }
        .alert(
            AppStrings.localized("无法准备分享文件"),
            isPresented: shareErrorBinding
        ) {
            Button(AppStrings.localized("知道了"), role: .cancel) {
                shareErrorMessage = nil
            }
        } message: {
            Text(shareErrorMessage ?? "")
        }
        .alert(
            AppStrings.localized("清除缓存数据？"),
            isPresented: $isClearCacheAlertPresented
        ) {
            Button(AppStrings.localized("取消"), role: .cancel) {}
            Button(AppStrings.localized("清除"), role: .destructive) {
                clearRuntimeStorage()
            }
        } message: {
            Text(AppStrings.localized("这会清除当前网页项目保存的进度和缓存数据，不会删除网页文件。"))
        }
        .alert(
            AppStrings.localized("无法清除缓存"),
            isPresented: clearCacheErrorBinding
        ) {
            Button(AppStrings.localized("知道了"), role: .cancel) {
                clearCacheErrorMessage = nil
            }
        } message: {
            Text(clearCacheErrorMessage ?? "")
        }
        .alert(AppStrings.localized("网页文件缺失"), isPresented: $isRestoreErrorPresented) {
            Button(AppStrings.localized("知道了"), role: .cancel) {}
        } message: {
            Text(AppStrings.localized("这个网页的入口文件已经不在本地网页文件夹中。"))
        }
        .alert(
            AppStrings.localized("彻底删除网页？"),
            isPresented: $isPermanentDeleteAlertPresented
        ) {
            Button(AppStrings.localized("取消"), role: .cancel) {}
            Button(AppStrings.localized("彻底删除"), role: .destructive) {
                onPermanentlyDeletePage?()
            }
        } message: {
            Text(AppStrings.localized("这会永久删除这个网页及其本机文件，无法恢复。"))
        }
        .alert(
            AppStrings.localized("重命名项目"),
            isPresented: $isRenameAlertPresented
        ) {
            TextField(AppStrings.localized("项目名称"), text: $draftProjectTitle)
            Button(AppStrings.localized("取消"), role: .cancel) {
                resetRenameState()
            }
            Button(AppStrings.localized("保存")) {
                onRenameProject(currentProject, draftProjectTitle)
                resetRenameState()
            }
            .disabled(normalizedDraftProjectTitle.isEmpty)
        } message: {
            Text(AppStrings.localized("只会修改首页列表中的项目名称，不会更改 HTML 文件或页面标题。"))
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                if case .failed(let message) = loadState {
                    errorBar(message)
                }
                if isRecentlyDeletedViewer {
                    recentlyDeletedActionDock
                }
            }
        }
    }

    private var currentEntry: WebPageEntry {
        let project = currentProject
        if let activeEntryID,
           let activeEntry = project.resolvedEntries.first(where: { $0.id == activeEntryID }) {
            return activeEntry
        }
        if let entry = project.resolvedEntries.first(where: { $0.id == entry.id }) {
            return entry
        }
        return entry
    }

    private var currentProject: WebPage {
        if let deletedPage {
            return deletedPage.page
        }
        return library.page(withID: page.id) ?? page
    }

    private var topChromeBackgroundOpacity: CGFloat {
        guard entryExists, !isPhoneLandscape else { return 0 }
        let rawProgress = min(max(webContentOffsetY / viewerTopChromeFadeDistance, 0), 1)
        let easedProgress = rawProgress * rawProgress * (3 - 2 * rawProgress)
        return 1 - easedProgress
    }

    private var topChromeBackgroundColor: UIColor {
        ViewerCSSColor.uiColor(
            from: currentEntry.safeAreaTopColor,
            preferLastToken: false,
            fallback: .htmlAnywherePageTop
        )
    }

    private var bottomViewportBackgroundColor: UIColor {
        ViewerCSSColor.uiColor(
            from: currentEntry.safeAreaBottomColor,
            preferLastToken: true,
            fallback: topChromeBackgroundColor
        )
    }

    private var viewportBackground: ViewerViewportBackground {
        ViewerViewportBackground(
            topCSS: currentEntry.safeAreaTopColor,
            bottomCSS: currentEntry.safeAreaBottomColor,
            fallbackTopColor: topChromeBackgroundColor,
            fallbackBottomColor: bottomViewportBackgroundColor
        )
    }

    private var navigationBarChromeInstaller: some View {
        ViewerNavigationBarChromeInstaller(
            isActive: !isPhoneLandscape,
            background: viewportBackground,
            backgroundOpacity: topChromeBackgroundOpacity
        )
    }

    private var isRecentlyDeletedViewer: Bool {
        deletedPage != nil
    }

    private var entryDirectoryInstaller: some View {
        ViewerEntryDirectoryInstaller(
            entries: page.resolvedEntries,
            currentEntryID: currentEntry.id,
            isVisible: showsEntryDirectoryButton,
            onSelectEntry: { entry in
                activeEntryID = entry.id
            }
        )
    }

    private var showsEntryDirectoryButton: Bool {
        !isPhoneLandscape && page.resolvedEntries.count > 1
    }

    private var isPhoneLandscape: Bool {
        UIDevice.current.userInterfaceIdiom == .phone && verticalSizeClass == .compact
    }

    private var usesTopSafeAreaWebLayout: Bool {
        webContentHasTopPinnedOverlay && !isPhoneLandscape
    }

    private var webViewIgnoredSafeAreaEdges: Edge.Set {
        usesTopSafeAreaWebLayout ? .bottom : [.top, .bottom]
    }

    private var floatingBackButton: some View {
        VStack {
            HStack {
                Button {
                    dismissViewer()
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(AppTheme.deepWater.opacity(0.62))
                        .frame(width: 44, height: 44)
                        .background {
                            Circle()
                                .fill(AppTheme.surfaceStrong.opacity(0.42))
                        }
                        .overlay {
                            Circle()
                                .stroke(AppTheme.surfaceBorder.opacity(0.34), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppStrings.localized("返回"))

                Spacer()
            }
            .padding(.top, 8)
            .padding(.horizontal, 12)

            Spacer()
        }
    }

    private var actionsPopover: some View {
        VStack(spacing: 0) {
            ViewerActionPopoverRow(
                title: AppStrings.localized("重新加载"),
                systemImage: "arrow.clockwise"
            ) {
                isActionsPopoverPresented = false
                reloadToken = UUID()
            }
            Divider()
                .padding(.leading, 52)

            ViewerActionPopoverRow(
                title: AppStrings.localized("分享"),
                systemImage: "square.and.arrow.up"
            ) {
                isActionsPopoverPresented = false
                startSharingAfterActionsPopoverDismiss()
            }
            Divider()
                .padding(.leading, 52)

            ViewerActionPopoverRow(
                title: AppStrings.localized("重命名"),
                systemImage: "pencil"
            ) {
                isActionsPopoverPresented = false
                startRenamingAfterActionsPopoverDismiss()
            }
            Divider()
                .padding(.leading, 52)

            ViewerActionPopoverRow(
                title: AppStrings.localized("清除缓存"),
                systemImage: "trash",
                role: .destructive
            ) {
                isActionsPopoverPresented = false
                startClearingCacheAfterActionsPopoverDismiss()
            }
        }
        .padding(.vertical)
        .frame(width: min(UIScreen.main.bounds.width - 32, 260))
        .fixedSize(horizontal: false, vertical: true)
        .presentationCompactAdaptation(.popover)
    }

    private func dismissViewer() {
        dismiss()
    }

    private var folderURL: URL {
        if let deletedPage {
            return library.recoverableFolderURL(for: deletedPage)
        }
        return library.folderURL(for: page)
    }

    private var entryURL: URL {
        if currentEntry.source == .bundledArchiveIndex,
           let templateURL = WebPageLibrary.bundledArchiveFallbackTemplateURL() {
            return templateURL
        }
        if let deletedPage {
            return library.entryURL(for: deletedPage, entry: currentEntry)
        }
        return library.entryURL(for: page, entry: currentEntry)
    }

    private var entryHTML: String? {
        currentEntry.source == .bundledArchiveIndex ? WebPageLibrary.bundledArchiveFallbackHTML(for: folderURL) : nil
    }

    private var entryExists: Bool {
        if currentEntry.source == .bundledArchiveIndex {
            return true
        }
        return FileManager.default.fileExists(atPath: entryURL.path)
    }

    private var normalizedDraftProjectTitle: String {
        draftProjectTitle
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private var missingState: some View {
        AppSurfaceCard(isProminent: true) {
            SectionHeader(AppStrings.localized("网页文件缺失"), systemImage: "exclamationmark.triangle")
            Text(AppStrings.localized("这个网页的入口文件已经不在本地网页文件夹中。"))
                .font(.system(size: 15))
                .foregroundStyle(AppTheme.textSecondary)
            if isRecentlyDeletedViewer {
                AppActionButton(AppStrings.localized("彻底删除"), systemImage: "trash", scene: .coral, size: .medium) {
                    isPermanentDeleteAlertPresented = true
                }
            } else {
                AppActionButton(AppStrings.localized("删除记录"), systemImage: "trash", scene: .coral, size: .medium) {
                    onDeletePage()
                }
            }
        }
    }

    private var recentlyDeletedActionDock: some View {
        BottomActionDock {
            HStack(spacing: 12) {
                AppActionButton(AppStrings.localized("恢复"), systemImage: "arrow.uturn.backward", scene: .leaf) {
                    if onRestoreDeletedPage?() == false {
                        isRestoreErrorPresented = true
                    }
                }
                AppActionButton(AppStrings.localized("彻底删除"), systemImage: "trash", scene: .coral) {
                    isPermanentDeleteAlertPresented = true
                }
            }
        }
    }

    private var sharePreparationOverlay: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text(AppStrings.localized("正在准备分享文件..."))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.surfaceBorder.opacity(0.4), lineWidth: 1)
        }
    }

    private var shareErrorBinding: Binding<Bool> {
        Binding {
            shareErrorMessage != nil
        } set: { isPresented in
            if !isPresented {
                shareErrorMessage = nil
            }
        }
    }

    private var clearCacheErrorBinding: Binding<Bool> {
        Binding {
            clearCacheErrorMessage != nil
        } set: { isPresented in
            if !isPresented {
                clearCacheErrorMessage = nil
            }
        }
    }

    private func errorBar(_ message: String) -> some View {
        AppSurfaceCard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppTheme.coral)
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func handleLoadStateChange(_ state: ViewerLoadState) {
        loadState = state
        guard !isRecentlyDeletedViewer else { return }
        switch state {
        case .loaded:
            library.markOpened(page, entry: currentEntry)
            onActivityChanged()
        case .failed:
            library.markFailed(page, entry: currentEntry)
        case .loading:
            break
        }
    }

    private func startRenamingAfterActionsPopoverDismiss() {
        draftProjectTitle = currentProject.title
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isRenameAlertPresented = true
        }
    }

    private func handleLocalFileNavigation(_ url: URL) {
        guard let matchedEntry = matchedEntry(forLocalFileNavigationURL: url) else {
            return
        }
        activeEntryID = matchedEntry.id
    }

    private func matchedEntry(forLocalFileNavigationURL url: URL) -> WebPageEntry? {
        guard let relativePath = Self.relativePath(of: url, in: folderURL) else {
            return nil
        }

        let entries = currentProject.resolvedEntries
        if let exactMatch = entries.first(where: { $0.entryRelativePath == relativePath }) {
            return exactMatch
        }

        return Self.directoryEntryRelativePaths(for: relativePath)
            .compactMap { candidate in
                entries.first { $0.entryRelativePath == candidate }
            }
            .first
    }

    private func handleWebScrollOffsetChange(_ offsetY: CGFloat) {
        guard abs(webContentOffsetY - offsetY) > 0.5 else { return }
        webContentOffsetY = offsetY
    }

    private func handleTopOverlayPreferenceChange(_ prefersTopSafeArea: Bool) {
        guard webContentHasTopPinnedOverlay != prefersTopSafeArea else { return }
        webContentHasTopPinnedOverlay = prefersTopSafeArea
    }

    private func startSharingAfterActionsPopoverDismiss() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            prepareShare()
        }
    }

    private func startClearingCacheAfterActionsPopoverDismiss() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isClearCacheAlertPresented = true
        }
    }

    private func clearRuntimeStorage() {
        Task {
            do {
                try await WebPageRuntimeStorage.clearRuntimeData(
                    for: page,
                    projectFolderURL: folderURL
                )
                onRuntimeStorageChanged()
                webViewIdentity = UUID()
                reloadToken = UUID()
            } catch {
                clearCacheErrorMessage = AppStrings.localized("缓存数据没有清除成功。")
            }
        }
    }

    private func prepareShare() {
        guard !isPreparingShare else { return }

        let projectFolderURL = folderURL
        let projectTitle = page.title
        let preparationID = UUID()
        sharePreparationID = preparationID
        isPreparingShare = true
        isSharePreparationOverlayVisible = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if isPreparingShare, sharePreparationID == preparationID {
                isSharePreparationOverlayVisible = true
            }
        }

        Task {
            do {
                let shareURL = try await Task.detached(priority: .userInitiated) {
                    try WebPageShareExporter().shareURL(
                        forProjectFolder: projectFolderURL,
                        preferredName: projectTitle
                    )
                }.value
                finishPreparingShare()
                sharePayload = SharePayload(url: shareURL)
            } catch {
                finishPreparingShare()
                shareErrorMessage = AppStrings.localized("无法准备分享文件。")
            }
        }
    }

    private func finishPreparingShare() {
        isPreparingShare = false
        isSharePreparationOverlayVisible = false
        sharePreparationID = nil
    }

    private func resetRenameState() {
        isRenameAlertPresented = false
        draftProjectTitle = ""
    }

    private static func relativePath(of fileURL: URL, in folderURL: URL) -> String? {
        let rootPath = folderURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        if filePath == rootPath {
            return ""
        }
        guard filePath.hasPrefix(rootPath + "/") else {
            return nil
        }
        return String(filePath.dropFirst(rootPath.count + 1))
    }

    private static let directoryEntryFileNames = [
        "index.html",
        "index.htm",
        "default.html",
        "default.htm"
    ]

    private static func directoryEntryRelativePaths(for relativePath: String) -> [String] {
        let trimmedPath = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let prefix = trimmedPath.isEmpty ? "" : "\(trimmedPath)/"
        return directoryEntryFileNames.map { "\(prefix)\($0)" }
    }
}

struct SharePayload: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ViewerNavigationBarChromeInstaller: UIViewControllerRepresentable {
    let isActive: Bool
    let background: ViewerViewportBackground
    let backgroundOpacity: CGFloat

    func makeUIViewController(context _: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ uiViewController: Controller, context _: Context) {
        uiViewController.update(
            isActive: isActive,
            background: background,
            backgroundOpacity: backgroundOpacity
        )
    }

    final class Controller: UIViewController {
        private var isActive = false
        private var background = ViewerViewportBackground(
            topCSS: nil,
            bottomCSS: nil,
            fallbackTopColor: .htmlAnywherePageTop,
            fallbackBottomColor: .htmlAnywherePageTop
        )
        private var backgroundOpacity: CGFloat = 1
        private var previousStandardAppearance: UINavigationBarAppearance?
        private var previousScrollEdgeAppearance: UINavigationBarAppearance?
        private var previousCompactAppearance: UINavigationBarAppearance?
        private var previousCompactScrollEdgeAppearance: UINavigationBarAppearance?
        private var previousIsTranslucent: Bool?
        private var previousNavigationControllerBackgroundColor: UIColor?
        private weak var chromeBackgroundView: ViewerViewportBackgroundView?
        private var hasStoredPreviousAppearance = false
        private var hasAppliedTransparentAppearance = false

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            applyAppearance()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            updateChromeBackgroundFrame()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            restorePreviousAppearance()
        }

        func update(isActive: Bool, background: ViewerViewportBackground, backgroundOpacity: CGFloat) {
            self.isActive = isActive
            self.background = background
            self.backgroundOpacity = min(max(backgroundOpacity, 0), 1)

            DispatchQueue.main.async { [weak self] in
                self?.applyAppearance()
            }
        }

        private func applyAppearance() {
            guard let navigationController else {
                return
            }
            let navigationBar = navigationController.navigationBar

            storePreviousAppearanceIfNeeded(for: navigationController)

            guard isActive else {
                restorePreviousAppearance()
                return
            }

            if !hasAppliedTransparentAppearance {
                let appearance = UINavigationBarAppearance()
                appearance.configureWithTransparentBackground()
                appearance.backgroundEffect = nil
                appearance.shadowColor = nil
                appearance.backgroundColor = .clear

                navigationBar.standardAppearance = appearance
                navigationBar.scrollEdgeAppearance = appearance
                navigationBar.compactAppearance = appearance
                navigationBar.compactScrollEdgeAppearance = appearance
                navigationBar.isTranslucent = true
                hasAppliedTransparentAppearance = true
            }

            navigationController.view.backgroundColor = background.fallbackTopColor
            updateChromeBackgroundView(in: navigationController)
        }

        private func storePreviousAppearanceIfNeeded(for navigationController: UINavigationController) {
            guard !hasStoredPreviousAppearance else {
                return
            }

            let navigationBar = navigationController.navigationBar
            previousStandardAppearance = navigationBar.standardAppearance.copy()
            previousScrollEdgeAppearance = navigationBar.scrollEdgeAppearance?.copy()
            previousCompactAppearance = navigationBar.compactAppearance?.copy()
            previousCompactScrollEdgeAppearance = navigationBar.compactScrollEdgeAppearance?.copy()
            previousIsTranslucent = navigationBar.isTranslucent
            previousNavigationControllerBackgroundColor = navigationController.view.backgroundColor
            hasStoredPreviousAppearance = true
        }

        private func restorePreviousAppearance() {
            guard hasStoredPreviousAppearance,
                  let navigationController else {
                return
            }
            let navigationBar = navigationController.navigationBar

            if let previousStandardAppearance {
                navigationBar.standardAppearance = previousStandardAppearance
            }
            navigationBar.scrollEdgeAppearance = previousScrollEdgeAppearance
            navigationBar.compactAppearance = previousCompactAppearance
            navigationBar.compactScrollEdgeAppearance = previousCompactScrollEdgeAppearance
            if let previousIsTranslucent {
                navigationBar.isTranslucent = previousIsTranslucent
            }
            navigationController.view.backgroundColor = previousNavigationControllerBackgroundColor
            chromeBackgroundView?.removeFromSuperview()
            chromeBackgroundView = nil
            hasAppliedTransparentAppearance = false
        }

        private func updateChromeBackgroundView(in navigationController: UINavigationController) {
            let backgroundView = chromeBackgroundView ?? {
                let view = ViewerViewportBackgroundView()
                view.mode = .topSafeArea
                view.isUserInteractionEnabled = false
                navigationController.view.insertSubview(view, belowSubview: navigationController.navigationBar)
                chromeBackgroundView = view
                return view
            }()

            UIView.performWithoutAnimation {
                backgroundView.background = background
                backgroundView.viewportReferenceSize = navigationController.view.bounds.size
                backgroundView.alpha = backgroundOpacity
                updateChromeBackgroundFrame()
            }
        }

        private func updateChromeBackgroundFrame() {
            guard let navigationController,
                  let backgroundView = chromeBackgroundView else {
                return
            }

            let navigationBar = navigationController.navigationBar
            let navigationBarFrame = navigationBar.convert(navigationBar.bounds, to: navigationController.view)
            let backgroundHeight = max(navigationBarFrame.maxY, navigationController.view.safeAreaInsets.top)
            let nextFrame = CGRect(
                x: 0,
                y: 0,
                width: navigationController.view.bounds.width,
                height: backgroundHeight
            )
            if !backgroundView.frame.isApproximatelyEqual(to: nextFrame) {
                backgroundView.frame = nextFrame
            }
            backgroundView.viewportReferenceSize = navigationController.view.bounds.size
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

private enum ViewerCSSColor {
    static func uiColor(from value: String?, preferLastToken: Bool, fallback: UIColor) -> UIColor {
        let tokens = colorTokens(in: value ?? "")
        let preferredToken = preferLastToken ? tokens.last : tokens.first
        guard let preferredToken,
              let color = parseColor(preferredToken) else {
            return fallback
        }
        return color
    }

    private static func colorTokens(in value: String) -> [String] {
        let pattern = "#[0-9A-Fa-f]{3,8}\\b|rgba?\\s*\\([^)]+\\)|\\b(?:black|white)\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return []
        }

        let nsString = value as NSString
        return regex.matches(in: value, options: [], range: NSRange(location: 0, length: nsString.length))
            .compactMap { match in
                guard match.range.location != NSNotFound else { return nil }
                return nsString.substring(with: match.range)
            }
    }

    private static func parseColor(_ value: String) -> UIColor? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.caseInsensitiveCompare("white") == .orderedSame {
            return .white
        }
        if trimmed.caseInsensitiveCompare("black") == .orderedSame {
            return .black
        }
        if trimmed.hasPrefix("#") {
            return colorFromHex(trimmed)
        }
        if trimmed.range(of: "^rgba?\\s*\\(", options: [.regularExpression, .caseInsensitive]) != nil {
            return colorFromRGB(trimmed)
        }
        return nil
    }

    private static func colorFromHex(_ value: String) -> UIColor? {
        let hex = String(value.dropFirst())
        let expanded: String
        switch hex.count {
        case 3, 4:
            expanded = hex.prefix(3).flatMap { [$0, $0] }.map(String.init).joined()
        case 6, 8:
            expanded = String(hex.prefix(6))
        default:
            return nil
        }

        guard let int = UInt32(expanded, radix: 16) else {
            return nil
        }
        return UIColor(htmlAnywhereHex: int)
    }

    private static func colorFromRGB(_ value: String) -> UIColor? {
        guard let open = value.firstIndex(of: "("),
              let close = value.lastIndex(of: ")"),
              open < close else {
            return nil
        }

        let arguments = value[value.index(after: open)..<close]
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard arguments.count >= 3 else {
            return nil
        }

        let red = rgbComponent(arguments[0])
        let green = rgbComponent(arguments[1])
        let blue = rgbComponent(arguments[2])
        return UIColor(red: red, green: green, blue: blue, alpha: 1)
    }

    private static func rgbComponent(_ value: String) -> CGFloat {
        if value.hasSuffix("%") {
            return min(max((Double(value.replacingOccurrences(of: "%", with: "")) ?? 0) / 100, 0), 1)
        }
        return min(max((Double(value) ?? 0) / 255, 0), 1)
    }
}

private extension UIColor {
    convenience init(htmlAnywhereHex hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    static var htmlAnywherePageTop: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(htmlAnywhereHex: 0x0D1118)
                : UIColor(htmlAnywhereHex: 0xDDE7FB)
        }
    }

}

private struct ViewerEntryDirectoryInstaller: UIViewControllerRepresentable {
    let entries: [WebPageEntry]
    let currentEntryID: WebPageEntry.ID
    let isVisible: Bool
    let onSelectEntry: (WebPageEntry) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            entries: entries,
            currentEntryID: currentEntryID,
            onSelectEntry: onSelectEntry
        )
    }

    func makeUIViewController(context: Context) -> ViewerEntryDirectoryViewController {
        ViewerEntryDirectoryViewController(coordinator: context.coordinator)
    }

    func updateUIViewController(_ uiViewController: ViewerEntryDirectoryViewController, context: Context) {
        context.coordinator.entries = entries
        context.coordinator.currentEntryID = currentEntryID
        context.coordinator.onSelectEntry = onSelectEntry
        uiViewController.isVisible = isVisible
        uiViewController.applyDirectoryItem()
    }

    final class Coordinator: NSObject, UIPopoverPresentationControllerDelegate {
        var entries: [WebPageEntry]
        var currentEntryID: WebPageEntry.ID
        var onSelectEntry: (WebPageEntry) -> Void
        var directoryItem: UIBarButtonItem?
        weak var presenter: UIViewController?
        weak var popoverController: UIViewController?

        init(
            entries: [WebPageEntry],
            currentEntryID: WebPageEntry.ID,
            onSelectEntry: @escaping (WebPageEntry) -> Void
        ) {
            self.entries = entries
            self.currentEntryID = currentEntryID
            self.onSelectEntry = onSelectEntry
        }

        @objc func openDirectory() {
            guard let presenter,
                  let directoryItem,
                  entries.count > 1 else {
                return
            }

            popoverController?.dismiss(animated: false)

            let content = ViewerEntryDirectoryPopoverContent(
                entries: entries,
                currentEntryID: currentEntryID,
                onSelectEntry: { [weak self] entry in
                    self?.popoverController?.dismiss(animated: true)
                    self?.onSelectEntry(entry)
                }
            )
            let hostingController = UIHostingController(rootView: content)
            hostingController.modalPresentationStyle = .popover
            hostingController.preferredContentSize = CGSize(
                width: min(UIScreen.main.bounds.width - 32, 320),
                height: min(CGFloat(entries.count) * 59 + 16, 420)
            )

            guard let popover = hostingController.popoverPresentationController else {
                return
            }
            popover.delegate = self
            popover.permittedArrowDirections = .any
            if #available(iOS 16.0, *) {
                popover.sourceItem = directoryItem
            } else {
                popover.sourceView = presenter.view
                popover.sourceRect = CGRect(
                    x: presenter.view.bounds.minX + 44,
                    y: presenter.view.safeAreaInsets.top,
                    width: 1,
                    height: 1
                )
            }

            popoverController = hostingController
            presenter.present(hostingController, animated: true)
        }

        func adaptivePresentationStyle(
            for controller: UIPresentationController,
            traitCollection: UITraitCollection
        ) -> UIModalPresentationStyle {
            .none
        }
    }
}

private final class ViewerEntryDirectoryViewController: UIViewController {
    weak var coordinator: ViewerEntryDirectoryInstaller.Coordinator?
    var isVisible = false

    init(coordinator: ViewerEntryDirectoryInstaller.Coordinator) {
        self.coordinator = coordinator
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyDirectoryItem()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        removeDirectoryItem()
    }

    func applyDirectoryItem() {
        guard let navigationController,
              let coordinator,
              let viewerViewController = owningNavigationStackViewController(in: navigationController),
              navigationController.topViewController === viewerViewController,
              isVisible else {
            removeDirectoryItem()
            return
        }

        let directoryItem: UIBarButtonItem
        if let existingItem = coordinator.directoryItem {
            directoryItem = existingItem
        } else {
            directoryItem = UIBarButtonItem(
                image: UIImage(systemName: "list.bullet"),
                style: .plain,
                target: coordinator,
                action: #selector(ViewerEntryDirectoryInstaller.Coordinator.openDirectory)
            )
            coordinator.directoryItem = directoryItem
        }
        directoryItem.accessibilityLabel = AppStrings.localized("页面目录")
        coordinator.presenter = viewerViewController

        let navigationItem = viewerViewController.navigationItem
        navigationItem.leftItemsSupplementBackButton = true
        if navigationItem.leftBarButtonItems?.contains(where: { $0 === directoryItem }) != true {
            navigationItem.leftBarButtonItems = [directoryItem]
        }
    }

    private func removeDirectoryItem() {
        guard let directoryItem = coordinator?.directoryItem,
              let navigationController else {
            return
        }

        let navigationItem = navigationController.topViewController?.navigationItem
        navigationItem?.leftBarButtonItems = navigationItem?.leftBarButtonItems?.filter { $0 !== directoryItem }
        if navigationItem?.leftBarButtonItems?.isEmpty == true {
            navigationItem?.leftBarButtonItems = nil
            navigationItem?.leftItemsSupplementBackButton = false
        }
    }

    private func owningNavigationStackViewController(in navigationController: UINavigationController) -> UIViewController? {
        var current: UIViewController? = self
        while let parent = current?.parent, parent !== navigationController {
            current = parent
        }
        return current
    }
}

private struct ViewerEntryDirectoryPopoverContent: View {
    let entries: [WebPageEntry]
    let currentEntryID: WebPageEntry.ID
    let onSelectEntry: (WebPageEntry) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(entries) { entry in
                    entryRow(entry)
                }
            }
            .padding(.vertical, 8)
        }
        .frame(
            width: min(UIScreen.main.bounds.width - 32, 320),
            height: min(CGFloat(entries.count) * 59 + 16, 420)
        )
    }

    private func entryRow(_ entry: WebPageEntry) -> some View {
        Button {
            onSelectEntry(entry)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(AppTheme.listItemTitle)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(entry.entryFileName)
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .layoutPriority(1)

                Spacer(minLength: 12)

                if entry.lastLoadStatus != .ready {
                    Text(entry.lastLoadStatus.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.trailing)
                } else if entry.id == currentEntryID {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.deepWater)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: entry))
    }

    private func statusText(for entry: WebPageEntry) -> String? {
        if entry.lastLoadStatus != .ready {
            return entry.lastLoadStatus.title
        }
        if entry.id == currentEntryID {
            return AppStrings.localized("当前页面")
        }
        return nil
    }

    private func accessibilityLabel(for entry: WebPageEntry) -> String {
        var parts = [entry.title, entry.entryFileName]
        if let status = statusText(for: entry) {
            parts.append(status)
        }
        return parts.joined(separator: "，")
    }
}

struct WebPageShareExporter {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func shareURL(forProjectFolder folderURL: URL, preferredName: String) throws -> URL {
        let writer = ZipArchiveWriter(fileManager: fileManager)
        let filePaths = try writer.regularFileRelativePaths(
            in: folderURL,
            excluding: WebPageRuntimeStorage.isRuntimeStoragePath
        )
        let htmlPaths = filePaths.filter(Self.isHTMLPath)

        if filePaths.count == 1, htmlPaths.count == 1 {
            return folderURL.appendingPathComponent(filePaths[0], isDirectory: false)
        }

        let exportFolderURL = fileManager.temporaryDirectory
            .appendingPathComponent("HTMLKeepShareExports", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let archiveURL = exportFolderURL.appendingPathComponent(
            "\(Self.safeFileName(from: preferredName)).zip",
            isDirectory: false
        )
        try writer.archiveFolder(
            at: folderURL,
            to: archiveURL,
            excluding: WebPageRuntimeStorage.isRuntimeStoragePath
        )
        return archiveURL
    }

    private static func isHTMLPath(_ path: String) -> Bool {
        let fileExtension = URL(fileURLWithPath: path).pathExtension.lowercased()
        return fileExtension == "html" || fileExtension == "htm"
    }

    private static func safeFileName(from title: String) -> String {
        let trimmed = title
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let fallback = AppStrings.localized("网页")
        let baseName = trimmed.isEmpty ? fallback : trimmed
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
            .union(.newlines)
            .union(.controlCharacters)
        let sanitized = baseName
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? fallback : sanitized
    }
}

struct ViewerActionPopoverRow: View {
    let title: String
    let systemImage: String
    var role: ButtonRole? = nil
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 24)

                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(role == .destructive ? Color(uiColor: .systemRed) : Color.primary)
        .accessibilityLabel(title)
    }
}

struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context _: Context) {}
}

enum ViewerLoadState: Equatable {
    case loading
    case loaded
    case failed(String)
}
