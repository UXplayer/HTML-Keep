import Foundation
import SwiftUI
import UIKit

private let homeScrollTopContentMargin: CGFloat = 14
private let homeEmptyStateMaxWidth: CGFloat = 720
private let homeBottomDockReservedHeight: CGFloat = 92
private let homeEmptyStateIllustrationAssetName = "IconDocument"
private let homeEmptyStateIllustrationSpriteResourceName = "bear-idle-sheet"
private let homeEmptyStateIllustrationSize: CGFloat = 156
private let homeListRowHorizontalInset: CGFloat = 16
private let homeListRowVerticalInset: CGFloat = 6
private let homeListRowCornerRadius: CGFloat = 22
private let homeListRowMinimumHeight: CGFloat = 72
private let homeGridReflowAnimation = Animation.spring(response: 0.32, dampingFraction: 0.86, blendDuration: 0.08)
let homeSearchPullOpenThresholdDistance: CGFloat = 100
let homeSearchPullCloseThresholdDistance: CGFloat = 90
let homeSearchPullActivationDistance: CGFloat = 16
let homeSearchTopTolerance: CGFloat = 1.5
let homeSearchScrollMetricTolerance: CGFloat = 0.5
let homeSearchVisibleRowCount = 4
let homeSearchProgressUpdateTolerance: CGFloat = 0.006
let homeSearchOpaqueMaskProgress: CGFloat = 1
let homeSearchOverlayScaleExpansion: CGFloat = 0.08
let homeSearchOverlayScaleUndershoot: CGFloat = 0.015
let homeSearchOverlayMinimumPullScale: CGFloat = 0.98
let homeSearchPullCompressionDistance: CGFloat = homeSearchPullOpenThresholdDistance
let homeSearchOverlayOpenAnimationDuration: TimeInterval = 0.16
let homeSearchOverlaySettleAnimationDuration: TimeInterval = 0.14
let homeSearchOverlayCloseAnimationDuration: TimeInterval = 0.12

enum HomeICloudEmptyState: Equatable {
    case normal
    case proEntitlementPrompt
    case syncing
    case failed

    var debugDescription: String {
        switch self {
        case .normal:
            return "normal"
        case .proEntitlementPrompt:
            return "proEntitlementPrompt"
        case .syncing:
            return "syncing"
        case .failed:
            return "failed"
        }
    }
}

private struct HomeEmptyStatePromptConfiguration {
    let title: String
    let message: String?
    let activityStyle: AppEmptyStatePromptActivityStyle
    let primaryAction: AppEmptyStatePromptAction?
    let secondaryAction: AppEmptyStatePromptAction?
    let contentIdentity: String
}

struct HomeView: View {
    let pages: [WebPage]
    let displayMode: HomeDisplayMode
    let iCloudEmptyState: HomeICloudEmptyState
    let projectIconURL: (WebPage) -> URL?
    let hasFullContentSearchIndex: Bool
    let searchResults: (String, WebPageSearchScope) -> [WebPageSearchResult]
    let onSearchFullContent: () async -> Void
    let onOpenImporter: () -> Void
    let onOpenSettings: (UIBarButtonItem?) -> Void
    let onOpenProEntitlement: () -> Void
    let onDismissICloudSyncPrompt: () -> Void
    let onRetryICloudSync: () -> Void
    let onOpenProject: (WebPage) -> Void
    let onSelectEntry: (WebPage, WebPageEntry) -> Void
    let onRenamePage: (WebPage, String) -> Void
    let onSetProjectIcon: (WebPage) -> Void
    let onDeletePage: (WebPage) -> Void
    let onDebugICloudSync: () -> Void

    @State private var renamingPage: WebPage?
    @State private var draftPageTitle = ""
    @StateObject private var searchOverlayPresenter = HomeSearchOverlayPresenter()
    @StateObject private var homeSearchScrollController = HomeSearchScrollController()
    @State private var isHomeScrollAtTop = false
    @State private var homeScrollTopOverscrollDistance: CGFloat = 0
    @State private var isTrackingSearchPull = false
    @State private var isSearchPullCommitted = false
    @State private var isSearchPullOpenArmed = false
    @State private var isSearchPullKeyboardActive = false
    @State private var syncToastMessage: String?
    @State private var syncToastID = UUID()

    var body: some View {
        ZStack(alignment: .bottom) {
            AppPageBackground()

            if pages.isEmpty {
                GeometryReader { proxy in
                    let availableHeight = max(proxy.size.height - homeBottomDockReservedHeight, 0)
                    let columnWidth = min(proxy.size.width, homeEmptyStateMaxWidth)
                    let cardWidth = max(columnWidth - 40, 0)

                    ScrollView {
                        AppEmptyStateViewport(
                            columnWidth: columnWidth,
                            contentWidth: cardWidth,
                            minHeight: availableHeight
                        ) {
                            emptyState
                        }
                        .padding(.bottom, homeBottomDockReservedHeight)
                    }
                    .background(homeSearchScrollObserver)
                }
            } else {
                switch displayMode {
                case .list:
                    webPageList
                case .grid:
                    webPageGrid
                }
            }

            BottomActionDock {
                AppActionButton(AppStrings.localized("打开网页文件"), scene: .sky) {
                    onOpenImporter()
                }
            }

            if let syncToastMessage {
                HomeToast(message: syncToastMessage)
                    .padding(.bottom, homeBottomDockReservedHeight)
                    .padding(.horizontal, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .navigationTitle(AppStrings.localized("app.displayName"))
        .navigationBarTitleDisplayMode(.inline)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onChange(of: displayMode) { _, _ in
            resetSearchPullTracking()
        }
        .onChange(of: pages.count) { _, _ in
            resetSearchPullTracking()
        }
        .alert(AppStrings.localized("重命名项目"), isPresented: Binding(
            get: { renamingPage != nil },
            set: { if !$0 { renamingPage = nil } }
        )) {
            TextField(AppStrings.localized("项目名称"), text: $draftPageTitle)
            Button(AppStrings.localized("取消"), role: .cancel) {
                renamingPage = nil
            }
            Button(AppStrings.localized("保存")) {
                if let renamingPage {
                    onRenamePage(renamingPage, draftPageTitle)
                }
                renamingPage = nil
            }
        }
        .background(SystemAlertTextFieldClearButtonInstaller(isActive: renamingPage != nil))
        #if DEBUG
        .background(DebugNavigationTitleLongPressInstaller(onLongPress: onDebugICloudSync))
        #endif
        .background(SystemNavigationBarMenuInstaller(
            onOpenSettings: onOpenSettings,
            onOpenSearch: {
                presentSearchOverlayFromButton()
            }
        ))
        #if DEBUG
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-HTMLKeepShowSearchOverlayOnLaunch") {
                DispatchQueue.main.async {
                    presentSearchOverlayFromButton()
                }
            }
        }
        #endif
    }

    @ViewBuilder
    private var emptyState: some View {
        let configuration = emptyStatePromptConfiguration

        AppEmptyStatePrompt(
            title: configuration.title,
            illustrationAssetName: homeEmptyStateIllustrationAssetName,
            illustrationSpriteResourceName: homeEmptyStateIllustrationSpriteResourceName,
            illustrationPlacement: .top,
            illustrationSize: homeEmptyStateIllustrationSize,
            message: configuration.message,
            activityStyle: configuration.activityStyle,
            primaryAction: configuration.primaryAction,
            secondaryAction: configuration.secondaryAction,
            contentIdentity: configuration.contentIdentity
        )
    }

    private var emptyStatePromptConfiguration: HomeEmptyStatePromptConfiguration {
        switch iCloudEmptyState {
        case .normal:
            return HomeEmptyStatePromptConfiguration(
                title: AppStrings.localized("还没有网页"),
                message: AppStrings.localized("打开一个 HTML 文件或 ZIP 压缩包，就可以在这里查看它。"),
                activityStyle: .none,
                primaryAction: nil,
                secondaryAction: nil,
                contentIdentity: "home.empty.noPages"
            )
        case .proEntitlementPrompt:
            return HomeEmptyStatePromptConfiguration(
                title: AppStrings.localized("你在其他设备上有网页"),
                message: AppStrings.localized("需要开通 iCloud 云同步、同步已有的网页吗？"),
                activityStyle: .none,
                primaryAction: AppEmptyStatePromptAction(
                    title: AppStrings.localized("开通 Pro 权益，立即同步"),
                    scene: .premiumGold,
                    size: .large,
                    action: onOpenProEntitlement
                ),
                secondaryAction: AppEmptyStatePromptAction(
                    title: AppStrings.localized("暂不同步，稍后再说"),
                    scene: .neutralLightWithBorder,
                    size: .large,
                    action: onDismissICloudSyncPrompt
                ),
                contentIdentity: "home.empty.iCloudProEntitlementPrompt"
            )
        case .syncing:
            return HomeEmptyStatePromptConfiguration(
                title: AppStrings.localized("正在从 iCloud 同步网页..."),
                message: nil,
                activityStyle: .typingDots,
                primaryAction: nil,
                secondaryAction: nil,
                contentIdentity: "home.empty.iCloudSyncing"
            )
        case .failed:
            return HomeEmptyStatePromptConfiguration(
                title: AppStrings.localized("同步遇到了一些问题"),
                message: AppStrings.localized("请检查网络状况后重新尝试。"),
                activityStyle: .none,
                primaryAction: AppEmptyStatePromptAction(
                    title: AppStrings.localized("再试一次"),
                    systemImage: "arrow.clockwise",
                    scene: .sky,
                    action: onRetryICloudSync
                ),
                secondaryAction: nil,
                contentIdentity: "home.empty.iCloudFailed"
            )
        }
    }

    private var webPageList: some View {
        List {
            ForEach(pages) { page in
                projectRow(page)
                    .listRowInsets(EdgeInsets(
                        top: homeListRowVerticalInset,
                        leading: homeListRowHorizontalInset,
                        bottom: homeListRowVerticalInset,
                        trailing: homeListRowHorizontalInset
                    ))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .contentMargins(.top, homeScrollTopContentMargin, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(homeSearchScrollObserver)
        .safeAreaInset(edge: .bottom) {
            Color.clear
                .frame(height: 92)
                .accessibilityHidden(true)
        }
    }

    private func projectRow(_ page: WebPage) -> some View {
        let status = homeStatus(for: page)

        return Button {
            open(page)
        } label: {
            AppListItem(
                title: page.title,
                subtitle: subtitle(for: page),
                statusText: nil,
                showsChevron: false,
                horizontalPadding: 16,
                minimumHeight: homeListRowMinimumHeight
            ) {
                projectListIcon(for: page, status: status)
            }
            .opacity(status?.dimsContent == true ? 0.62 : 1)
            .background(AppTheme.surfaceStrong, in: RoundedRectangle(
                cornerRadius: homeListRowCornerRadius,
                style: .continuous
            ))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            projectContextMenu(for: page)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDeletePage(page)
            } label: {
                Image(systemName: "trash")
            }
            .tint(AppTheme.coral)
            .accessibilityLabel(AppStrings.localized("删除"))
        }
        .accessibilityLabel(accessibilityLabel(for: page))
    }

    private var webPageGrid: some View {
        GeometryReader { proxy in
            let metrics = HomeGridMetrics(containerSize: proxy.size)
            let pageIDs = pages.map(\.id)

            ScrollView {
                LazyVGrid(columns: metrics.columns, alignment: .center, spacing: metrics.rowSpacing) {
                    ForEach(pages) { page in
                        projectGridItem(page, metrics: metrics)
                            .transition(.asymmetric(
                                insertion: .identity,
                                removal: .scale(scale: 0.92).combined(with: .opacity)
                            ))
                    }
                }
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.top, metrics.topPadding)
                .padding(.bottom, 110)
                .animation(homeGridReflowAnimation, value: pageIDs)
                .background(homeSearchScrollObserver)
            }
        }
    }

    private func projectGridItem(_ page: WebPage, metrics: HomeGridMetrics) -> some View {
        let status = homeStatus(for: page)

        return Button {
            open(page)
        } label: {
            VStack(spacing: metrics.iconTitleSpacing) {
                ZStack(alignment: .topTrailing) {
                    projectGridIcon(for: page, metrics: metrics, status: status)

                    if status?.showsErrorBadge == true {
                        HomeStatusBadge(size: 16)
                            .offset(x: 5, y: -5)
                    }
                }
                .frame(width: metrics.iconFrameSize, height: metrics.iconFrameSize)

                Text(page.title)
                    .font(.system(size: metrics.labelFontSize, weight: .medium))
                    .foregroundStyle(AppTheme.contentPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .opacity(status?.dimsContent == true ? 0.58 : 1)
                    .frame(width: metrics.labelWidth, height: metrics.labelHeight, alignment: .top)
            }
            .frame(width: metrics.itemWidth, height: metrics.itemHeight, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            projectContextMenu(for: page)
        }
        .accessibilityLabel(accessibilityLabel(for: page))
    }

    @ViewBuilder
    private func projectContextMenu(for page: WebPage) -> some View {
        Button {
            open(page)
        } label: {
            menuLabel(
                AppStrings.localized("打开"),
                systemImage: "arrow.up.forward.app"
            )
        }
        .tint(Color.primary)
        .disabled(!canOpen(page))

        Button {
            startRenaming(page)
        } label: {
            menuLabel(AppStrings.localized("重命名"), systemImage: "pencil")
        }
        .tint(Color.primary)

        Button {
            onSetProjectIcon(page)
        } label: {
            menuLabel(AppStrings.localized("设置图标"), systemImage: "photo")
        }
        .tint(Color.primary)

        Button(role: .destructive) {
            onDeletePage(page)
        } label: {
            menuLabel(
                AppStrings.localized("删除"),
                systemImage: "trash",
                isDestructive: true
            )
        }
        .tint(Color.red)
    }

    private func menuLabel(_ title: String, systemImage: String, isDestructive: Bool = false) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(isDestructive ? Color.red : Color.primary)
        }
    }

    private func open(_ page: WebPage) {
        let status = homeStatus(for: page)
        if status?.showsSyncToast == true {
            showSyncInProgressToast()
            return
        }
        guard canOpen(page) else {
            if status?.showsUnavailableToast == true {
                showToast(AppStrings.localized("同步失败，暂时无法打开。可以删除后重新同步。"))
            }
            return
        }
        onSelectEntry(page, preferredEntry(for: page))
    }

    private func presentSearchOverlay(
        initialProgress: CGFloat = 0,
        initialCardScale: CGFloat? = nil,
        animated: Bool = true,
        focusWhenSettled: Bool = true,
        activateAfterAnimation: Bool = false
    ) {
        searchOverlayPresenter.present(
            pages: pages,
            projectIconURL: projectIconURL,
            hasFullContentSearchIndex: hasFullContentSearchIndex,
            searchResults: searchResults,
            onSearchFullContent: onSearchFullContent,
            onSelectEntry: onSelectEntry,
            initialProgress: initialProgress,
            initialCardScale: initialCardScale,
            animated: animated,
            focusWhenSettled: focusWhenSettled,
            activateAfterAnimation: activateAfterAnimation,
            onDidDismiss: {
                isSearchPullCommitted = false
                isTrackingSearchPull = false
                isSearchPullOpenArmed = false
                isSearchPullKeyboardActive = false
                homeScrollTopOverscrollDistance = 0
                homeSearchScrollController.unlock()
            }
        )
    }

    private func presentSearchOverlayFromButton() {
        deactivateSearchPullKeyboardIfNeeded()
        isSearchPullCommitted = false
        isSearchPullOpenArmed = false
        isSearchPullKeyboardActive = false
        endSearchPullInteraction(keepsHomeScrollLocked: false)
        presentSearchOverlay(
            initialProgress: 0,
            animated: true,
            focusWhenSettled: false,
            activateAfterAnimation: true
        )
    }

    private func searchPresentationProgress(for pullDistance: CGFloat) -> CGFloat {
        let activeDistance = max(pullDistance - homeSearchPullActivationDistance, 0)
        let activeRange = max(homeSearchPullOpenThresholdDistance - homeSearchPullActivationDistance, 1)
        return min(activeDistance / activeRange, 1)
    }

    private func searchPullCardScale(for pullDistance: CGFloat) -> CGFloat {
        let progress = searchPresentationProgress(for: pullDistance)
        let thresholdScale = 1 - homeSearchOverlayScaleUndershoot
        if pullDistance <= homeSearchPullOpenThresholdDistance {
            return 1
                + homeSearchOverlayScaleExpansion * (1 - progress)
                - homeSearchOverlayScaleUndershoot * progress
        }

        let extraDistance = pullDistance - homeSearchPullOpenThresholdDistance
        let compressionProgress = min(extraDistance / max(homeSearchPullCompressionDistance, 1), 1)
        return thresholdScale
            - (thresholdScale - homeSearchOverlayMinimumPullScale) * compressionProgress
    }

    private var homeSearchScrollObserver: some View {
        HomeSearchScrollObserver(scrollController: homeSearchScrollController) { metrics in
            handleSearchScrollMetrics(metrics)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func handleSearchScrollMetrics(_ metrics: HomeSearchScrollMetrics) {
        guard !isSearchPullCommitted else { return }

        isHomeScrollAtTop = metrics.isAtTop
        homeScrollTopOverscrollDistance = metrics.topOverscrollDistance

        if metrics.didEndDragging {
            finishSearchPullFromScrollDistance(metrics.topOverscrollDistance)
            return
        }

        guard metrics.isActivelyDragging else {
            if !metrics.isAtTop {
                cancelSearchPullOpeningImmediately()
            }
            return
        }

        let pullDistance = metrics.topOverscrollDistance
        if pullDistance <= homeSearchPullActivationDistance {
            if isTrackingSearchPull || searchOverlayPresenter.isPresented {
                triggerSearchPullCloseFeedbackIfNeeded()
                deactivateSearchPullKeyboardIfNeeded()
                cancelSearchPullOpeningImmediately()
            }
            return
        }

        beginSearchPullInteraction()
        let progress = searchPresentationProgress(for: pullDistance)
        let cardScale = searchPullCardScale(for: pullDistance)

        if searchOverlayPresenter.isPresented {
            searchOverlayPresenter.updateInteractiveProgress(progress, cardScale: cardScale)
        } else {
            presentSearchOverlay(
                initialProgress: progress,
                initialCardScale: cardScale,
                animated: false,
                focusWhenSettled: false
            )
        }

        updateSearchPullArming(for: pullDistance)
    }

    private func finishSearchPullFromScrollDistance(_ pullDistance: CGFloat) {
        guard isTrackingSearchPull || searchOverlayPresenter.isPresented else {
            deactivateSearchPullKeyboardIfNeeded()
            endSearchPullInteraction(keepsHomeScrollLocked: false)
            return
        }

        if pullDistance >= homeSearchPullOpenThresholdDistance {
            triggerSearchPullOpenFeedbackIfNeeded()
        } else if pullDistance <= homeSearchPullCloseThresholdDistance {
            triggerSearchPullCloseFeedbackIfNeeded()
        }

        if isSearchPullOpenArmed {
            activateSearchPullKeyboardIfNeeded()
            commitSearchPullOpening()
        } else {
            deactivateSearchPullKeyboardIfNeeded()
            endSearchPullInteraction(keepsHomeScrollLocked: false)
            searchOverlayPresenter.cancelInteractiveOpening()
        }
    }

    private func updateSearchPullArming(for pullDistance: CGFloat) {
        if pullDistance >= homeSearchPullOpenThresholdDistance {
            triggerSearchPullOpenFeedbackIfNeeded()
            activateSearchPullKeyboardIfNeeded()
            return
        }

        if isSearchPullOpenArmed {
            if pullDistance <= homeSearchPullCloseThresholdDistance {
                triggerSearchPullCloseFeedbackIfNeeded()
                deactivateSearchPullKeyboardIfNeeded()
            } else {
                activateSearchPullKeyboardIfNeeded()
            }
            return
        }

        deactivateSearchPullKeyboardIfNeeded()
    }

    private func commitSearchPullOpening() {
        guard searchOverlayPresenter.isPresented,
              !isSearchPullCommitted else {
            return
        }
        isSearchPullCommitted = true
        homeSearchScrollController.lockAtRestingTop()
        endSearchPullInteraction(keepsHomeScrollLocked: true)
        searchOverlayPresenter.finishInteractiveOpening(focusDelay: 0.12)
    }

    private func beginSearchPullInteraction() {
        guard !isTrackingSearchPull,
              !isSearchPullCommitted else {
            return
        }
        isTrackingSearchPull = true
    }

    private func cancelSearchPullOpeningImmediately() {
        guard isTrackingSearchPull else { return }
        deactivateSearchPullKeyboardIfNeeded()
        endSearchPullInteraction(keepsHomeScrollLocked: false)
        searchOverlayPresenter.cancelInteractiveOpening(animated: false)
    }

    private func activateSearchPullKeyboardIfNeeded() {
        guard !isSearchPullKeyboardActive else { return }
        isSearchPullKeyboardActive = true
        searchOverlayPresenter.activateInteractiveKeyboard()
    }

    private func deactivateSearchPullKeyboardIfNeeded() {
        guard isSearchPullKeyboardActive else { return }
        isSearchPullKeyboardActive = false
        searchOverlayPresenter.deactivateInteractiveKeyboard()
    }

    private func triggerSearchPullOpenFeedbackIfNeeded() {
        guard !isSearchPullOpenArmed else { return }
        isSearchPullOpenArmed = true
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred(intensity: 0.85)
    }

    private func triggerSearchPullCloseFeedbackIfNeeded() {
        guard isSearchPullOpenArmed else { return }
        isSearchPullOpenArmed = false
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred(intensity: 0.55)
    }

    private func endSearchPullInteraction(keepsHomeScrollLocked: Bool) {
        isTrackingSearchPull = false
        if !keepsHomeScrollLocked {
            homeSearchScrollController.unlock()
        }
    }

    private func resetSearchPullTracking() {
        deactivateSearchPullKeyboardIfNeeded()
        isSearchPullCommitted = false
        isSearchPullOpenArmed = false
        isSearchPullKeyboardActive = false
        isHomeScrollAtTop = false
        homeScrollTopOverscrollDistance = 0
        endSearchPullInteraction(keepsHomeScrollLocked: false)
    }

    private func showSyncInProgressToast() {
        showToast(AppStrings.localized("正在同步中，请稍后再打开。"))
    }

    private func showToast(_ message: String) {
        let toastID = UUID()
        syncToastID = toastID

        withAnimation(.spring(response: 0.26, dampingFraction: 0.88)) {
            syncToastMessage = message
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard syncToastID == toastID else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                syncToastMessage = nil
            }
        }
    }

    private func startRenaming(_ page: WebPage) {
        draftPageTitle = page.title
        renamingPage = page
    }

    private func accessibilityLabel(for page: WebPage) -> String {
        var parts = [page.title]
        if page.resolvedEntries.count > 1 {
            parts.append(AppStrings.localized("多页面项目"))
        }
        if let status = homeStatus(for: page) {
            parts.append(status.title)
        }
        return parts.joined(separator: "，")
    }

    @ViewBuilder
    private func projectListIcon(for page: WebPage, status: HomeProjectStatus?) -> some View {
        if status?.showsLoading == true {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
                .tint(AppTheme.contentAccent)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
        } else {
            ZStack(alignment: .topTrailing) {
                ProjectIconImage(
                    iconURL: projectIconURL(page),
                    iconVersion: page.projectIcon?.updatedAt,
                    fallbackSymbolName: projectIconSymbolName(for: page),
                    size: 28,
                    cornerRadius: 7,
                    fallbackBackground: .webPageTop(safeAreaTopBackground(for: page)),
                    fallbackPlacement: .listItem
                )

                if status?.showsErrorBadge == true {
                    HomeStatusBadge(size: 12)
                        .offset(x: 3, y: -3)
                }
            }
        }
    }

    private func projectGridIcon(
        for page: WebPage,
        metrics: HomeGridMetrics,
        status: HomeProjectStatus?
    ) -> some View {
        ProjectIconImage(
            iconURL: projectIconURL(page),
            iconVersion: page.projectIcon?.updatedAt,
            fallbackSymbolName: projectIconSymbolName(for: page),
            size: metrics.iconSize,
            cornerRadius: metrics.iconCornerRadius,
            fallbackBackground: .webPageTop(safeAreaTopBackground(for: page)),
            fallbackPlacement: .pageBackground
        )
        .opacity(status?.dimsContent == true ? 0.78 : 1)
        .overlay {
            if status?.showsLoading == true {
                RoundedRectangle(cornerRadius: metrics.iconCornerRadius, style: .continuous)
                    .fill(AppTheme.surfaceStrong.opacity(0.66))
                    .accessibilityHidden(true)
            }
        }
        .overlay {
            if status?.showsLoading == true {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.regular)
                    .tint(AppTheme.contentAccent)
                    .accessibilityHidden(true)
            }
        }
    }

    private func safeAreaTopBackground(for page: WebPage) -> String? {
        preferredEntry(for: page).safeAreaTopColor ?? page.safeAreaTopColor
    }

    private func subtitle(for page: WebPage) -> String? {
        guard let sourceFileName = page.sourceFileName, !sourceFileName.isEmpty else {
            return nil
        }
        return sourceFileName
    }

    private func projectIconSymbolName(for page: WebPage) -> String {
        if page.opensInNativeFileViewer {
            return "folder.fill"
        }
        return page.resolvedEntries.count > 1 ? "folder.fill" : "doc.text.fill"
    }

    private func homeStatus(for page: WebPage) -> HomeProjectStatus? {
        let statuses = [page.lastLoadStatus] + page.resolvedEntries.map(\.lastLoadStatus)

        if let status = statuses.first(where: { $0.isCloudPackageLoading }) {
            return .cloudLoading(status.title)
        }
        if let status = statuses.first(where: { $0.isCloudPackageFailed }) {
            return .cloudUnavailable(status.title)
        }
        if statuses.contains(.missing) {
            return .localUnavailable(WebPageLoadStatus.missing.title)
        }
        if statuses.contains(.failed) {
            return .localUnavailable(WebPageLoadStatus.failed.title)
        }
        return nil
    }

    private func preferredEntry(for page: WebPage) -> WebPageEntry {
        if let defaultEntryID = page.defaultEntryID,
           let entry = page.resolvedEntries.first(where: { $0.id == defaultEntryID }) {
            return entry
        }
        return page.resolvedEntries[0]
    }

    private func canOpen(_ page: WebPage) -> Bool {
        !page.lastLoadStatus.isCloudPackageUnavailable &&
            !preferredEntry(for: page).lastLoadStatus.isCloudPackageUnavailable
    }

}

struct ProjectPageListView: View {
    let page: WebPage
    let onSelectEntry: (WebPage, WebPageEntry) -> Void

    var body: some View {
        ZStack {
            AppPageBackground()

            List {
                Section {
                    ForEach(page.resolvedEntries) { entry in
                        pageEntryRow(entry)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .contentMargins(.top, homeScrollTopContentMargin, for: .scrollContent)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(page.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func pageEntryRow(_ entry: WebPageEntry) -> some View {
        Button {
            onSelectEntry(page, entry)
        } label: {
            AppListItem(
                title: entry.title,
                subtitle: entry.entryFileName,
                leadingIconAssetName: "htmlfile",
                statusText: entry.lastLoadStatus == .ready ? nil : entry.lastLoadStatus.title,
                showsChevron: false,
                horizontalPadding: 0,
                minimumHeight: nil
            )
        }
        .buttonStyle(.plain)
    }
}

private enum HomeProjectStatus {
    case cloudLoading(String)
    case cloudUnavailable(String)
    case localUnavailable(String)

    var title: String {
        switch self {
        case .cloudLoading(let title), .cloudUnavailable(let title), .localUnavailable(let title):
            return title
        }
    }

    var showsLoading: Bool {
        if case .cloudLoading = self {
            return true
        }
        return false
    }

    var showsErrorBadge: Bool {
        !showsLoading
    }

    var showsSyncToast: Bool {
        if case .cloudLoading = self {
            return true
        }
        return false
    }

    var showsUnavailableToast: Bool {
        if case .cloudUnavailable = self {
            return true
        }
        return false
    }

    var dimsContent: Bool {
        switch self {
        case .cloudUnavailable:
            return true
        case .cloudLoading, .localUnavailable:
            return false
        }
    }
}

private extension WebPageLoadStatus {
    var isCloudPackageLoading: Bool {
        switch self {
        case .metadataOnly, .downloading:
            return true
        case .ready, .missing, .failed, .downloadFailed, .invalidPackage:
            return false
        }
    }

    var isCloudPackageFailed: Bool {
        switch self {
        case .downloadFailed, .invalidPackage:
            return true
        case .ready, .missing, .failed, .metadataOnly, .downloading:
            return false
        }
    }
}

private struct HomeToast: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(AppTheme.contentPrimary)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background {
                Capsule(style: .continuous)
                    .fill(AppTheme.surfaceStrong)
                    .shadow(color: AppTheme.surfaceShadow, radius: 8, x: 0, y: 4)
            }
            .accessibilityAddTraits(.isStaticText)
    }
}

private struct HomeStatusBadge: View {
    let size: CGFloat

    var body: some View {
        Image(systemName: "exclamationmark.circle.fill")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(AppTheme.coral)
            .background(Circle().fill(AppTheme.surfaceStrong))
            .accessibilityHidden(true)
    }
}

private struct HomeGridMetrics {
    let columnCount: Int
    let horizontalPadding: CGFloat
    let itemWidth: CGFloat
    let labelWidth: CGFloat
    let contentWidth: CGFloat
    let iconSize: CGFloat
    let labelFontSize: CGFloat
    let labelHeight: CGFloat
    let rowSpacing: CGFloat
    let topPadding: CGFloat
    let iconTitleSpacing: CGFloat

    init(containerSize: CGSize) {
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        let isLandscape = containerSize.width > containerSize.height
        let width = max(containerSize.width, 1)

        columnCount = isPad ? (isLandscape ? 6 : 5) : 4

        let referenceIconSize: CGFloat = 64
        let iconSizeForContainer = isPad ?
            referenceIconSize :
            min(max(width * (referenceIconSize / 402), referenceIconSize), 70)
        let minimumSpacing: CGFloat = isPad ? 36 : 20
        let templateMarginRatio: CGFloat = isPad ? 165 / 1210 : 35.5 / 402
        let preferredPadding = width * templateMarginRatio
        let maximumPadding = max(
            0,
            (width - iconSizeForContainer * CGFloat(columnCount) - minimumSpacing * CGFloat(columnCount - 1)) / 2
        )
        horizontalPadding = min(max(preferredPadding, isPad ? 48 : 28), maximumPadding)

        itemWidth = iconSizeForContainer
        labelWidth = iconSizeForContainer + 1
        contentWidth = max(width - horizontalPadding * 2, itemWidth * CGFloat(columnCount))

        iconSize = iconSizeForContainer
        labelFontSize = 12
        labelHeight = 16
        rowSpacing = isPad ? 43 : 17
        topPadding = homeScrollTopContentMargin
        iconTitleSpacing = 5
    }

    var columns: [GridItem] {
        let spacing = max(
            columnCount > 1 ?
                (max(0, contentWidth - itemWidth * CGFloat(columnCount)) / CGFloat(columnCount - 1)) :
                0,
            UIDevice.current.userInterfaceIdiom == .pad ? 36 : 20
        )
        return Array(
            repeating: GridItem(.fixed(itemWidth), spacing: spacing, alignment: .top),
            count: columnCount
        )
    }

    var iconCornerRadius: CGFloat {
        iconSize * 0.225
    }

    var iconFrameSize: CGFloat {
        iconSize
    }

    var itemHeight: CGFloat {
        iconFrameSize + iconTitleSpacing + labelHeight
    }

}

#Preview {
    NavigationStack {
        HomeView(
            pages: [
                WebPage(
                    id: UUID(),
                    title: "Demo Page",
                    sourceDescription: "Files",
                    sourceFileName: "demo.html",
                    folderName: UUID().uuidString,
                    entryRelativePath: "index.html",
                    contentSHA256: nil,
                    createdAt: .now,
                    lastOpenedAt: .now,
                    lastLoadStatus: .ready
                )
            ],
            displayMode: .grid,
            iCloudEmptyState: .normal,
            projectIconURL: { _ in nil },
            hasFullContentSearchIndex: false,
            searchResults: { _, _ in [] },
            onSearchFullContent: {},
            onOpenImporter: {},
            onOpenSettings: { _ in },
            onOpenProEntitlement: {},
            onDismissICloudSyncPrompt: {},
            onRetryICloudSync: {},
            onOpenProject: { _ in },
            onSelectEntry: { _, _ in },
            onRenamePage: { _, _ in },
            onSetProjectIcon: { _ in },
            onDeletePage: { _ in },
            onDebugICloudSync: {}
        )
    }
}
