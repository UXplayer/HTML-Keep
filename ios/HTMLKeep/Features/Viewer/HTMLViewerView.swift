import CryptoKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

private let viewerTopChromeFadeDistance: CGFloat = 72
private let viewerLoadingIndicatorDelay: TimeInterval = 0.35

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
    @State private var loadState: ViewerLoadState = .loaded
    @State private var isLoadingIndicatorVisible = false
    @State private var loadingIndicatorID: UUID?
    @State private var reloadToken = UUID()
    @State private var webPageZoomIndex = ViewerZoomScale.defaultIndex
    @State private var isActionsPopoverPresented = false
    @State private var pendingActionsPopoverAction: HTMLViewerActionsPopoverAction?
    @State private var presentedViewerSheet: ViewerPresentedSheet?
    @State private var sharePayload: SharePayload?
    @State private var isHubShareCodeSheetPresented = false
    @State private var hubShareCache: WebPageHubShareCache.ValidShare?
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
                    pageZoom: ViewerZoomScale.pageZoom(for: webPageZoomIndex),
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

            if isLoadingIndicatorVisible, entryExists {
                loadingIndicatorOverlay
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
                            .onDisappear {
                                performPendingActionsPopoverAction()
                            }
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
        .sheet(isPresented: $isHubShareCodeSheetPresented) {
            HubShareCodeSheet(
                projectTitle: page.title,
                projectFolderURL: folderURL,
                cachedShare: hubShareCache,
                onCacheChanged: { hubShareCache = $0 }
            ) {
                let projectFolderURL = folderURL
                let projectTitle = page.title
                return try await Task.detached(priority: .userInitiated) {
                    try WebPageShareExporter().shareURL(
                        forProjectFolder: projectFolderURL,
                        preferredName: projectTitle
                    )
                }.value
            }
        }
        .sheet(item: $presentedViewerSheet) { sheet in
            switch sheet {
            case .zoom:
                ViewerZoomSheet(zoomIndex: $webPageZoomIndex)
            }
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
        .task(id: page.id) {
            await refreshHubShareCache()
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

    private var loadingIndicatorOverlay: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .allowsHitTesting(false)
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
                title: AppStrings.localized("缩放"),
                systemImage: "plus.magnifyingglass"
            ) {
                dismissActionsPopover(then: .zoom)
            }
            Divider()
                .padding(.leading, 52)

            ViewerActionPopoverRow(
                title: AppStrings.localized("分享"),
                systemImage: "square.and.arrow.up"
            ) {
                dismissActionsPopover(then: .share)
            }
            Divider()
                .padding(.leading, 52)

            ViewerActionPopoverRow(
                title: AppStrings.localized(hubShareCache == nil ? "生成暗号" : "查看暗号"),
                systemImage: "key.fill"
            ) {
                dismissActionsPopover(then: .hubCode)
            }
            Divider()
                .padding(.leading, 52)

            ViewerActionPopoverRow(
                title: AppStrings.localized("重命名"),
                systemImage: "pencil"
            ) {
                dismissActionsPopover(then: .rename)
            }
            Divider()
                .padding(.leading, 52)

            ViewerActionPopoverRow(
                title: AppStrings.localized("清除缓存"),
                systemImage: "trash",
                role: .destructive
            ) {
                dismissActionsPopover(then: .clearCache)
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
        updateLoadingIndicator(for: state)
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

    private func updateLoadingIndicator(for state: ViewerLoadState) {
        switch state {
        case .loading:
            let id = UUID()
            loadingIndicatorID = id
            isLoadingIndicatorVisible = false
            DispatchQueue.main.asyncAfter(deadline: .now() + viewerLoadingIndicatorDelay) {
                guard loadingIndicatorID == id else { return }
                isLoadingIndicatorVisible = true
            }
        case .loaded, .failed:
            loadingIndicatorID = nil
            isLoadingIndicatorVisible = false
        }
    }

    private func dismissActionsPopover(then action: HTMLViewerActionsPopoverAction) {
        pendingActionsPopoverAction = action
        isActionsPopoverPresented = false
    }

    private func performPendingActionsPopoverAction() {
        guard let action = pendingActionsPopoverAction else { return }
        pendingActionsPopoverAction = nil
        DispatchQueue.main.async {
            switch action {
            case .rename:
                startRenamingAfterActionsPopoverDismiss()
            case .share:
                startSharingAfterActionsPopoverDismiss()
            case .hubCode:
                startGeneratingHubCodeAfterActionsPopoverDismiss()
            case .zoom:
                startShowingZoomSheetAfterActionsPopoverDismiss()
            case .clearCache:
                startClearingCacheAfterActionsPopoverDismiss()
            }
        }
    }

    private func startRenamingAfterActionsPopoverDismiss() {
        draftProjectTitle = currentProject.title
        isRenameAlertPresented = true
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
        prepareShare()
    }

    private func startGeneratingHubCodeAfterActionsPopoverDismiss() {
        isHubShareCodeSheetPresented = true
    }

    private func startShowingZoomSheetAfterActionsPopoverDismiss() {
        presentedViewerSheet = .zoom
    }

    private func refreshHubShareCache() async {
        let projectFolderURL = folderURL
        let validShare = await Task.detached(priority: .utility) {
            WebPageHubShareCache.validShare(in: projectFolderURL)
        }.value
        guard !Task.isCancelled else { return }
        hubShareCache = validShare
    }

    private func startClearingCacheAfterActionsPopoverDismiss() {
        isClearCacheAlertPresented = true
    }

    private func clearRuntimeStorage() {
        Task {
            do {
                try await WebPageRuntimeStorage.clearRuntimeData(
                    for: page,
                    projectFolderURL: folderURL
                )
                onRuntimeStorageChanged()
                hubShareCache = nil
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

private enum ViewerPresentedSheet: Identifiable {
    case zoom

    var id: String {
        switch self {
        case .zoom:
            return "zoom"
        }
    }
}

private enum HTMLViewerActionsPopoverAction {
    case rename
    case share
    case hubCode
    case zoom
    case clearCache
}

private enum ViewerZoomScale {
    static let percentages = [
        25, 33, 50, 67, 75, 80, 90, 100, 110, 125, 150, 175, 200, 250, 300
    ]
    static let defaultPercentage = 100
    static let defaultIndex = percentages.firstIndex(of: defaultPercentage) ?? 7
    static var maximumIndex: Int { percentages.count - 1 }

    static func clampedIndex(_ index: Int) -> Int {
        min(max(index, 0), maximumIndex)
    }

    static func percentage(for index: Int) -> Int {
        percentages[clampedIndex(index)]
    }

    static func pageZoom(for index: Int) -> CGFloat {
        CGFloat(percentage(for: index)) / 100
    }

    static func accessibilityValue(for index: Int) -> String {
        "\(percentage(for: index))%"
    }
}

private struct ViewerZoomSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var measuredContentHeight: CGFloat = 92
    @Binding var zoomIndex: Int

    private let sheetChromeAllowance: CGFloat = 64
    private let minimumSheetHeight: CGFloat = 168

    private var sliderValue: Binding<Double> {
        Binding {
            Double(zoomIndex)
        } set: { newValue in
            zoomIndex = ViewerZoomScale.clampedIndex(Int(newValue.rounded()))
        }
    }

    private var canReset: Bool {
        zoomIndex != ViewerZoomScale.defaultIndex
    }

    private var canDecrease: Bool {
        zoomIndex > 0
    }

    private var canIncrease: Bool {
        zoomIndex < ViewerZoomScale.maximumIndex
    }

    private var sheetHeight: CGFloat {
        max(minimumSheetHeight, measuredContentHeight + sheetChromeAllowance)
    }

    private var systemDefaultTextColor: Color {
        Color(uiColor: .label)
    }

    var body: some View {
        NavigationStack {
            zoomControl
            .navigationTitle(AppStrings.localized("缩放"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    resetButton
                }
                ToolbarItem(placement: .confirmationAction) {
                    closeButton
                }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.visible)
    }

    private var zoomControl: some View {
        HStack(spacing: 16) {
            Button {
                decrease()
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .disabled(!canDecrease)
            .buttonStyle(.plain)
            .foregroundStyle(systemDefaultTextColor)
            .accessibilityLabel(AppStrings.localized("缩小"))

            zoomSlider

            Button {
                increase()
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .disabled(!canIncrease)
            .buttonStyle(.plain)
            .foregroundStyle(systemDefaultTextColor)
            .accessibilityLabel(AppStrings.localized("放大"))
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 24)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ViewerZoomControlHeightKey.self,
                    value: proxy.size.height
                )
            }
        )
        .onPreferenceChange(ViewerZoomControlHeightKey.self) { contentHeight in
            updateMeasuredContentHeight(contentHeight)
        }
    }

    @ViewBuilder
    private var zoomSlider: some View {
        if #available(iOS 26.0, *) {
            ViewerZoomTickedSlider(
                zoomIndex: $zoomIndex,
                tintColor: .label
            )
            .accessibilityLabel(AppStrings.localized("缩放"))
            .accessibilityValue(ViewerZoomScale.accessibilityValue(for: zoomIndex))
        } else {
            Slider(
                value: sliderValue,
                in: 0...Double(ViewerZoomScale.maximumIndex),
                step: 1
            )
            .tint(systemDefaultTextColor)
            .accessibilityLabel(AppStrings.localized("缩放"))
            .accessibilityValue(ViewerZoomScale.accessibilityValue(for: zoomIndex))
        }
    }

    private var resetButton: some View {
        Button(AppStrings.localized("重置")) {
            reset()
        }
        .disabled(!canReset)
        .foregroundStyle(systemDefaultTextColor)
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
        }
        .foregroundStyle(systemDefaultTextColor)
        .accessibilityLabel(AppStrings.localized("关闭"))
    }

    private func decrease() {
        zoomIndex = ViewerZoomScale.clampedIndex(zoomIndex - 1)
    }

    private func increase() {
        zoomIndex = ViewerZoomScale.clampedIndex(zoomIndex + 1)
    }

    private func reset() {
        zoomIndex = ViewerZoomScale.defaultIndex
    }

    private func updateMeasuredContentHeight(_ contentHeight: CGFloat) {
        guard contentHeight > 0 else { return }
        guard abs(measuredContentHeight - contentHeight) > 1 else { return }
        measuredContentHeight = contentHeight
    }
}

private struct ViewerZoomControlHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

@available(iOS 26.0, *)
private struct ViewerZoomTickedSlider: UIViewRepresentable {
    @Binding var zoomIndex: Int
    let tintColor: UIColor

    func makeUIView(context: Context) -> UISlider {
        let slider = UISlider(frame: .zero)
        slider.minimumValue = 0
        slider.maximumValue = Float(ViewerZoomScale.maximumIndex)
        slider.isContinuous = true
        slider.addTarget(
            context.coordinator,
            action: #selector(Coordinator.valueChanged(_:)),
            for: .valueChanged
        )
        return slider
    }

    func updateUIView(_ slider: UISlider, context: Context) {
        context.coordinator.parent = self
        slider.minimumValue = 0
        slider.maximumValue = Float(ViewerZoomScale.maximumIndex)
        slider.tintColor = tintColor
        slider.minimumTrackTintColor = tintColor
        slider.thumbTintColor = tintColor
        slider.trackConfiguration = UISlider.TrackConfiguration(
            allowsTickValuesOnly: false,
            neutralValue: 0,
            enabledRange: 0...1,
            ticks: [
                UISlider.TrackConfiguration.Tick(
                    position: normalizedDefaultTickPosition
                )
            ]
        )

        let value = Float(ViewerZoomScale.clampedIndex(zoomIndex))
        guard abs(slider.value - value) > 0.001 else { return }
        slider.setValue(value, animated: false)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    private var normalizedDefaultTickPosition: Float {
        let maximumIndex = Float(ViewerZoomScale.maximumIndex)
        guard maximumIndex > 0 else { return 0 }
        return Float(ViewerZoomScale.defaultIndex) / maximumIndex
    }

    final class Coordinator: NSObject {
        var parent: ViewerZoomTickedSlider

        init(parent: ViewerZoomTickedSlider) {
            self.parent = parent
        }

        @objc func valueChanged(_ slider: UISlider) {
            let index = ViewerZoomScale.clampedIndex(Int(slider.value.rounded()))
            parent.zoomIndex = index
            slider.setValue(Float(index), animated: false)
        }
    }
}

struct SharePayload: Identifiable {
    let id = UUID()
    let url: URL
}

enum WebPageHubShareCache {
    struct ValidShare: Equatable, Sendable {
        let result: HubShareUploadResult
        let projectFingerprint: String
    }

    private struct Snapshot: Codable, Equatable {
        let schemaVersion: Int
        let savedAt: Date
        let projectFingerprint: String
        let result: HubShareUploadResult
    }

    static func validShare(
        in projectFolderURL: URL,
        fileManager: FileManager = .default,
        now: Date = .now
    ) -> ValidShare? {
        let url = cacheURL(in: projectFolderURL)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? decoder.decode(Snapshot.self, from: data),
              snapshot.schemaVersion == 1 else {
            try? fileManager.removeItem(at: url)
            return nil
        }
        guard !snapshot.result.isExpired(now: now) else {
            try? fileManager.removeItem(at: url)
            return nil
        }
        guard let currentFingerprint = try? projectFingerprint(in: projectFolderURL, fileManager: fileManager) else {
            return nil
        }
        guard currentFingerprint == snapshot.projectFingerprint else {
            try? fileManager.removeItem(at: url)
            return nil
        }
        return ValidShare(result: snapshot.result, projectFingerprint: snapshot.projectFingerprint)
    }

    static func save(
        result: HubShareUploadResult,
        projectFingerprint: String,
        in projectFolderURL: URL,
        fileManager: FileManager = .default
    ) throws -> ValidShare {
        try fileManager.createDirectory(
            at: runtimeDirectoryURL(in: projectFolderURL),
            withIntermediateDirectories: true
        )
        let snapshot = Snapshot(
            schemaVersion: 1,
            savedAt: .now,
            projectFingerprint: projectFingerprint,
            result: result
        )
        let data = try encoder.encode(snapshot)
        try data.write(to: cacheURL(in: projectFolderURL), options: [.atomic])
        return ValidShare(result: result, projectFingerprint: projectFingerprint)
    }

    static func projectFingerprint(
        in projectFolderURL: URL,
        fileManager: FileManager = .default
    ) throws -> String {
        let relativePaths = try ZipArchiveWriter(fileManager: fileManager).regularFileRelativePaths(
            in: projectFolderURL,
            excluding: WebPageLibrary.isAppManagedProjectFilePath
        )
        guard !relativePaths.isEmpty else {
            throw ZipArchiveWriterError.emptyFolder
        }

        var hasher = SHA256()
        for relativePath in relativePaths {
            let fileURL = projectFolderURL.appendingPathComponent(relativePath, isDirectory: false)
            let fileData = try Data(contentsOf: fileURL)
            hasher.update(data: Data("path:\(relativePath)\n".utf8))
            hasher.update(data: Data("bytes:\(fileData.count)\n".utf8))
            hasher.update(data: fileData)
            hasher.update(data: Data([0]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func runtimeDirectoryURL(in projectFolderURL: URL) -> URL {
        projectFolderURL.appendingPathComponent(WebPageRuntimeStorage.directoryName, isDirectory: true)
    }

    private static func cacheURL(in projectFolderURL: URL) -> URL {
        runtimeDirectoryURL(in: projectFolderURL)
            .appendingPathComponent("hub-share.json", isDirectory: false)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

struct HubShareCodeSheet: View {
    @Environment(\.dismiss) private var dismiss

    let projectTitle: String
    let projectFolderURL: URL
    let onCacheChanged: (WebPageHubShareCache.ValidShare?) -> Void
    let prepareShareURL: () async throws -> URL

    @State private var phase: HubShareCodePhase
    @State private var uploadTask: Task<Void, Never>?
    @State private var isCopied = false

    init(
        projectTitle: String,
        projectFolderURL: URL,
        cachedShare: WebPageHubShareCache.ValidShare?,
        onCacheChanged: @escaping (WebPageHubShareCache.ValidShare?) -> Void,
        prepareShareURL: @escaping () async throws -> URL
    ) {
        self.projectTitle = projectTitle
        self.projectFolderURL = projectFolderURL
        self.onCacheChanged = onCacheChanged
        self.prepareShareURL = prepareShareURL
        _phase = State(initialValue: cachedShare.map { .completed($0.result) } ?? .confirm)
    }

    private var sheetHeight: CGFloat {
        switch phase {
        case .confirm:
            return 448
        case .uploading:
            return 300
        case .completed:
            return 472
        case .failed:
            return 352
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .navigationTitle(AppStrings.localized(phase.isCompleted ? "查看暗号" : "生成暗号"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .disabled(phase.isWorking)
                    .accessibilityLabel(AppStrings.localized("关闭"))
                }
            }
        }
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(phase.isWorking)
        .onDisappear {
            uploadTask?.cancel()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .confirm:
            confirmContent
        case let .uploading(progress):
            uploadingContent(progress: progress)
        case let .completed(result):
            completedContent(result: result)
        case let .failed(message):
            failedContent(message: message)
        }
    }

    private var confirmContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            HubShareCodeHeroIcon(systemImage: "key.fill")

            VStack(alignment: .leading, spacing: 8) {
                Text(AppStrings.localized("生成分享暗号"))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.contentPrimary)

                Text(AppStrings.localized("上传后这份文件会公开，任何拿到暗号或链接的人都可以下载。"))
                    .font(.system(size: 15))
                    .lineSpacing(3)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                HubShareCodeInfoRow(
                    systemImage: "calendar.badge.clock",
                    text: AppStrings.localized("默认保留 30 天，过期后 Hub 会自动清理。")
                )
                HubShareCodeInfoRow(
                    systemImage: "doc.on.doc",
                    text: AppStrings.localized("同一份文件重复生成时，会直接复用已有暗号。")
                )
            }

            HubShareCodePrimaryButton(
                title: AppStrings.localized("确认生成"),
                systemImage: "arrow.up.circle.fill",
                action: startUpload
            )
        }
    }

    private func uploadingContent(progress: Double?) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HubShareCodeHeroIcon(systemImage: "arrow.up.circle.fill")

            VStack(alignment: .leading, spacing: 10) {
                if let progress {
                    ProgressView(value: progress, total: 1)
                        .tint(AppTheme.deepWater)
                    Text(String(format: AppStrings.localized("正在上传 %d%%"), Int((progress * 100).rounded())))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppTheme.contentPrimary)
                } else {
                    ProgressView()
                        .tint(AppTheme.deepWater)
                    Text(AppStrings.localized("正在准备上传..."))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppTheme.contentPrimary)
                }

                Text(AppStrings.localized("请保持 HTML Keep 在前台，上传完成后会显示暗号。"))
                    .font(.system(size: 15))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }

    private func completedContent(result: HubShareUploadResult) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HubShareCodeHeroIcon(systemImage: "checkmark.circle.fill")

            VStack(alignment: .leading, spacing: 8) {
                Text(AppStrings.localized("暗号已生成"))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.contentPrimary)

                Text(AppStrings.localized("这个暗号默认保留 30 天。"))
                    .font(.system(size: 15))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Text(result.code)
                .font(.system(size: 46, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppTheme.deepWater)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 14)
                .background(AppTheme.surfaceInset, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppTheme.surfaceBorder, lineWidth: 1)
                }
                .accessibilityLabel(AppStrings.localized("暗号已生成"))
                .accessibilityValue(result.code)

            Text(result.detailText)
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.textSecondary)

            HubShareCodePrimaryButton(
                title: isCopied ? AppStrings.localized("已复制") : AppStrings.localized("复制分享文案"),
                systemImage: isCopied ? "checkmark" : "doc.on.doc",
                action: {
                    UIPasteboard.general.string = result.copyText(projectTitle: projectTitle)
                    isCopied = true
                }
            )

            Button(AppStrings.localized("完成")) {
                dismiss()
            }
            .font(.system(size: 16, weight: .semibold))
            .frame(maxWidth: .infinity)
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.contentPrimary)
        }
    }

    private func failedContent(message: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HubShareCodeHeroIcon(systemImage: "exclamationmark.triangle.fill", isWarning: true)

            VStack(alignment: .leading, spacing: 8) {
                Text(AppStrings.localized("生成失败"))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.contentPrimary)

                Text(message)
                    .font(.system(size: 15))
                    .lineSpacing(3)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            HubShareCodePrimaryButton(
                title: AppStrings.localized("重新生成"),
                systemImage: "arrow.clockwise",
                action: startUpload
            )
        }
    }

    private func startUpload() {
        guard !phase.isWorking else { return }

        isCopied = false
        uploadTask?.cancel()
        uploadTask = Task {
            await runUpload()
        }
    }

    @MainActor
    private func runUpload() async {
        withAnimation(.snappy(duration: 0.2)) {
            phase = .uploading(nil)
        }

        do {
            let projectFolderURL = projectFolderURL
            let projectFingerprint = try await Task.detached(priority: .utility) {
                try WebPageHubShareCache.projectFingerprint(in: projectFolderURL)
            }.value
            let shareURL = try await prepareShareURL()
            defer {
                WebPageShareExporter().cleanupTemporaryExportIfNeeded(at: shareURL)
            }

            let result = try await HubShareCodeUploader().upload(
                fileURL: shareURL,
                retentionPolicy: "30d",
                progress: { progress in
                    Task { @MainActor in
                        guard case .uploading = phase else { return }
                        withAnimation(.linear(duration: 0.12)) {
                            phase = .uploading(progress)
                        }
                    }
                }
            )

            let cachedShare = try? WebPageHubShareCache.save(
                result: result,
                projectFingerprint: projectFingerprint,
                in: projectFolderURL
            )
            if let cachedShare {
                onCacheChanged(cachedShare)
            }
            withAnimation(.snappy(duration: 0.2)) {
                phase = .completed(result)
            }
        } catch is CancellationError {
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? AppStrings.localized("暂时无法生成暗号，请稍后再试。")
            withAnimation(.snappy(duration: 0.2)) {
                phase = .failed(message)
            }
        }
    }
}

private enum HubShareCodePhase: Equatable {
    case confirm
    case uploading(Double?)
    case completed(HubShareUploadResult)
    case failed(String)

    var isWorking: Bool {
        if case .uploading = self {
            return true
        }
        return false
    }

    var isCompleted: Bool {
        if case .completed = self {
            return true
        }
        return false
    }
}

private struct HubShareCodeHeroIcon: View {
    let systemImage: String
    var isWarning = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 24, weight: .bold))
            .foregroundStyle(isWarning ? AppTheme.coral : AppTheme.deepWater)
            .frame(width: 54, height: 54)
            .background(AppTheme.surfaceInset, in: Circle())
            .overlay {
                Circle()
                    .stroke(AppTheme.surfaceBorder, lineWidth: 1)
            }
    }
}

private struct HubShareCodeInfoRow: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.deepWater)
                .frame(width: 20)

            Text(text)
                .font(.system(size: 14))
                .lineSpacing(2)
                .foregroundStyle(AppTheme.contentPrimary)
        }
    }
}

private struct HubShareCodePrimaryButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .bold))
                Text(title)
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(AppTheme.deepWater, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct HubShareUploadResult: Codable, Equatable, Sendable {
    let code: String
    let url: URL
    let fileName: String
    let byteSize: Int64
    let expiresAt: String?
    let deduplicated: Bool

    var detailText: String {
        let expiryText: String
        if let expiresAt,
           let date = ISO8601DateFormatter.htmlKeepHubDate(from: expiresAt) {
            expiryText = DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
        } else {
            expiryText = AppStrings.localized("永久保存")
        }

        return "\(fileName) · \(Self.formatBytes(byteSize)) · \(expiryText)"
    }

    func isExpired(now: Date = .now) -> Bool {
        guard let expiresAt else {
            return false
        }
        guard let expiryDate = ISO8601DateFormatter.htmlKeepHubDate(from: expiresAt) else {
            return true
        }
        return expiryDate <= now
    }

    func copyText(projectTitle: String) -> String {
        let title = projectTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeTitle = title.isEmpty ? AppStrings.localized("网页") : title
        return [
            String(format: AppStrings.localized("我用 HTML Keep 分享了一个网页作品：%@"), safeTitle),
            String(format: AppStrings.localized("打开 HTML Keep，点击首页底部右侧的「输入暗号」按钮，输入暗号：%@"), code),
            String(format: AppStrings.localized("分享链接：%@"), url.absoluteString),
            AppStrings.localized("这个暗号默认保留 30 天，过期后会自动清理。")
        ].joined(separator: "\n")
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        if bytes >= 1_000_000 {
            return String(format: "%.1f MB", Double(bytes) / 1_000_000)
        }

        if bytes >= 1_000 {
            return String(format: "%.1f KB", Double(bytes) / 1_000)
        }

        return "\(bytes) bytes"
    }
}

private final class HubShareCodeUploader {
    private static let uploadURL = URL(string: "https://hub.htmlkeep.com/api/upload")!
    private static let maxUploadBytes: Int64 = 25_000_000

    func upload(
        fileURL: URL,
        retentionPolicy: String,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> HubShareUploadResult {
        let fileSize = try Self.fileSize(at: fileURL)
        guard fileSize <= Self.maxUploadBytes else {
            throw HubShareCodeUploadError.fileTooLarge(Self.formatBytes(Self.maxUploadBytes))
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        let body = try Self.multipartBody(
            fileURL: fileURL,
            fileName: fileURL.lastPathComponent,
            contentType: Self.contentType(for: fileURL),
            retentionPolicy: retentionPolicy,
            boundary: boundary
        )
        var request = URLRequest(url: Self.uploadURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let delegate = HubShareCodeUploadProgressDelegate(progress: progress)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer {
            session.invalidateAndCancel()
        }

        let (data, response) = try await session.upload(for: request, from: body)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HubShareCodeUploadError.invalidResponse
        }

        let decoder = JSONDecoder()
        guard (200...299).contains(httpResponse.statusCode) else {
            let serverError = try? decoder.decode(HubShareCodeServerError.self, from: data)
            throw HubShareCodeUploadError.server(serverError?.message ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))
        }

        do {
            return try decoder.decode(HubShareUploadResult.self, from: data)
        } catch {
            throw HubShareCodeUploadError.invalidResponse
        }
    }

    private static func multipartBody(
        fileURL: URL,
        fileName: String,
        contentType: String,
        retentionPolicy: String,
        boundary: String
    ) throws -> Data {
        var body = Data()
        body.appendMultipartField(name: "retention", value: retentionPolicy, boundary: boundary)
        body.appendMultipartFile(
            name: "file",
            fileName: fileName,
            contentType: contentType,
            data: try Data(contentsOf: fileURL),
            boundary: boundary
        )
        body.appendUTF8("--\(boundary)--\r\n")
        return body
    }

    private static func fileSize(at fileURL: URL) throws -> Int64 {
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }

    private static func contentType(for fileURL: URL) -> String {
        if let mimeType = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType {
            return mimeType
        }

        return "application/octet-stream"
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        if bytes >= 1_000_000 {
            return String(format: "%.0f MB", Double(bytes) / 1_000_000)
        }

        if bytes >= 1_000 {
            return String(format: "%.0f KB", Double(bytes) / 1_000)
        }

        return "\(bytes) bytes"
    }
}

private final class HubShareCodeUploadProgressDelegate: NSObject, URLSessionTaskDelegate {
    private let progress: @Sendable (Double) -> Void

    init(progress: @escaping @Sendable (Double) -> Void) {
        self.progress = progress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        let value = min(max(Double(totalBytesSent) / Double(totalBytesExpectedToSend), 0), 1)
        progress(value)
    }
}

private struct HubShareCodeServerError: Decodable {
    let message: String?
}

private enum HubShareCodeUploadError: LocalizedError {
    case fileTooLarge(String)
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case let .fileTooLarge(limit):
            return String(
                format: AppStrings.localized("这个文件超过 Hub 当前 %@ 的上传限制。"),
                limit
            )
        case .invalidResponse:
            return AppStrings.localized("Hub 返回了无法识别的响应。")
        case let .server(message):
            return String(
                format: AppStrings.localized("无法上传这个文件。%@"),
                message
            )
        }
    }
}

private extension Data {
    mutating func appendMultipartField(name: String, value: String, boundary: String) {
        appendUTF8("--\(boundary)\r\n")
        appendUTF8("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        appendUTF8("\(value)\r\n")
    }

    mutating func appendMultipartFile(
        name: String,
        fileName: String,
        contentType: String,
        data: Data,
        boundary: String
    ) {
        let escapedFileName = fileName.replacingOccurrences(of: "\"", with: "'")
        appendUTF8("--\(boundary)\r\n")
        appendUTF8("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(escapedFileName)\"\r\n")
        appendUTF8("Content-Type: \(contentType)\r\n\r\n")
        append(data)
        appendUTF8("\r\n")
    }

    mutating func appendUTF8(_ string: String) {
        append(Data(string.utf8))
    }
}

private extension ISO8601DateFormatter {
    static let htmlKeepHub: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let htmlKeepHubWithoutFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func htmlKeepHubDate(from value: String) -> Date? {
        htmlKeepHub.date(from: value) ?? htmlKeepHubWithoutFractionalSeconds.date(from: value)
    }
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
            excluding: WebPageLibrary.isAppManagedProjectFilePath
        )

        if filePaths.count == 1 {
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
            excluding: WebPageLibrary.isAppManagedProjectFilePath
        )
        return archiveURL
    }

    func cleanupTemporaryExportIfNeeded(at shareURL: URL) {
        let exportsURL = fileManager.temporaryDirectory
            .appendingPathComponent("HTMLKeepShareExports", isDirectory: true)
            .standardizedFileURL
        let standardizedShareURL = shareURL.standardizedFileURL
        guard standardizedShareURL.path.hasPrefix(exportsURL.path + "/") else {
            return
        }

        try? fileManager.removeItem(at: standardizedShareURL.deletingLastPathComponent())
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
