import SwiftUI
import UIKit

private enum SettingsICloudSyncFeedback {
    static let rotationDuration: TimeInterval = 1.35
    static let loadingPhaseCount = 3
    static let loadingPhaseDuration = rotationDuration / Double(loadingPhaseCount)
}

private enum SettingsICloudSyncGuideAnimation {
    static let rotationDuration: TimeInterval = 3.2
}

private let recentlyDeletedEmptyStateMaxWidth: CGFloat = 720
private let settingsListTopContentMargin: CGFloat = 16

enum RecentlyDeletedVisibilityPolicy {
    static let freeVisibleInterval: TimeInterval = 3 * 24 * 60 * 60

    static func isVisible(
        _ deletedPage: DeletedWebPage,
        canViewFullHistory: Bool,
        now: Date = .now
    ) -> Bool {
        canViewFullHistory || deletedPage.deletedAt >= now.addingTimeInterval(-freeVisibleInterval)
    }
}

enum SettingsContainerStyle {
    case appBackground
    case systemPopover
}

private extension View {
    func settingsListRowSurface() -> some View {
        listRowBackground(AppTheme.surfaceStrong)
    }
}

struct SettingsView: View {
    @AppStorage(AppPreferenceKeys.language) private var languagePreferenceRaw = AppLanguagePreference.automatic.rawValue
    @AppStorage(AppPreferenceKeys.appearance) private var appearancePreferenceRaw = AppAppearancePreference.automatic.rawValue
    @AppStorage(AppPreferenceKeys.homeDisplayMode) private var homeDisplayModeRaw = HomeDisplayMode.list.rawValue
    @AppStorage(AppPreferenceKeys.iCloudSyncEnabled) private var isICloudSyncEnabled = true
    @AppStorage(AppPreferenceKeys.expertModeEnabled) private var isExpertModeEnabled = AppBuildFlavor.current.defaultIsExpertModeEnabled
    @EnvironmentObject private var proEntitlementStore: ProEntitlementStore
    #if !HTMLKEEP_COMMUNITY
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    #endif
    @State private var isShowingShareSheet = false
    @State private var iCloudSyncFeedbackStartedAt: Date?
    @State private var iCloudSyncFeedbackResetAt: Date?
    @State private var debugToolsStatusMessage: String?

    let iCloudSyncService: ICloudWebPageSyncService?
    let iCloudSyncAccess: ICloudWebPageSyncAccess
    let onICloudSyncEnabled: () -> Void
    let onICloudSyncDisabled: () -> Void
    let onICloudSyncNow: () -> Void
    let onOpenRecentlyDeleted: () -> Void
    let onOpenProjectWidgetGuide: () -> Void
    let onOpenICloudSyncProEntitlementGuide: () -> Void
    let onOpenAgentImport: () -> Void
    let onOpenHomeLayoutSettings: () -> Void
    let onOpenLanguageSettings: () -> Void
    let onOpenAppearanceSettings: () -> Void
    let onOpenDebugTools: () -> Void
    let onOpenProEntitlement: () -> Void
    @ObservedObject var debugFloatingBallVisibilityStore: DebugFloatingBallVisibilityStore
    var containerStyle: SettingsContainerStyle = .appBackground

    var body: some View {
        styledSettingsList
        .navigationTitle(AppStrings.localized("设置"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: isICloudSyncEnabled) { _, isEnabled in
            guard proEntitlementStore.canUseCloudSync else {
                return
            }
            if isEnabled {
                onICloudSyncEnabled()
            } else {
                onICloudSyncDisabled()
            }
        }
        .sheet(isPresented: $isShowingShareSheet) {
            SettingsSupportShareSheet(activityItems: [Self.appStoreProductURL])
        }
    }

    @ViewBuilder
    private var styledSettingsList: some View {
        switch containerStyle {
        case .appBackground:
            ZStack {
                AppPageBackground()
                settingsList
                    .scrollContentBackground(.hidden)
            }
        case .systemPopover:
            settingsList
        }
    }

    private var settingsList: some View {
        List {
            Section {
                #if HTMLKEEP_COMMUNITY
                ProEntitlementPresentationCard(
                    presentation: proEntitlementStore.presentation
                )
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color.clear)
                #else
                MembershipEntryCard(
                    entryPresentation: subscriptionStore.entryPresentation,
                    onOpen: onOpenProEntitlement
                )
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color.clear)
                #endif
            }

            Section {
                Button {
                    onOpenHomeLayoutSettings()
                } label: {
                    SettingsActionRow(
                        title: AppStrings.localized("首页布局"),
                        leadingIconAssetName: "IconHome",
                        statusText: currentHomeDisplayModeTitle
                    )
                }
                .buttonStyle(.plain)
                .settingsListRowSurface()

                Button {
                    onOpenAppearanceSettings()
                } label: {
                    SettingsActionRow(
                        title: AppStrings.localized("主题色"),
                        leadingIconAssetName: "IconDarkOrLight",
                        statusText: currentAppearanceTitle
                    )
                }
                .buttonStyle(.plain)
                .settingsListRowSurface()

                Button {
                    onOpenLanguageSettings()
                } label: {
                    SettingsActionRow(
                        title: AppStrings.localized("语言"),
                        leadingIconAssetName: "IconEarth",
                        statusText: currentLanguageTitle
                    )
                }
                .buttonStyle(.plain)
                .settingsListRowSurface()
            } header: {
                AppListSectionTitle(AppStrings.localized("显示"))
            }

            Section {
                Button {
                    onOpenProjectWidgetGuide()
                } label: {
                    SettingsActionRow(
                        title: AppStrings.localized("桌面小组件"),
                        leadingIconAssetName: "IconWidgetGrid"
                    )
                }
                .buttonStyle(.plain)
                .settingsListRowSurface()

                Button {
                    onOpenAgentImport()
                } label: {
                    SettingsActionRow(
                        title: AppStrings.localized("Agent 管理"),
                        leadingIconAssetName: "IconAgentManagement"
                    )
                }
                .buttonStyle(.plain)
                .settingsListRowSurface()
            } header: {
                AppListSectionTitle(AppStrings.localized("扩展"))
            }

            Section {
                Button {
                    openAppStoreReviewPage()
                } label: {
                    SettingsActionRow(
                        title: AppStrings.localized("给个好评"),
                        leadingIconAssetName: "IconThumbUp"
                    )
                }
                .buttonStyle(.plain)
                .settingsListRowSurface()

                Button {
                    isShowingShareSheet = true
                } label: {
                    SettingsActionRow(
                        title: AppStrings.localized("分享给好友"),
                        leadingIconAssetName: "IconShareFriends"
                    )
                }
                .buttonStyle(.plain)
                .settingsListRowSurface()
            } header: {
                AppListSectionTitle(AppStrings.localized("支持"))
            }

            Section {
                Button {
                    openExternalLink(Self.githubRepositoryURL)
                } label: {
                    SettingsActionRow(
                        title: "GitHub",
                        leadingIconAssetName: "IconGitHub"
                    )
                }
                .buttonStyle(.plain)
                .settingsListRowSurface()

                Button {
                    openExternalLink(Self.discordURL)
                } label: {
                    SettingsActionRow(
                        title: "Discord",
                        leadingIconAssetName: "IconDiscord"
                    )
                }
                .buttonStyle(.plain)
                .settingsListRowSurface()
            } header: {
                AppListSectionTitle(AppStrings.localized("关于"))
            }

            Section {
                Button {
                    onOpenRecentlyDeleted()
                } label: {
                    SettingsActionRow(
                        title: AppStrings.localized("最近删除"),
                        leadingIconAssetName: "IconTrash"
                    )
                }
                .buttonStyle(.plain)
                .settingsListRowSurface()

                iCloudSyncRow
                    .settingsListRowSurface()
            } header: {
                AppListSectionTitle(AppStrings.localized("数据"))
            } footer: {
                SettingsICloudSyncStatusFooter(
                    proEntitlementState: proEntitlementStore.proEntitlementState,
                    isEnabled: displayedICloudSyncEnabled,
                    isSwitchDisabled: isICloudSyncUnavailable,
                    showsSyncFeedback: isShowingICloudSyncFeedback,
                    syncFeedbackStartedAt: iCloudSyncFeedbackStartedAt,
                    latestRecord: latestICloudSyncRecord,
                    onSyncNow: onICloudSyncNow,
                    onOpenSettings: openSystemSettings,
                    onOpenProEntitlement: onOpenICloudSyncProEntitlementGuide
                )
            }

            if AppBuildFlavor.current.isTestingBuild {
                Section {
                    Button {
                        onOpenDebugTools()
                    } label: {
                        SettingsActionRow(
                            title: AppStrings.localized("debug.settings.open.title"),
                            subtitle: AppStrings.localized("debug.settings.open.subtitle"),
                            leadingIconAssetName: "IconFlaskPurple",
                            statusText: nil
                        )
                    }
                    .buttonStyle(.plain)
                    .settingsListRowSurface()

                    SettingsToggleRow(
                        title: AppStrings.localized("debug.settings.floating.toggle"),
                        leadingIconAssetName: "IconEye",
                        isOn: debugFloatingBallVisibilityBinding
                    )
                    .settingsListRowSurface()

                    Button {
                        resetDebugFloatingBallPosition()
                    } label: {
                        SettingsActionRow(
                            title: AppStrings.localized("debug.settings.floating.reset"),
                            leadingIconAssetName: "IconCompass",
                            showsChevron: false
                        )
                    }
                    .buttonStyle(.plain)
                    .settingsListRowSurface()

                    if let debugToolsStatusMessage {
                        Text(debugToolsStatusMessage)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                            .settingsListRowSurface()
                    }
                } header: {
                    AppListSectionTitle(AppStrings.localized("debug.settings.section.title"))
                }
            }

            SettingsVersionFooter(
                version: currentAppVersion,
                build: currentAppBuild,
                isExpertModeEnabled: $isExpertModeEnabled
            )
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
        .listStyle(.insetGrouped)
        .contentMargins(.top, settingsListTopContentMargin, for: .scrollContent)
        .onAppear(perform: refreshICloudSyncFeedbackState)
        .onChange(of: isICloudSyncEnabled) { _, _ in
            refreshICloudSyncFeedbackState()
        }
        .onChange(of: isICloudSyncInProgress) { _, _ in
            refreshICloudSyncFeedbackState()
        }
        .onChange(of: latestICloudSyncRecord) { _, _ in
            refreshICloudSyncFeedbackState()
        }
        .task(id: iCloudSyncFeedbackResetAt) {
            guard let iCloudSyncFeedbackResetAt else { return }

            let delay = iCloudSyncFeedbackResetAt.timeIntervalSinceNow
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            guard !Task.isCancelled else { return }
            self.iCloudSyncFeedbackStartedAt = nil
            self.iCloudSyncFeedbackResetAt = nil
        }
    }

    private var currentAppVersion: String {
        nonEmptyBundleValue(for: "CFBundleShortVersionString") ?? "0.0.0"
    }

    private var currentAppBuild: String {
        nonEmptyBundleValue(for: "CFBundleVersion") ?? "0"
    }

    private var currentLanguageTitle: String {
        let preference = AppLanguagePreference.value(for: languagePreferenceRaw)
        return AppStrings.localized(preference.titleKey)
    }

    private var currentAppearanceTitle: String {
        let preference = AppAppearancePreference.value(for: appearancePreferenceRaw)
        return AppStrings.localized(preference.titleKey)
    }

    private var currentHomeDisplayModeTitle: String {
        let mode = HomeDisplayMode.value(for: homeDisplayModeRaw)
        return AppStrings.localized(mode.layoutTitleKey)
    }

    @ViewBuilder
    private var iCloudSyncRow: some View {
        if !AppDistribution.current.supportsOfficialICloudSync {
            EmptyView()
        } else if isICloudSyncProEntitlementLocked {
            Button(action: onOpenICloudSyncProEntitlementGuide) {
                SettingsICloudSyncInlineRow(
                    isEnabled: .constant(false),
                    isSwitchDisabled: true,
                    isSyncing: false
                )
            }
            .buttonStyle(.plain)
        } else {
            SettingsICloudSyncInlineRow(
                isEnabled: iCloudSyncEnabledBinding,
                isSwitchDisabled: isICloudSyncSwitchDisabled,
                isSyncing: isICloudSyncInProgress
            )
        }
    }

    private var iCloudSyncEnabledBinding: Binding<Bool> {
        Binding(
            get: { displayedICloudSyncEnabled },
            set: { newValue in
                guard proEntitlementStore.canUseCloudSync else {
                    onOpenICloudSyncProEntitlementGuide()
                    return
                }
                isICloudSyncEnabled = newValue
            }
        )
    }

    private var displayedICloudSyncEnabled: Bool {
        proEntitlementStore.canUseCloudSync && isICloudSyncEnabled
    }

    private var isICloudSyncProEntitlementLocked: Bool {
        guard AppDistribution.current.supportsOfficialICloudSync else { return false }
        return proEntitlementStore.proEntitlementState == .free || proEntitlementStore.proEntitlementState == .expired
    }

    private var isICloudSyncInProgress: Bool {
        displayedICloudSyncEnabled && latestICloudSyncRecord?.kind == .inProgress
    }

    private var isICloudSyncUnavailable: Bool {
        guard displayedICloudSyncEnabled else { return false }
        return latestICloudSyncRecord?.kind == .noAccount || latestICloudSyncRecord?.kind == .unavailable
    }

    private var isICloudSyncSwitchDisabled: Bool {
        proEntitlementStore.proEntitlementState == .unknown ||
            isICloudSyncUnavailable ||
            isShowingICloudSyncFeedback
    }

    private var isShowingICloudSyncFeedback: Bool {
        if isICloudSyncInProgress {
            return true
        }

        guard let iCloudSyncFeedbackResetAt else {
            return false
        }

        return iCloudSyncFeedbackResetAt > .now
    }

    private var latestICloudSyncRecord: ICloudWebPageSyncUserRecord? {
        iCloudSyncService?.userRecords.first
    }

    private var debugFloatingBallVisibilityBinding: Binding<Bool> {
        Binding(
            get: { debugFloatingBallVisibilityStore.isVisible },
            set: { isVisible in
                setDebugFloatingBallVisibility(isVisible)
            }
        )
    }

    private func refreshICloudSyncFeedbackState() {
        let now = Date()

        guard displayedICloudSyncEnabled else {
            iCloudSyncFeedbackStartedAt = nil
            iCloudSyncFeedbackResetAt = nil
            return
        }

        if isICloudSyncInProgress {
            iCloudSyncFeedbackStartedAt = latestICloudSyncRecord?.createdAt ?? now
            iCloudSyncFeedbackResetAt = nil
            return
        }

        guard let iCloudSyncFeedbackStartedAt else {
            iCloudSyncFeedbackResetAt = nil
            return
        }

        let elapsed = max(now.timeIntervalSince(iCloudSyncFeedbackStartedAt), 0)
        let completedCycles = max(1, Int(ceil(elapsed / SettingsICloudSyncFeedback.rotationDuration)))
        let resetAt = iCloudSyncFeedbackStartedAt.addingTimeInterval(
            Double(completedCycles) * SettingsICloudSyncFeedback.rotationDuration
        )

        if resetAt <= now {
            self.iCloudSyncFeedbackStartedAt = nil
            iCloudSyncFeedbackResetAt = nil
        } else {
            iCloudSyncFeedbackResetAt = resetAt
        }
    }

    private func nonEmptyBundleValue(for key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String, !value.isEmpty else {
            return nil
        }

        return value
    }

    private func openAppStoreReviewPage() {
        guard let reviewURL = URL(string: Self.appStoreReviewURLString) else {
            return
        }

        UIApplication.shared.open(reviewURL)
    }

    private func openExternalLink(_ url: URL) {
        UIApplication.shared.open(url)
    }

    private func openSystemSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
            return
        }

        UIApplication.shared.open(settingsURL)
    }

    private func resetDebugFloatingBallPosition() {
        DebugFloatingBallPositionStore().reset()
        debugToolsStatusMessage = AppStrings.localized("debug.settings.floating.reset.status")
    }

    private func setDebugFloatingBallVisibility(_ isVisible: Bool) {
        debugFloatingBallVisibilityStore.setVisible(isVisible)
        debugToolsStatusMessage = AppStrings.localized(
            isVisible
                ? "debug.settings.floating.visible.status"
                : "debug.settings.floating.hidden.status"
        )
    }

    private static let appID = "6767142789"
    private static let appStoreProductURL = URL(string: "https://apps.apple.com/app/id\(appID)")!
    private static let appStoreReviewURLString = "https://apps.apple.com/app/id\(appID)?action=write-review"
    private static let githubRepositoryURL = URL(string: "https://github.com/UXplayer/HTML-Keep")!
    private static let discordURL = URL(string: "https://discord.gg/MTE3ER26X")!
}

private struct SettingsActionRow: View {
    let title: String
    let subtitle: String?
    let leadingIconAssetName: String
    var statusText: String?
    var showsChevron: Bool

    init(
        title: String,
        subtitle: String? = nil,
        leadingIconAssetName: String,
        statusText: String? = nil,
        showsChevron: Bool = true
    ) {
        self.title = title
        self.subtitle = subtitle
        self.leadingIconAssetName = leadingIconAssetName
        self.statusText = statusText
        self.showsChevron = showsChevron
    }

    var body: some View {
        AppListItem(
            title: title,
            subtitle: subtitle,
            leadingIconAssetName: leadingIconAssetName,
            statusText: statusText,
            showsChevron: showsChevron,
            horizontalPadding: 0,
            minimumHeight: nil
        )
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let leadingIconAssetName: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            AppColoredIcon(assetName: leadingIconAssetName)
                .frame(width: 28, height: 28)

            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(AppTheme.listItemTitle)
                .lineLimit(1)

            Spacer(minLength: 12)

            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .tint(AppTheme.deepWater)
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .padding(.horizontal, 0)
        .contentShape(Rectangle())
    }
}

private struct SettingsICloudSyncIcon: UIViewRepresentable {
    let isSyncing: Bool
    let rotationDuration: TimeInterval

    init(
        isSyncing: Bool,
        rotationDuration: TimeInterval = SettingsICloudSyncFeedback.rotationDuration
    ) {
        self.isSyncing = isSyncing
        self.rotationDuration = rotationDuration
    }

    func makeUIView(context _: Context) -> IconView {
        IconView()
    }

    func updateUIView(_ iconView: IconView, context: Context) {
        if isSyncing {
            context.coordinator.startContinuousRotation(on: iconView.iconLayer)
        } else {
            context.coordinator.finishCurrentRotation(on: iconView.iconLayer)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(rotationDuration: rotationDuration)
    }

    static func dismantleUIView(_ uiView: IconView, coordinator: Coordinator) {
        coordinator.stop(on: uiView.iconLayer)
    }

    final class IconView: UIView {
        let iconLayer = CALayer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            isAccessibilityElement = false
            clipsToBounds = false

            iconLayer.contents = UIImage(named: "IconICloudSync")?.cgImage
            iconLayer.contentsGravity = .resizeAspect
            iconLayer.contentsScale = UIScreen.main.scale
            iconLayer.masksToBounds = false
            layer.addSublayer(iconLayer)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var intrinsicContentSize: CGSize {
            CGSize(width: 28, height: 28)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            iconLayer.bounds = bounds
            iconLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
            iconLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            CATransaction.commit()
        }
    }

    final class Coordinator: NSObject, CAAnimationDelegate {
        private static let rotationKey = "htmlanywhere.icloudSync.rotation"
        private static let finishKey = "htmlanywhere.icloudSync.finishRotation"
        private static let fullTurn = CGFloat.pi * 2

        private let rotationDuration: TimeInterval
        private var isRotatingContinuously = false
        private var isFinishing = false

        init(rotationDuration: TimeInterval) {
            self.rotationDuration = rotationDuration
            super.init()
        }

        func startContinuousRotation(on layer: CALayer) {
            guard !isRotatingContinuously else {
                return
            }

            let currentAngle = currentRotationAngle(for: layer)
            layer.removeAnimation(forKey: Self.finishKey)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.setAffineTransform(CGAffineTransform(rotationAngle: currentAngle))
            CATransaction.commit()

            let animation = CABasicAnimation(keyPath: "transform.rotation.z")
            animation.fromValue = currentAngle
            animation.toValue = currentAngle + Self.fullTurn
            animation.duration = rotationDuration
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            animation.isRemovedOnCompletion = false
            layer.add(animation, forKey: Self.rotationKey)

            isRotatingContinuously = true
            isFinishing = false
        }

        func finishCurrentRotation(on layer: CALayer) {
            guard isRotatingContinuously else {
                return
            }

            let currentAngle = normalizedPositiveAngle(currentRotationAngle(for: layer))
            layer.removeAnimation(forKey: Self.rotationKey)
            layer.removeAnimation(forKey: Self.finishKey)

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.setAffineTransform(CGAffineTransform(rotationAngle: currentAngle))
            CATransaction.commit()

            let remainingAngle = Self.fullTurn - currentAngle
            guard remainingAngle > 0.01 else {
                stop(on: layer)
                return
            }

            let animation = CABasicAnimation(keyPath: "transform.rotation.z")
            animation.fromValue = currentAngle
            animation.toValue = Self.fullTurn
            animation.duration = rotationDuration * CFTimeInterval(remainingAngle / Self.fullTurn)
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false
            animation.delegate = self
            animation.setValue(layer, forKey: "targetLayer")
            layer.add(animation, forKey: Self.finishKey)

            isRotatingContinuously = false
            isFinishing = true
        }

        func stop(on layer: CALayer) {
            layer.removeAnimation(forKey: Self.rotationKey)
            layer.removeAnimation(forKey: Self.finishKey)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.setAffineTransform(.identity)
            CATransaction.commit()
            isRotatingContinuously = false
            isFinishing = false
        }

        func animationDidStop(_ animation: CAAnimation, finished flag: Bool) {
            guard flag,
                  let layer = animation.value(forKey: "targetLayer") as? CALayer else {
                return
            }

            stop(on: layer)
        }

        private func currentRotationAngle(for layer: CALayer) -> CGFloat {
            let transform = (layer.presentation() ?? layer).affineTransform()
            return atan2(transform.b, transform.a)
        }

        private func normalizedPositiveAngle(_ angle: CGFloat) -> CGFloat {
            let normalized = angle.truncatingRemainder(dividingBy: Self.fullTurn)
            return normalized >= 0 ? normalized : normalized + Self.fullTurn
        }
    }
}

private struct SettingsICloudSyncInlineRow: View {
    @Binding var isEnabled: Bool

    let isSwitchDisabled: Bool
    let isSyncing: Bool

    var body: some View {
        HStack(spacing: 12) {
            SettingsICloudSyncIcon(isSyncing: isSyncing)
                .frame(width: 28, height: 28)

            Text(AppStrings.localized("iCloud 云同步"))
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(AppTheme.listItemTitle)
                .lineLimit(1)
            .layoutPriority(1)

            Spacer(minLength: 12)

            Toggle(AppStrings.localized("iCloud 云同步"), isOn: $isEnabled)
                .labelsHidden()
                .disabled(isSwitchDisabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct SettingsICloudSyncStatusFooter: View {
    @Environment(\.layoutDirection) private var layoutDirection

    let proEntitlementState: ProEntitlementState
    let isEnabled: Bool
    let isSwitchDisabled: Bool
    let showsSyncFeedback: Bool
    let syncFeedbackStartedAt: Date?
    let latestRecord: ICloudWebPageSyncUserRecord?
    let onSyncNow: () -> Void
    let onOpenSettings: () -> Void
    let onOpenProEntitlement: () -> Void

    @ViewBuilder
    var body: some View {
        if proEntitlementState == .expired {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(AppStrings.localized("同步已暂停"))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 12)

                Button {
                    onOpenProEntitlement()
                } label: {
                    Text(AppStrings.localized("立即续费"))
                        .fontWeight(.semibold)
                }
                .buttonStyle(.plain)
                .fixedSize()
            }
        } else if isEnabled {
            TimelineView(
                .animation(
                    minimumInterval: SettingsICloudSyncFeedback.loadingPhaseDuration,
                    paused: !showsSyncFeedback
                )
            ) { timeline in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(recentSyncTimeText(at: timeline.date))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 12)

                    if canOpenSettings {
                        Button {
                            onOpenSettings()
                        } label: {
                            Text(AppStrings.localized("打开设置"))
                                .fontWeight(.semibold)
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                    } else if canSyncNow {
                        Button {
                            onSyncNow()
                        } label: {
                            Text(AppStrings.localized("立即同步"))
                                .fontWeight(.semibold)
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                    }
                }
            }
        }
    }

    private var canSyncNow: Bool {
        isEnabled && !isSwitchDisabled && !showsSyncFeedback
    }

    private var canOpenSettings: Bool {
        isEnabled && latestRecord?.kind == .noAccount
    }

    private func recentSyncTimeText(at date: Date) -> String {
        if showsSyncFeedback {
            return syncingText(at: date)
        }

        guard let latestRecord else {
            return AppStrings.localized("还没有同步过")
        }

        if latestRecord.kind == .noAccount {
            return AppStrings.localized("未登录 iCloud")
        }

        if latestRecord.kind == .unavailable {
            return AppStrings.localized("iCloud 暂不可用")
        }

        if latestRecord.kind == .failed {
            return AppStrings.localized("同步失败，将自动重试")
        }

        return String(
            format: AppStrings.localized("最近同步：%@"),
            timeText(for: latestRecord)
        )
    }

    private func syncingText(at date: Date) -> String {
        let anchor = syncFeedbackStartedAt ?? latestRecord?.createdAt ?? date
        let elapsed = max(date.timeIntervalSince(anchor), 0)
        let step = Int(elapsed / SettingsICloudSyncFeedback.loadingPhaseDuration) % SettingsICloudSyncFeedback.loadingPhaseCount + 1
        return AppStrings.localized("数据同步中") + String(repeating: ".", count: step)
    }

    private func timeText(for record: ICloudWebPageSyncUserRecord) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent

        if calendar.isDateInToday(record.createdAt) {
            formatter.dateFormat = "HH:mm:ss"
            return String(
                format: AppStrings.localized("今天 %@"),
                formatter.string(from: record.createdAt)
            )
        }

        if calendar.component(.year, from: record.createdAt) == calendar.component(.year, from: .now) {
            formatter.dateFormat = layoutDirection == .rightToLeft ? "d/M HH:mm" : "M月d日 HH:mm"
            return formatter.string(from: record.createdAt)
        }

        formatter.dateFormat = layoutDirection == .rightToLeft ? "d/M/yyyy" : "yyyy年M月d日"
        return formatter.string(from: record.createdAt)
    }
}

struct RecentlyDeletedWebPagesView: View {
    let deletedPages: [DeletedWebPage]
    let canViewFullHistory: Bool
    let projectIconURL: (DeletedWebPage) -> URL?
    let onOpenProject: (DeletedWebPage) -> Void
    let onSelectEntry: (DeletedWebPage, WebPageEntry) -> Void
    let onRestore: (DeletedWebPage) -> Bool
    let onPermanentlyDelete: (DeletedWebPage) -> Void
    let onOpenProEntitlement: () -> Void

    @State private var permanentDeleteCandidate: DeletedWebPage?
    @State private var isRestoreErrorPresented = false

    var body: some View {
        ZStack {
            AppPageBackground()

            if visibleDeletedPages.isEmpty && !hasProEntitlementLockedDeletedPages {
                GeometryReader { proxy in
                    let columnWidth = min(proxy.size.width, recentlyDeletedEmptyStateMaxWidth)
                    let cardWidth = max(columnWidth - 40, 0)

                    ScrollView {
                        AppEmptyStateViewport(
                            columnWidth: columnWidth,
                            contentWidth: cardWidth,
                            minHeight: proxy.size.height
                        ) {
                            emptyState
                        }
                    }
                }
            } else {
                List {
                    recentlyDeletedListSections
                }
                .listStyle(.insetGrouped)
                .listSectionSpacing(.compact)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle(AppStrings.localized("最近删除"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            AppStrings.localized("彻底删除网页？"),
            isPresented: Binding(
                get: { permanentDeleteCandidate != nil },
                set: { if !$0 { permanentDeleteCandidate = nil } }
            )
        ) {
            Button(AppStrings.localized("取消"), role: .cancel) {
                permanentDeleteCandidate = nil
            }
            Button(AppStrings.localized("彻底删除"), role: .destructive) {
                if let permanentDeleteCandidate {
                    onPermanentlyDelete(permanentDeleteCandidate)
                }
                permanentDeleteCandidate = nil
            }
        } message: {
            Text(AppStrings.localized("这会永久删除这个网页及其本机文件，无法恢复。"))
        }
        .alert(AppStrings.localized("网页文件缺失"), isPresented: $isRestoreErrorPresented) {
            Button(AppStrings.localized("知道了"), role: .cancel) {}
        } message: {
            Text(AppStrings.localized("这个网页的入口文件已经不在本地网页文件夹中。"))
        }
    }

    @ViewBuilder
    private var recentlyDeletedListSections: some View {
        if shouldRenderRecentWindowSection {
            if recentVisibleDeletedPages.isEmpty {
                Section {
                    recentWindowEmptyRow
                } header: {
                    if shouldShowTimeGroupHeaders {
                        Text(RecentlyDeletedWebPageTimeGroup.withinFreeWindow.title)
                    }
                }
            } else {
                recentlyDeletedSections(
                    recentVisibleDeletedPages,
                    headerTitle: shouldShowTimeGroupHeaders
                        ? RecentlyDeletedWebPageTimeGroup.withinFreeWindow.title
                        : nil
                )
            }
        }

        if shouldRenderOlderSection {
            if canViewFullHistory {
                recentlyDeletedSections(
                    olderVisibleDeletedPages,
                    headerTitle: shouldShowTimeGroupHeaders
                        ? RecentlyDeletedWebPageTimeGroup.olderThanFreeWindow.title
                        : nil
                )
            } else {
                Section {
                    proEntitlementGuideRow
                } header: {
                    if shouldShowTimeGroupHeaders {
                        Text(RecentlyDeletedWebPageTimeGroup.olderThanFreeWindow.title)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func recentlyDeletedSections(
        _ pages: [DeletedWebPage],
        headerTitle: String?
    ) -> some View {
        ForEach(pages) { deletedPage in
            Section {
                recentlyDeletedRow(deletedPage)
            } header: {
                if deletedPage.id == pages.first?.id,
                   let headerTitle {
                    Text(headerTitle)
                }
            }
        }
    }

    private var visibleDeletedPages: [DeletedWebPage] {
        let now = Date()
        return deletedPages.filter {
            RecentlyDeletedVisibilityPolicy.isVisible(
                $0,
                canViewFullHistory: canViewFullHistory,
                now: now
            )
        }
    }

    private var hasProEntitlementLockedDeletedPages: Bool {
        proEntitlementLockedDeletedPageCount > 0
    }

    private var proEntitlementLockedDeletedPageCount: Int {
        guard !canViewFullHistory else { return 0 }
        let now = Date()
        return deletedPages.filter {
            !RecentlyDeletedVisibilityPolicy.isVisible(
                $0,
                canViewFullHistory: false,
                now: now
            )
        }.count
    }

    private var recentVisibleDeletedPages: [DeletedWebPage] {
        visibleDeletedPages(in: .withinFreeWindow)
    }

    private var olderVisibleDeletedPages: [DeletedWebPage] {
        visibleDeletedPages(in: .olderThanFreeWindow)
    }

    private var shouldRenderRecentWindowSection: Bool {
        !recentVisibleDeletedPages.isEmpty || shouldShowRecentWindowEmptyRow
    }

    private var shouldRenderOlderSection: Bool {
        !olderVisibleDeletedPages.isEmpty || hasProEntitlementLockedDeletedPages
    }

    private var shouldShowRecentWindowEmptyRow: Bool {
        !canViewFullHistory && recentVisibleDeletedPages.isEmpty && hasProEntitlementLockedDeletedPages
    }

    private var shouldShowTimeGroupHeaders: Bool {
        if canViewFullHistory {
            return !recentVisibleDeletedPages.isEmpty && !olderVisibleDeletedPages.isEmpty
        }
        return hasProEntitlementLockedDeletedPages
    }

    private var emptyState: some View {
        AppEmptyStatePrompt(
            title: AppStrings.localized("没有可恢复网页"),
            illustrationAssetName: "IconTrash",
            illustrationSpriteResourceName: "bear-idle-sheet",
            illustrationPlacement: .top,
            illustrationSize: 156,
            message: AppStrings.localized("最近删除的网页会显示在这里。"),
            contentIdentity: "recentlyDeleted.empty.noRecoverablePages"
        )
    }

    private var recentWindowEmptyRow: some View {
        Text(AppStrings.localized("最近三天没有删除的网页"))
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(AppTheme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
            .listRowSeparator(.hidden)
    }

    private func visibleDeletedPages(in timeGroup: RecentlyDeletedWebPageTimeGroup) -> [DeletedWebPage] {
        let sortedPages = visibleDeletedPages.sorted { $0.deletedAt > $1.deletedAt }
        let now = Date()
        return sortedPages.filter { timeGroup.contains($0.deletedAt, now: now) }
    }

    private var proEntitlementGuideRow: some View {
        VStack(spacing: 12) {
            Text(proEntitlementGuideTitle)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(AppTheme.contentPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)

            AppActionButton(
                AppStrings.localized("开通 Pro 权益"),
                scene: .premiumGold,
                action: onOpenProEntitlement
            )
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity)
        .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
        .listRowSeparator(.hidden)
    }

    private var proEntitlementGuideTitle: String {
        String(
            format: AppStrings.localized("recentlyDeleted.proEntitlementGuide.titleFormat"),
            proEntitlementLockedDeletedPageCount
        )
    }

    private func recentlyDeletedRow(_ deletedPage: DeletedWebPage) -> some View {
        Button {
            onSelectEntry(deletedPage, preferredEntry(for: deletedPage))
        } label: {
            AppListItem(
                title: deletedPage.page.title,
                subtitle: subtitle(for: deletedPage),
                subtitleSystemImage: "trash",
                statusText: projectStatus(for: deletedPage.page),
                showsChevron: false,
                horizontalPadding: 0,
                minimumHeight: nil
            ) {
                ProjectIconImage(
                    iconURL: projectIconURL(deletedPage),
                    iconVersion: deletedPage.page.projectIcon?.updatedAt,
                    fallbackSymbolName: projectIconSymbolName(for: deletedPage.page),
                    size: 28,
                    cornerRadius: 7,
                    fallbackBackground: .webPageTop(safeAreaTopBackground(for: deletedPage)),
                    fallbackPlacement: .listItem
                )
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                if !onRestore(deletedPage) {
                    isRestoreErrorPresented = true
                }
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .tint(AppTheme.leaf)
            .accessibilityLabel(AppStrings.localized("恢复"))
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                permanentDeleteCandidate = deletedPage
            } label: {
                Image(systemName: "trash")
            }
            .tint(AppTheme.coral)
            .accessibilityLabel(AppStrings.localized("彻底删除"))
        }
    }

    private func subtitle(for deletedPage: DeletedWebPage) -> String {
        formattedDeletedTime(deletedPage.deletedAt)
    }

    private func projectIconSymbolName(for page: WebPage) -> String {
        if page.opensInNativeFileViewer {
            return "folder.fill"
        }
        return page.resolvedEntries.count > 1 ? "folder.fill" : "doc.text.fill"
    }

    private func projectStatus(for page: WebPage) -> String? {
        let statuses = page.resolvedEntries.map(\.lastLoadStatus)
        if statuses.contains(.missing) {
            return WebPageLoadStatus.missing.title
        }
        if statuses.contains(.failed) {
            return WebPageLoadStatus.failed.title
        }
        return nil
    }

    private func preferredEntry(for deletedPage: DeletedWebPage) -> WebPageEntry {
        if let defaultEntryID = deletedPage.page.defaultEntryID,
           let entry = deletedPage.page.resolvedEntries.first(where: { $0.id == defaultEntryID }) {
            return entry
        }
        return deletedPage.page.resolvedEntries[0]
    }

    private func safeAreaTopBackground(for deletedPage: DeletedWebPage) -> String? {
        preferredEntry(for: deletedPage).safeAreaTopColor ?? deletedPage.page.safeAreaTopColor
    }

    private func formattedDeletedTime(_ date: Date) -> String {
        if Calendar.current.isDate(date, equalTo: .now, toGranularity: .year) {
            return Self.currentYearDeletedDateFormatter.string(from: date)
        }
        return Self.pastYearDeletedDateFormatter.string(from: date)
    }

    private static let currentYearDeletedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = AppStrings.localized("importDate.currentYearFormat")
        return formatter
    }()

    private static let pastYearDeletedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = AppStrings.localized("importDate.pastYearFormat")
        return formatter
    }()
}

struct RecentlyDeletedProjectPageListView: View {
    let deletedPage: DeletedWebPage
    let onSelectEntry: (DeletedWebPage, WebPageEntry) -> Void

    var body: some View {
        ZStack {
            AppPageBackground()

            List {
                Section {
                    ForEach(deletedPage.page.resolvedEntries) { entry in
                        pageEntryRow(entry)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(deletedPage.page.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func pageEntryRow(_ entry: WebPageEntry) -> some View {
        Button {
            onSelectEntry(deletedPage, entry)
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

private enum RecentlyDeletedWebPageTimeGroup: CaseIterable {
    case withinFreeWindow
    case olderThanFreeWindow

    var title: String {
        switch self {
        case .withinFreeWindow:
            return AppStrings.localized("三天内")
        case .olderThanFreeWindow:
            return AppStrings.localized("更早之前")
        }
    }

    func contains(_ date: Date, now: Date = .now) -> Bool {
        let freeWindowStart = now.addingTimeInterval(-RecentlyDeletedVisibilityPolicy.freeVisibleInterval)
        switch self {
        case .withinFreeWindow:
            return date >= freeWindowStart
        case .olderThanFreeWindow:
            return date < freeWindowStart
        }
    }
}

struct SettingsHomeLayoutSelectionView: View {
    @AppStorage(AppPreferenceKeys.homeDisplayMode) private var homeDisplayModeRaw = HomeDisplayMode.list.rawValue
    @State private var selectedModeRaw: String?
    var containerStyle: SettingsContainerStyle = .appBackground

    var body: some View {
        styledContent
            .navigationTitle(AppStrings.localized("首页布局"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if selectedModeRaw == nil {
                    selectedModeRaw = homeDisplayModeRaw
                }
            }
            .onChange(of: homeDisplayModeRaw) { _, newValue in
                guard selectedModeRaw != newValue else {
                    return
                }
                selectedModeRaw = newValue
            }
    }

    @ViewBuilder
    private var styledContent: some View {
        switch containerStyle {
        case .appBackground:
            ZStack {
                AppPageBackground()
                selectionContent
            }
        case .systemPopover:
            selectionContent
        }
    }

    private var selectionContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 22) {
                    ForEach(HomeDisplayMode.allCases) { mode in
                        SettingsHomeLayoutChoice(
                            mode: mode,
                            isSelected: mode == selectedMode,
                            action: {
                                guard mode != selectedMode else {
                                    return
                                }

                                withAnimation(SettingsHomeLayoutPreviewStyle.selectionAnimation) {
                                    selectedModeRaw = mode.rawValue
                                }

                                var transaction = Transaction()
                                transaction.disablesAnimations = true
                                withTransaction(transaction) {
                                    homeDisplayModeRaw = mode.rawValue
                                }
                            }
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(selectionSurface)
            }
            .padding(20)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private var selectedMode: HomeDisplayMode {
        HomeDisplayMode.value(for: selectedModeRaw ?? homeDisplayModeRaw)
    }

    private var selectionSurface: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(AppTheme.surface)
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AppTheme.surfaceBorder, lineWidth: 1)
            }
    }
}

private struct SettingsHomeLayoutChoice: View {
    let mode: HomeDisplayMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                SettingsHomeLayoutPreview(mode: mode, isSelected: isSelected)
                    .frame(maxWidth: .infinity)

                Text(AppStrings.localized(mode.layoutTitleKey))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AppTheme.listItemTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
                    .allowsTightening(true)

                selectionIndicator
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(SettingsNoHighlightButtonStyle())
        .accessibilityLabel(AppStrings.localized(mode.layoutTitleKey))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var selectionIndicator: some View {
        ZStack {
            Circle()
                .stroke(SettingsHomeLayoutPreviewStyle.unselectedIndicatorStroke, lineWidth: 3)
                .frame(width: 30, height: 30)
                .opacity(isSelected ? 0 : 1)

            Circle()
                .fill(SettingsHomeLayoutPreviewStyle.selectedIndicatorBackground)
                .frame(width: 30, height: 30)
                .opacity(isSelected ? 1 : 0)

            Circle()
                .fill(SettingsHomeLayoutPreviewStyle.selectedIndicatorGradient)
                .frame(width: 30, height: 30)
                .opacity(isSelected ? 1 : 0)

            Image(systemName: "checkmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(SettingsHomeLayoutPreviewStyle.selectedIndicatorMark)
                .flipsForRightToLeftLayoutDirection(false)
                .opacity(isSelected ? 1 : 0)
        }
        .accessibilityHidden(true)
        .animation(SettingsHomeLayoutPreviewStyle.selectionAnimation, value: isSelected)
    }
}

private struct SettingsNoHighlightButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

private struct SettingsHomeLayoutPreview: View {
    let mode: HomeDisplayMode
    let isSelected: Bool

    @State private var liftOffset: CGFloat = 0
    @State private var selectedShadowOpacity: Double = 0
    @State private var liftAnimationTask: Task<Void, Never>?

    var body: some View {
        phoneShell
            .aspectRatio(0.58, contentMode: .fit)
            .offset(y: liftOffset)
            .shadow(
                color: SettingsHomeLayoutPreviewStyle.unselectedPreviewShadow,
                radius: 3,
                x: 0,
                y: 1
            )
            .shadow(
                color: SettingsHomeLayoutPreviewStyle.selectedPreviewShadow.opacity(selectedShadowOpacity),
                radius: SettingsHomeLayoutPreviewStyle.selectedPreviewShadowRadius,
                x: 0,
                y: SettingsHomeLayoutPreviewStyle.selectedPreviewShadowYOffset
            )
            .accessibilityHidden(true)
            .onAppear {
                liftOffset = isSelected ? SettingsHomeLayoutPreviewStyle.selectedLiftOffset : 0
                selectedShadowOpacity = isSelected ? SettingsHomeLayoutPreviewStyle.selectedShadowSettledOpacity : 0
            }
            .onChange(of: isSelected) { _, newValue in
                animateLift(isSelected: newValue)
            }
    }

    private func animateLift(isSelected: Bool) {
        liftAnimationTask?.cancel()

        if isSelected {
            liftAnimationTask = Task { @MainActor in
                withAnimation(SettingsHomeLayoutPreviewStyle.liftOutAnimation) {
                    liftOffset = SettingsHomeLayoutPreviewStyle.selectedLiftOvershootOffset
                    selectedShadowOpacity = SettingsHomeLayoutPreviewStyle.selectedShadowOvershootOpacity
                }

                try? await Task.sleep(nanoseconds: 110_000_000)

                guard !Task.isCancelled else {
                    return
                }

                withAnimation(SettingsHomeLayoutPreviewStyle.liftSettleAnimation) {
                    liftOffset = SettingsHomeLayoutPreviewStyle.selectedLiftOffset
                    selectedShadowOpacity = SettingsHomeLayoutPreviewStyle.selectedShadowSettledOpacity
                }
            }
        } else {
            liftAnimationTask = nil
            withAnimation(SettingsHomeLayoutPreviewStyle.liftReturnAnimation) {
                liftOffset = 0
                selectedShadowOpacity = 0
            }
        }
    }

    private var phoneShell: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(SettingsHomeLayoutPreviewStyle.previewBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(SettingsHomeLayoutPreviewStyle.previewBorder, lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 8) {
                switch mode {
                case .list:
                    listPreviewRows
                case .grid:
                    gridPreviewIcons
                }
            }
            .padding(12)
        }
    }

    private var listPreviewRows: some View {
        VStack(spacing: 7) {
            ForEach(0..<5, id: \.self) { index in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: SettingsHomeLayoutPreviewStyle.listIconCornerRadius, style: .continuous)
                        .fill(listIconColor(for: index))
                        .frame(
                            width: SettingsHomeLayoutPreviewStyle.listIconSize,
                            height: SettingsHomeLayoutPreviewStyle.listIconSize
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Capsule()
                            .fill(SettingsHomeLayoutPreviewStyle.previewPrimaryText)
                            .frame(width: 44, height: 4)
                        Capsule()
                            .fill(SettingsHomeLayoutPreviewStyle.previewSecondaryText)
                            .frame(width: 30, height: 3)
                    }
                }
                .padding(.horizontal, SettingsHomeLayoutPreviewStyle.listRowHorizontalPadding)
                .padding(.vertical, SettingsHomeLayoutPreviewStyle.listRowVerticalPadding)
                .frame(
                    maxWidth: .infinity,
                    minHeight: SettingsHomeLayoutPreviewStyle.listRowHeight,
                    alignment: .leading
                )
                .background(
                    SettingsHomeLayoutPreviewStyle.listRowSurface,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .shadow(
                    color: SettingsHomeLayoutPreviewStyle.listRowShadow,
                    radius: 2,
                    x: 0,
                    y: 1
                )
            }
        }
    }

    private var gridPreviewIcons: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 3),
            spacing: 8
        ) {
            ForEach(0..<12, id: \.self) { index in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(gridIconColor(for: index))
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)

                    Capsule()
                        .fill(SettingsHomeLayoutPreviewStyle.previewPrimaryText)
                        .frame(height: 3)
                }
            }
        }
    }

    private func listIconColor(for index: Int) -> Color {
        SettingsHomeLayoutPreviewStyle.iconPalette[index % SettingsHomeLayoutPreviewStyle.iconPalette.count]
    }

    private func gridIconColor(for index: Int) -> Color {
        SettingsHomeLayoutPreviewStyle.iconPalette[index % SettingsHomeLayoutPreviewStyle.iconPalette.count]
    }
}

private enum SettingsHomeLayoutPreviewStyle {
    static let previewBackground = LinearGradient(
        colors: [AppTheme.pageTop, AppTheme.pageBottom],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let previewBorder = AppTheme.surfaceInsetBorder
    static let selectedPreviewShadow = AppTheme.sky.opacity(0.48)
    static let unselectedPreviewShadow = AppTheme.surfaceShadow.opacity(0.34)
    static let selectedPreviewShadowRadius: CGFloat = 6
    static let selectedPreviewShadowYOffset: CGFloat = 3
    static let selectedShadowOvershootOpacity: Double = 1
    static let selectedShadowSettledOpacity: Double = 0.72
    static let selectedLiftOffset: CGFloat = -1
    static let selectedLiftOvershootOffset: CGFloat = -2
    static let listRowSurface = AppTheme.surfaceStrong
    static let listRowShadow = AppTheme.surfaceShadow.opacity(0.26)
    static let previewPrimaryText = AppTheme.textSecondary.opacity(0.56)
    static let previewSecondaryText = AppTheme.textSecondary.opacity(0.28)
    static let listIconSize: CGFloat = 10
    static let listIconCornerRadius: CGFloat = 3
    static let listRowHorizontalPadding: CGFloat = 6
    static let listRowVerticalPadding: CGFloat = 4
    static let listRowHeight: CGFloat = 21
    static let unselectedIndicatorStroke = AppTheme.textSecondary.opacity(0.38)
    static let selectedIndicatorBackground = AppActionButtonScene.sky.palette.fill
    static let selectedIndicatorGradient = LinearGradient(
        stops: [
            .init(color: AppActionButtonScene.sky.palette.topGlowStart, location: 0),
            .init(color: AppActionButtonScene.sky.palette.topGlowEnd, location: 1)
        ],
        startPoint: UnitPoint(x: 0.5, y: 0),
        endPoint: UnitPoint(x: 0.5, y: 1)
    )
    static let selectedIndicatorMark = AppActionButtonScene.neutralLight.palette.fill
    static let iconPalette = [
        AppTheme.sky,
        AppTheme.leaf,
        AppTheme.gold,
        AppTheme.orange,
        AppTheme.aiPurple,
        AppTheme.mint
    ]
    static let selectionAnimation = Animation.spring(
        response: 0.32,
        dampingFraction: 0.58,
        blendDuration: 0.08
    )
    static let liftOutAnimation = Animation.easeOut(duration: 0.11)
    static let liftSettleAnimation = Animation.spring(
        response: 0.24,
        dampingFraction: 0.72,
        blendDuration: 0.04
    )
    static let liftReturnAnimation = Animation.easeOut(duration: 0.16)
}

struct SettingsLanguageSelectionView: View {
    @AppStorage(AppPreferenceKeys.language) private var languagePreferenceRaw = AppLanguagePreference.automatic.rawValue
    var containerStyle: SettingsContainerStyle = .appBackground

    var body: some View {
        SettingsPreferenceSelectionView(
            titleKey: "语言",
            options: AppLanguagePreference.allCases.map { preference in
                SettingsPreferenceOption(rawValue: preference.rawValue, titleKey: preference.titleKey)
            },
            selectionRawValue: $languagePreferenceRaw,
            containerStyle: containerStyle
        )
    }
}

struct SettingsAppearanceSelectionView: View {
    @AppStorage(AppPreferenceKeys.appearance) private var appearancePreferenceRaw = AppAppearancePreference.automatic.rawValue
    var containerStyle: SettingsContainerStyle = .appBackground

    var body: some View {
        SettingsPreferenceSelectionView(
            titleKey: "主题色",
            options: AppAppearancePreference.allCases.map { preference in
                SettingsPreferenceOption(rawValue: preference.rawValue, titleKey: preference.titleKey)
            },
            selectionRawValue: $appearancePreferenceRaw,
            containerStyle: containerStyle
        )
    }
}

struct SettingsProjectWidgetGuideView: View {
    var containerStyle: SettingsContainerStyle = .appBackground

    var body: some View {
        styledContent
            .navigationTitle(AppStrings.localized("桌面小组件"))
            .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var styledContent: some View {
        switch containerStyle {
        case .appBackground:
            ZStack {
                AppPageBackground()
                guideContent
            }
        case .systemPopover:
            guideContent
        }
    }

    private var guideContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsProjectWidgetIllustration()

                AppSurfaceCard {
                    Text(AppStrings.localized("把最常用、最喜爱的网页放到桌面"))
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(AppTheme.contentPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 12) {
                        SettingsProjectWidgetStepRow(index: 1, textKey: "在主屏幕添加“HTML Keep”小组件。")
                        SettingsProjectWidgetStepRow(index: 2, textKey: "长按、编辑小组件，选择网页项目。")
                        SettingsProjectWidgetStepRow(index: 3, textKey: "在桌面上点击小组件，即可直接打开。")
                    }
                    .padding(.top, 4)
                }
            }
            .padding(20)
            .frame(maxWidth: UIDevice.current.userInterfaceIdiom == .pad ? 760 : 520)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }
}

struct SettingsICloudSyncProEntitlementGuideView: View {
    @Binding var measuredSheetHeight: CGFloat

    let onOpenProEntitlement: () -> Void

    private let sheetChromeAllowance: CGFloat = 56

    var body: some View {
        ZStack {
            AppPageBackground()

            ScrollView {
                VStack(spacing: 18) {
                    SettingsICloudSyncProEntitlementIllustration()

                    AppActionButton(
                        AppStrings.localized("开通 Pro 权益，立即同步"),
                        scene: .premiumGold,
                        size: .large,
                        action: onOpenProEntitlement
                    )
                }
                .padding(20)
                .padding(.bottom, 6)
                .frame(maxWidth: UIDevice.current.userInterfaceIdiom == .pad ? 560 : 520)
                .frame(maxWidth: .infinity)
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .preference(
                                key: SettingsICloudSyncProEntitlementGuideHeightKey.self,
                                value: proxy.size.height
                            )
                    }
                )
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(AppStrings.localized("iCloud 云同步"))
        .navigationBarTitleDisplayMode(.inline)
        .onPreferenceChange(SettingsICloudSyncProEntitlementGuideHeightKey.self) { contentHeight in
            updateMeasuredSheetHeight(contentHeight: contentHeight)
        }
    }

    private func updateMeasuredSheetHeight(contentHeight: CGFloat) {
        guard contentHeight > 0 else { return }
        let targetHeight = contentHeight + sheetChromeAllowance
        let maxHeight = UIScreen.main.bounds.height * 0.9
        let minimumHeight: CGFloat = 360
        let resolvedHeight = min(max(targetHeight, minimumHeight), maxHeight)
        guard abs(measuredSheetHeight - resolvedHeight) > 1 else { return }
        measuredSheetHeight = resolvedHeight
    }
}

private struct SettingsICloudSyncProEntitlementGuideHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct SettingsICloudSyncProEntitlementIllustration: View {
    private let deviceSceneBaseSize = CGSize(width: 500, height: 236)

    var body: some View {
        VStack(spacing: 0) {
            deviceScene
                .padding(.top, 4)

            SettingsICloudSyncGuideMessage()
                .padding(.horizontal, 30)
                .padding(.top, 16)
                .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity)
        .background {
            SettingsICloudSyncIllustrationBackdrop()
                .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    private var deviceScene: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width, deviceSceneBaseSize.width)
            let scale = width / deviceSceneBaseSize.width

            deviceArtwork
                .frame(width: deviceSceneBaseSize.width, height: deviceSceneBaseSize.height)
                .scaleEffect(scale, anchor: .top)
                .frame(width: width, height: deviceSceneBaseSize.height * scale, alignment: .top)
                .frame(maxWidth: .infinity)
        }
        .aspectRatio(deviceSceneBaseSize.width / deviceSceneBaseSize.height, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private var deviceArtwork: some View {
        ZStack {
            SettingsICloudSyncGuideDevice(kind: .pad)
                .position(x: 180, y: 144)

            SettingsICloudSyncGuideDevice(kind: .phone)
                .position(x: 368, y: 133)

            SettingsICloudSyncGuideCloudBadge()
                .position(x: 298, y: 139)
        }
    }
}

private struct SettingsICloudSyncGuideMessage: View {
    var body: some View {
        Text(AppStrings.localized("开通 Pro 权益可在 iPhone 和 iPad 间自动同步全部数据"))
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(AppTheme.contentPrimary)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .shadow(color: Color.white.opacity(0.44), radius: 8, x: 0, y: 2)
    }
}

private struct SettingsICloudSyncIllustrationBackdrop: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(lightHex: 0xDDF6FF, darkHex: 0x142B3A),
                                Color(lightHex: 0xEAF8F0, darkHex: 0x15342F),
                                Color(lightHex: 0xF7FBF4, darkHex: 0x18342F)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                SettingsICloudSyncIllustrationCloud()
                    .fill(Color.white.opacity(0.58))
                    .frame(width: width * 0.34, height: height * 0.18)
                    .position(x: width * 0.20, y: height * 0.16)

                SettingsICloudSyncIllustrationCloud()
                    .fill(Color.white.opacity(0.44))
                    .frame(width: width * 0.28, height: height * 0.15)
                    .position(x: width * 0.82, y: height * 0.18)

                SettingsICloudSyncIllustrationHorizon()
                    .fill(Color.white.opacity(0.28))

                SettingsICloudSyncIllustrationHorizon()
                    .fill(AppTheme.sky.opacity(0.16))
                    .offset(y: height * 0.05)
            }
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        }
    }
}

private struct SettingsICloudSyncIllustrationCloud: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRoundedRect(
            in: CGRect(
                x: rect.minX + rect.width * 0.10,
                y: rect.minY + rect.height * 0.48,
                width: rect.width * 0.80,
                height: rect.height * 0.28
            ),
            cornerSize: CGSize(width: rect.height * 0.18, height: rect.height * 0.18)
        )
        path.addEllipse(
            in: CGRect(
                x: rect.minX + rect.width * 0.18,
                y: rect.minY + rect.height * 0.25,
                width: rect.width * 0.30,
                height: rect.height * 0.42
            )
        )
        path.addEllipse(
            in: CGRect(
                x: rect.minX + rect.width * 0.38,
                y: rect.minY + rect.height * 0.10,
                width: rect.width * 0.34,
                height: rect.height * 0.52
            )
        )
        path.addEllipse(
            in: CGRect(
                x: rect.minX + rect.width * 0.62,
                y: rect.minY + rect.height * 0.32,
                width: rect.width * 0.24,
                height: rect.height * 0.34
            )
        )
        return path
    }
}

private struct SettingsICloudSyncIllustrationHorizon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.height * 0.66))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.height * 0.64),
            control1: CGPoint(x: rect.width * 0.24, y: rect.height * 0.54),
            control2: CGPoint(x: rect.width * 0.68, y: rect.height * 0.78)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct SettingsICloudSyncGuideCloudBadge: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(AppTheme.surfaceStrong)
                .shadow(color: AppTheme.surfaceShadow.opacity(0.50), radius: 9, x: 0, y: 5)

            Circle()
                .stroke(AppTheme.surfaceBorder, lineWidth: 1)

            SettingsICloudSyncIcon(
                isSyncing: true,
                rotationDuration: SettingsICloudSyncGuideAnimation.rotationDuration
            )
                .frame(width: 52, height: 52)
        }
        .frame(width: 84, height: 84)
    }
}

private struct SettingsICloudSyncGuideDevice: View {
    enum Kind {
        case pad
        case phone
    }

    let kind: Kind

    private var size: CGSize {
        switch kind {
        case .pad:
            return CGSize(width: 186, height: 132)
        case .phone:
            return CGSize(width: 92, height: 154)
        }
    }

    private var cornerRadius: CGFloat {
        switch kind {
        case .pad:
            return 22
        case .phone:
            return 20
        }
    }

    var body: some View {
        ZStack {
            outerShell

            screen
                .padding(screenInsets)

            if kind == .phone {
                phoneSensorHousing
                    .position(x: size.width / 2, y: 17)

                homeIndicator(width: 28, opacity: 0.34)
                    .position(x: size.width / 2, y: size.height - 13)
            } else {
                Circle()
                    .fill(Color.white.opacity(0.38))
                    .frame(width: 4.5, height: 4.5)
                    .overlay {
                        Circle()
                            .fill(Color.black.opacity(0.62))
                            .frame(width: 2.6, height: 2.6)
                    }
                    .position(x: size.width / 2, y: 5.5)

                homeIndicator(width: 44, opacity: 0.28)
                    .position(x: size.width / 2, y: size.height - 12)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private var outerShell: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(lightHex: 0x252B36, darkHex: 0x11151C),
                        Color(lightHex: 0x05070A, darkHex: 0x030406)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.24), lineWidth: 1.2)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius - 2, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    .padding(2)
            }
            .shadow(color: AppTheme.surfaceShadow.opacity(0.45), radius: 8, x: 0, y: 5)
    }

    private var screenInsets: EdgeInsets {
        switch kind {
        case .pad:
            return EdgeInsets(top: 7, leading: 7, bottom: 7, trailing: 7)
        case .phone:
            return EdgeInsets(top: 5, leading: 5, bottom: 5, trailing: 5)
        }
    }

    private var phoneSensorHousing: some View {
        Capsule(style: .continuous)
            .fill(Color.black.opacity(0.76))
            .frame(width: 29, height: 8)
            .overlay(alignment: .trailing) {
                Circle()
                    .fill(Color.white.opacity(0.20))
                    .frame(width: 3.5, height: 3.5)
                    .padding(.trailing, 5)
            }
    }

    private func homeIndicator(width: CGFloat, opacity: Double) -> some View {
        Capsule(style: .continuous)
            .fill(Color.black.opacity(opacity))
            .frame(width: width, height: 3)
    }

    private var screenCornerRadius: CGFloat {
        max(cornerRadius - 5, 10)
    }

    private var screenContentInsets: EdgeInsets {
        switch kind {
        case .pad:
            return EdgeInsets(top: 9, leading: 12, bottom: 0, trailing: 12)
        case .phone:
            return EdgeInsets(top: 18, leading: 9, bottom: 0, trailing: 9)
        }
    }

    private var rowSpacing: CGFloat {
        switch kind {
        case .pad:
            return 7
        case .phone:
            return 5
        }
    }

    private var screen: some View {
        RoundedRectangle(cornerRadius: screenCornerRadius, style: .continuous)
            .fill(AppTheme.pageGradient)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: rowSpacing) {
                    ForEach(0..<rowCount, id: \.self) { index in
                        SettingsICloudSyncGuideMiniRow(index: index, isCompact: kind == .phone)
                    }
                }
                .padding(screenContentInsets)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .clipShape(RoundedRectangle(cornerRadius: screenCornerRadius, style: .continuous))
    }

    private var rowCount: Int {
        switch kind {
        case .pad:
            return 4
        case .phone:
            return 5
        }
    }
}

private struct SettingsICloudSyncGuideMiniRow: View {
    let index: Int
    let isCompact: Bool

    private var iconColor: Color {
        let colors = [AppTheme.sky, AppTheme.leaf, AppTheme.gold, AppTheme.aiPurple]
        return colors[index % colors.count]
    }

    var body: some View {
        HStack(spacing: isCompact ? 5 : 7) {
            RoundedRectangle(cornerRadius: isCompact ? 5 : 6, style: .continuous)
                .fill(iconColor.opacity(0.88))
                .frame(width: isCompact ? 15 : 17, height: isCompact ? 15 : 17)

            VStack(alignment: .leading, spacing: isCompact ? 3 : 4) {
                Capsule()
                    .fill(AppTheme.contentPrimary.opacity(0.56))
                    .frame(width: isCompact ? 28 : 74, height: isCompact ? 4 : 5)
                Capsule()
                    .fill(AppTheme.textSecondary.opacity(0.36))
                    .frame(width: isCompact ? 20 : 48, height: isCompact ? 3 : 4)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, isCompact ? 6 : 8)
        .padding(.vertical, isCompact ? 5 : 5)
        .background(
            AppTheme.surfaceStrong.opacity(0.86),
            in: RoundedRectangle(cornerRadius: isCompact ? 9 : 11, style: .continuous)
        )
    }
}

private struct SettingsProjectWidgetIllustration: View {
    @State private var activeWidgetSampleIndex = 0

    var body: some View {
        GeometryReader { proxy in
            if UIDevice.current.userInterfaceIdiom == .pad {
                let iPadWidth = min(proxy.size.width, IPadMetrics.maxWidth)
                let scale = iPadWidth / IPadMetrics.visibleSourceWidth * IPadMetrics.renderScale
                let visibleHeight = min(proxy.size.height, IPadMetrics.visibleSourceHeight * scale)

                iPadScreen(width: iPadWidth, visibleHeight: visibleHeight, scale: scale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let phoneWidth = min(proxy.size.width, Metrics.maxPhoneWidth)
                let scale = phoneWidth / Metrics.sourceWidth
                let visibleHeight = min(proxy.size.height, Metrics.visibleSourceHeight * scale)

                phoneScreen(width: phoneWidth, visibleHeight: visibleHeight, scale: scale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .aspectRatio(
            UIDevice.current.userInterfaceIdiom == .pad ? IPadMetrics.visibleAspectRatio : Metrics.visibleAspectRatio,
            contentMode: .fit
        )
        .task {
            await rotateWidgetSamples()
        }
        .accessibilityHidden(true)
    }

    private func guideWidgetPreview(side: CGFloat) -> some View {
        let widgetCornerRadius = side * 0.146
        let activeSampleID = Self.widgetSamples[activeWidgetSampleIndex].id

        return ZStack {
            ForEach(Self.widgetSamples) { sample in
                let isActive = sample.id == activeSampleID

                ZStack(alignment: .bottom) {
                    guideWidgetImage(sample.imageAssetName, side: side)
                    guideWidgetTitleFade(side: side)
                    guideWidgetTitle(AppStrings.localized(sample.titleKey), side: side)
                }
                .opacity(isActive ? 1 : 0)
                .scaleEffect(isActive ? 1 : 1.045)
                .offset(y: isActive ? 0 : side * 0.025)
                .zIndex(isActive ? 1 : 0)
                .animation(.easeInOut(duration: 0.78), value: activeSampleID)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: widgetCornerRadius, style: .continuous))
    }

    private func guideWidgetImage(_ assetName: String, side: CGFloat) -> some View {
        Image(assetName)
            .resizable()
            .scaledToFill()
            .frame(width: side, height: side)
            .scaleEffect(1.06)
            .clipped()
    }

    private func rotateWidgetSamples() async {
        try? await Task.sleep(nanoseconds: 500_000_000)
        if Task.isCancelled { return }
        await MainActor.run {
            advanceWidgetSample()
        }

        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if Task.isCancelled { return }
            await MainActor.run {
                advanceWidgetSample()
            }
        }
    }

    private func advanceWidgetSample() {
        withAnimation(.easeInOut(duration: 0.78)) {
            activeWidgetSampleIndex = (activeWidgetSampleIndex + 1) % Self.widgetSamples.count
        }
    }

    private struct WidgetSample: Identifiable {
        let id: Int
        let imageAssetName: String
        let titleKey: String
    }

    private static let widgetSamples: [WidgetSample] = [
        WidgetSample(id: 0, imageAssetName: "ProjectWidgetGuidePinyinTrain", titleKey: "字母小火车"),
        WidgetSample(id: 1, imageAssetName: "ProjectWidgetGuideMultiplicationPlanet", titleKey: "数字星球"),
        WidgetSample(id: 2, imageAssetName: "ProjectWidgetGuideDinoClock", titleKey: "恐龙时钟"),
        WidgetSample(id: 3, imageAssetName: "ProjectWidgetGuideStoryBox", titleKey: "睡前故事盒")
    ]

    private func guideWidgetTitleFade(side: CGFloat) -> some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black.opacity(0.13), location: 0.46),
                .init(color: .black.opacity(0.46), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: side * 0.35)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    private func guideWidgetTitle(_ title: String, side: CGFloat) -> some View {
        Text(title)
            .font(.system(size: min(13.5, max(10.5, side * 0.082)), weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.82)
            .shadow(color: .black.opacity(0.38), radius: 0.28, x: 0, y: 0.5)
            .shadow(color: .black.opacity(0.30), radius: 1.25, x: 0, y: 0.95)
            .shadow(color: .black.opacity(0.20), radius: 3.2, x: 0, y: 1.8)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, side * 0.073)
            .padding(.bottom, side * 0.055)
    }

    private func phoneScreen(width: CGFloat, visibleHeight: CGFloat, scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Image("ProjectWidgetGuideWallpaper")
                .resizable()
                .interpolation(.high)
                .frame(width: width, height: Metrics.sourceHeight * scale, alignment: .top)

            statusBar(scale: scale)

            guideWidgetPreview(side: Metrics.widgetFrame.width * scale)
                .position(
                    x: Metrics.widgetFrame.midX * scale,
                    y: Metrics.widgetFrame.midY * scale
                )

            homeScreenLabel(AppStrings.localized("app.displayName"), scale: scale)
                .position(
                    x: Metrics.widgetFrame.midX * scale,
                    y: Metrics.widgetTitleY * scale
                )

            ForEach(Self.homeApps) { app in
                ProjectWidgetGuideHomeIcon(
                    iconAssetName: app.iconAssetName,
                    titleKey: app.titleKey,
                    scale: scale
                )
                .position(
                    x: (app.frame.minX + Metrics.appSlotSize.width / 2) * scale,
                    y: (app.frame.minY + Metrics.appSlotSize.height / 2) * scale
                )
            }

            ProjectWidgetGuideHomeIcon(
                iconAssetName: "ProjectWidgetGuideAppIcon",
                titleKey: "app.displayName",
                scale: scale,
                clipsIconToAppShape: true
            )
            .position(
                x: (Metrics.ownAppFrame.minX + Metrics.appSlotSize.width / 2) * scale,
                y: (Metrics.ownAppFrame.minY + Metrics.appSlotSize.height / 2) * scale
            )

            widgetFocusCue(
                widgetFrame: Metrics.widgetFrame,
                sourceSize: CGSize(width: Metrics.sourceWidth, height: Metrics.sourceHeight),
                scale: scale
            )

            searchField(scale: scale)
                .position(
                    x: Metrics.searchField.midX * scale,
                    y: Metrics.searchField.midY * scale
                )

            Image("ProjectWidgetGuideDock")
                .resizable()
                .interpolation(.high)
                .frame(
                    width: Metrics.dockFrame.width * scale,
                    height: Metrics.dockFrame.height * scale
                )
                .position(
                    x: Metrics.dockFrame.midX * scale,
                    y: Metrics.dockFrame.midY * scale
                )
        }
        .frame(width: width, height: visibleHeight, alignment: .topLeading)
        .compositingGroup()
        .clipShape(
            RoundedRectangle(
                cornerRadius: Metrics.screenCornerRadiusRatio * width,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: Metrics.screenCornerRadiusRatio * width,
                style: .continuous
            )
            .stroke(Color.white.opacity(0.45), lineWidth: 1)
        }
        .shadow(color: AppTheme.surfaceShadow.opacity(0.5), radius: 12, x: 0, y: 7)
    }

    private func iPadScreen(width: CGFloat, visibleHeight: CGFloat, scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Image("ProjectWidgetGuideIPadWallpaper")
                .resizable()
                .interpolation(.high)
                .frame(width: IPadMetrics.sourceWidth * scale, height: IPadMetrics.sourceHeight * scale, alignment: .top)

            iPadStatusBar(scale: scale)

            guideWidgetPreview(side: IPadMetrics.widgetFrame.width * scale)
                .position(
                    x: IPadMetrics.widgetFrame.midX * scale,
                    y: IPadMetrics.widgetFrame.midY * scale
                )

            ForEach(Self.iPadApps) { app in
                ProjectWidgetGuideIPadHomeIcon(
                    iconAssetName: app.iconAssetName,
                    titleKey: app.titleKey,
                    scale: scale,
                    clipsIconToAppShape: app.clipsIconToAppShape
                )
                .position(
                    x: (app.frame.minX + IPadMetrics.appSlotSize.width / 2) * scale,
                    y: (IPadMetrics.appIconsOriginY + app.frame.minY + IPadMetrics.appSlotSize.height / 2) * scale
                )
            }

            widgetFocusCue(
                widgetFrame: IPadMetrics.widgetFrame,
                sourceSize: CGSize(width: IPadMetrics.sourceWidth, height: IPadMetrics.sourceHeight),
                scale: scale
            )

            pageControl(scale: scale)
                .position(
                    x: IPadMetrics.pageControlFrame.midX * scale,
                    y: IPadMetrics.pageControlFrame.midY * scale
                )
        }
        .frame(width: width, height: visibleHeight, alignment: .topLeading)
        .compositingGroup()
        .clipShape(
            RoundedRectangle(
                cornerRadius: IPadMetrics.screenCornerRadiusRatio * width,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: IPadMetrics.screenCornerRadiusRatio * width,
                style: .continuous
            )
            .stroke(Color.white.opacity(0.42), lineWidth: 1)
        }
        .shadow(color: AppTheme.surfaceShadow.opacity(0.45), radius: 12, x: 0, y: 7)
    }

    private func statusBar(scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Text("9:41")
                .font(.system(size: 17 * scale, weight: .semibold))
                .foregroundStyle(Color.white)
                .shadow(color: Color.black.opacity(0.18), radius: 2 * scale, x: 0, y: 1 * scale)
                .position(x: 75 * scale, y: 31 * scale)

            HStack(spacing: 6 * scale) {
                Image(systemName: "cellularbars")
                    .font(.system(size: 15 * scale, weight: .semibold))
                Image(systemName: "wifi")
                    .font(.system(size: 14 * scale, weight: .semibold))
                batteryIcon(scale: scale)
            }
            .foregroundStyle(Color.white)
            .shadow(color: Color.black.opacity(0.16), radius: 2 * scale, x: 0, y: 1 * scale)
            .flipsForRightToLeftLayoutDirection(false)
            .position(x: 325 * scale, y: 31 * scale)
        }
        .frame(width: Metrics.sourceWidth * scale, height: Metrics.statusBarHeight * scale, alignment: .topLeading)
    }

    private func iPadStatusBar(scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 8 * scale) {
                Text("9:41")
                Text("Tue Apr 1")
            }
            .font(.system(size: 12 * scale, weight: .medium))
            .foregroundStyle(Color.white)
            .shadow(color: Color.black.opacity(0.16), radius: 2 * scale, x: 0, y: 1 * scale)
            .position(x: 68 * scale, y: 16 * scale)

            HStack(spacing: 4 * scale) {
                Image(systemName: "cellularbars")
                    .font(.system(size: 11 * scale, weight: .semibold))
                Image(systemName: "wifi")
                    .font(.system(size: 10 * scale, weight: .semibold))
                Text("100%")
                    .font(.system(size: 12 * scale, weight: .medium))
                batteryIcon(scale: scale * 0.86)
            }
            .foregroundStyle(Color.white)
            .shadow(color: Color.black.opacity(0.16), radius: 2 * scale, x: 0, y: 1 * scale)
            .flipsForRightToLeftLayoutDirection(false)
            .position(x: 1136 * scale, y: 16 * scale)
        }
        .frame(width: IPadMetrics.sourceWidth * scale, height: IPadMetrics.statusBarHeight * scale, alignment: .topLeading)
    }

    private func batteryIcon(scale: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3 * scale, style: .continuous)
                .stroke(Color.white.opacity(0.86), lineWidth: 1.2 * scale)
                .frame(width: 24 * scale, height: 12 * scale)

            RoundedRectangle(cornerRadius: 1.5 * scale, style: .continuous)
                .fill(Color.white.opacity(0.92))
                .frame(width: 18 * scale, height: 8 * scale)
                .padding(.leading, 2 * scale)

            RoundedRectangle(cornerRadius: 1 * scale, style: .continuous)
                .fill(Color.white.opacity(0.82))
                .frame(width: 2.4 * scale, height: 5 * scale)
                .offset(x: 25 * scale)
        }
        .frame(width: 28 * scale, height: 14 * scale)
    }

    private func searchField(scale: CGFloat) -> some View {
        HStack(spacing: 4 * scale) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10 * scale, weight: .semibold))
            Text(AppStrings.localized("guide.homeScreen.search"))
                .font(.system(size: 12 * scale, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 12 * scale)
        .frame(width: Metrics.searchField.width * scale, height: Metrics.searchField.height * scale)
        .background(Color.white.opacity(0.18), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.22), lineWidth: max(0.5, scale))
        }
        .shadow(color: Color.black.opacity(0.12), radius: 4 * scale, x: 0, y: 2 * scale)
    }

    private func homeScreenLabel(_ title: String, scale: CGFloat) -> some View {
        ProjectWidgetGuideHomeLabel(
            title: title,
            iconWidth: Metrics.iconSize.width * scale,
            width: Metrics.appLabelWidth * scale
        )
    }

    private func widgetFocusCue(widgetFrame: CGRect, sourceSize: CGSize, scale: CGFloat) -> some View {
        let markerWidth = widgetFrame.width * (36.0 / 164.0) * scale
        let markerHeight = widgetFrame.width * (44.0 / 164.0) * scale
        let arrowWidth = widgetFrame.width * (84.0 / 164.0) * scale
        let arrowHeight = widgetFrame.width * (70.0 / 164.0) * scale
        let markerHorizontalOffset = widgetFrame.width * (6.666873931884766 / 164.0)
        let markerVerticalOffset = widgetFrame.width * (1.0 / 164.0)

        return ZStack(alignment: .topLeading) {
            focusImage("ProjectWidgetGuideFocusMarkerLeft")
                .frame(width: markerWidth, height: markerHeight)
                .position(
                    x: (widgetFrame.minX - markerHorizontalOffset) * scale,
                    y: (widgetFrame.minY - markerVerticalOffset) * scale
                )

            focusImage("ProjectWidgetGuideFocusMarkerLeft")
                .scaleEffect(x: -1, y: 1)
                .frame(width: markerWidth, height: markerHeight)
                .position(
                    x: (widgetFrame.maxX + markerHorizontalOffset) * scale,
                    y: (widgetFrame.minY - markerVerticalOffset) * scale
                )

            focusImage("ProjectWidgetGuideFocusArrow")
                .frame(width: arrowWidth, height: arrowHeight)
                .position(
                    x: (widgetFrame.minX + widgetFrame.width * (197.3331413269043 / 164.0)) * scale,
                    y: (widgetFrame.minY + widgetFrame.width * (182.0 / 164.0)) * scale
                )
        }
        .frame(width: sourceSize.width * scale, height: sourceSize.height * scale, alignment: .topLeading)
    }

    private func focusImage(_ assetName: String) -> some View {
        Image(assetName)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
    }

    private func pageControl(scale: CGFloat) -> some View {
        HStack(spacing: 10 * scale) {
            Circle()
                .fill(Color.white.opacity(0.95))
                .frame(width: 7 * scale, height: 7 * scale)

            Circle()
                .fill(Color.white.opacity(0.3))
                .frame(width: 7 * scale, height: 7 * scale)
        }
        .padding(.horizontal, 12 * scale)
        .frame(width: IPadMetrics.pageControlFrame.width * scale, height: IPadMetrics.pageControlFrame.height * scale)
    }

    private struct HomeApp: Identifiable {
        let id = UUID()
        let iconAssetName: String
        let titleKey: String
        let frame: CGRect

        init(iconAssetName: String, titleKey: String, x: CGFloat, y: CGFloat) {
            self.iconAssetName = iconAssetName
            self.titleKey = titleKey
            frame = CGRect(origin: CGPoint(x: x, y: y), size: Metrics.appSlotSize)
        }
    }

    private struct IPadApp: Identifiable {
        let id = UUID()
        let iconAssetName: String
        let titleKey: String
        let frame: CGRect
        var clipsIconToAppShape = false

        init(
            iconAssetName: String,
            titleKey: String,
            x: CGFloat,
            y: CGFloat,
            clipsIconToAppShape: Bool = false
        ) {
            self.iconAssetName = iconAssetName
            self.titleKey = titleKey
            self.clipsIconToAppShape = clipsIconToAppShape
            frame = CGRect(origin: CGPoint(x: x, y: y), size: IPadMetrics.appSlotSize)
        }
    }

    private struct ProjectWidgetGuideHomeIcon: View {
        let iconAssetName: String
        let titleKey: String
        let scale: CGFloat
        var clipsIconToAppShape = false

        var body: some View {
            VStack(spacing: 7 * scale) {
                Image(iconAssetName)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: Metrics.iconSize.width * scale, height: Metrics.iconSize.height * scale)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: (clipsIconToAppShape ? Metrics.appIconCornerRadius : 0) * scale,
                            style: .continuous
                        )
                    )

                ProjectWidgetGuideHomeLabel(
                    title: AppStrings.localized(titleKey),
                    iconWidth: Metrics.iconSize.width * scale,
                    width: Metrics.appLabelWidth * scale
                )
            }
            .frame(width: Metrics.appSlotSize.width * scale, height: Metrics.appSlotSize.height * scale)
        }
    }

    private struct ProjectWidgetGuideIPadHomeIcon: View {
        let iconAssetName: String
        let titleKey: String
        let scale: CGFloat
        var clipsIconToAppShape = false

        var body: some View {
            VStack(spacing: 8.5 * scale) {
                Image(iconAssetName)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: IPadMetrics.iconSize.width * scale, height: IPadMetrics.iconSize.height * scale)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: (clipsIconToAppShape ? IPadMetrics.appIconCornerRadius : 0) * scale,
                            style: .continuous
                        )
                    )

                ProjectWidgetGuideHomeLabel(
                    title: AppStrings.localized(titleKey),
                    iconWidth: IPadMetrics.iconSize.width * scale,
                    width: IPadMetrics.appLabelWidth * scale
                )
            }
            .frame(width: IPadMetrics.appSlotSize.width * scale, height: IPadMetrics.appSlotSize.height * scale)
        }
    }

    private struct ProjectWidgetGuideHomeLabel: View {
        let title: String
        let iconWidth: CGFloat
        let width: CGFloat

        var body: some View {
            let labelScale = iconWidth / 68

            Text(title)
                .font(.system(size: 12 * labelScale, weight: .medium))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .multilineTextAlignment(.center)
                .frame(width: width)
                .shadow(color: Color.black.opacity(0.28), radius: 2 * labelScale, x: 0, y: 1 * labelScale)
        }
    }

    private enum Metrics {
        static let sourceWidth: CGFloat = 402
        static let sourceHeight: CGFloat = 874
        static let visibleSourceHeight: CGFloat = 386
        static let visibleAspectRatio: CGFloat = sourceWidth / visibleSourceHeight
        static let maxPhoneWidth: CGFloat = 402
        static let screenCornerRadiusRatio: CGFloat = 0.089
        static let statusBarHeight: CGFloat = 62
        static let widgetFrame = CGRect(x: 26.667, y: 90, width: 164, height: 164)
        static let widgetTitleY: CGFloat = 268
        static let appSlotSize = CGSize(width: 72, height: 83)
        static let appLabelWidth: CGFloat = 88
        static let iconSize = CGSize(width: 64, height: 64)
        static let ownAppFrame = CGRect(origin: CGPoint(x: 211.333, y: 90), size: appSlotSize)
        static let appIconCornerRadius: CGFloat = 14
        static let searchField = CGRect(x: 162.5, y: 704, width: 77, height: 30)
        static let dockFrame = CGRect(x: 0, y: 704, width: 402, height: 176)
    }

    private enum IPadMetrics {
        static let sourceWidth: CGFloat = 1210
        static let sourceHeight: CGFloat = 834
        static let visibleSourceWidth: CGFloat = 680
        static let visibleSourceHeight: CGFloat = 367
        static let renderScale: CGFloat = 0.9
        static let visibleAspectRatio: CGFloat = visibleSourceWidth / (visibleSourceHeight * renderScale)
        static let maxWidth: CGFloat = 720
        static let screenCornerRadiusRatio: CGFloat = 0.03
        static let statusBarHeight: CGFloat = 32
        static let appIconsOriginY: CGFloat = 32
        static let widgetFrame = CGRect(x: 125, y: 46, width: 138, height: 138)
        static let appSlotSize = CGSize(width: 146, height: 90.5)
        static let appLabelWidth: CGFloat = 132
        static let iconSize = CGSize(width: 68, height: 68)
        static let appIconCornerRadius: CGFloat = 15
        static let pageControlFrame = CGRect(x: 581, y: 827, width: 48, height: 7)
    }

    private static let homeApps: [HomeApp] = [
        HomeApp(iconAssetName: "ProjectWidgetGuideIconCalendar", titleKey: "guide.homeScreen.calendar", x: 304, y: 90),
        HomeApp(iconAssetName: "ProjectWidgetGuideIconPhotos", titleKey: "guide.homeScreen.photos", x: 211.333, y: 190),
        HomeApp(iconAssetName: "ProjectWidgetGuideIconCamera", titleKey: "guide.homeScreen.camera", x: 304, y: 190),
        HomeApp(iconAssetName: "ProjectWidgetGuideIconMail", titleKey: "guide.homeScreen.mail", x: 26, y: 290),
        HomeApp(iconAssetName: "ProjectWidgetGuideIconNotes", titleKey: "guide.homeScreen.notes", x: 118.667, y: 290),
        HomeApp(iconAssetName: "ProjectWidgetGuideIconReminders", titleKey: "guide.homeScreen.reminders", x: 211.333, y: 290),
        HomeApp(iconAssetName: "ProjectWidgetGuideIconClock", titleKey: "guide.homeScreen.clock", x: 304, y: 290),
        HomeApp(iconAssetName: "ProjectWidgetGuideIconNews", titleKey: "guide.homeScreen.news", x: 26, y: 390),
        HomeApp(iconAssetName: "ProjectWidgetGuideIconTV", titleKey: "guide.homeScreen.tv", x: 118.667, y: 390),
        HomeApp(iconAssetName: "ProjectWidgetGuideIconGames", titleKey: "guide.homeScreen.games", x: 211.333, y: 390),
        HomeApp(iconAssetName: "ProjectWidgetGuideIconAppStore", titleKey: "guide.homeScreen.appStore", x: 304, y: 390),
        HomeApp(iconAssetName: "ProjectWidgetGuideIconMaps", titleKey: "guide.homeScreen.maps", x: 26, y: 490),
        HomeApp(iconAssetName: "ProjectWidgetGuideIconHealth", titleKey: "guide.homeScreen.health", x: 118.667, y: 490),
        HomeApp(iconAssetName: "ProjectWidgetGuideIconWallet", titleKey: "guide.homeScreen.wallet", x: 211.333, y: 490),
        HomeApp(iconAssetName: "ProjectWidgetGuideIconSettings", titleKey: "guide.homeScreen.settings", x: 304, y: 490)
    ]

    private static let iPadApps: [IPadApp] = [
        IPadApp(
            iconAssetName: "ProjectWidgetGuideAppIcon",
            titleKey: "app.displayName",
            x: 287.2,
            y: 50,
            clipsIconToAppShape: true
        ),
        IPadApp(iconAssetName: "ProjectWidgetGuideIconPhotos", titleKey: "guide.homeScreen.photos", x: 450.4, y: 50),
        IPadApp(iconAssetName: "ProjectWidgetGuideIconCamera", titleKey: "guide.homeScreen.camera", x: 613.6, y: 50),
        IPadApp(iconAssetName: "ProjectWidgetGuideIconMaps", titleKey: "guide.homeScreen.maps", x: 776.8, y: 50),
        IPadApp(iconAssetName: "ProjectWidgetGuideIconSettings", titleKey: "guide.homeScreen.settings", x: 940, y: 50),
        IPadApp(iconAssetName: "ProjectWidgetGuideIconMail", titleKey: "guide.homeScreen.mail", x: 124, y: 216.5),
        IPadApp(iconAssetName: "ProjectWidgetGuideIconAppStore", titleKey: "guide.homeScreen.appStore", x: 287.2, y: 216.5),
        IPadApp(iconAssetName: "ProjectWidgetGuideIconNotes", titleKey: "guide.homeScreen.notes", x: 450.4, y: 216.5),
        IPadApp(iconAssetName: "ProjectWidgetGuideIconGames", titleKey: "guide.homeScreen.games", x: 613.6, y: 216.5),
        IPadApp(iconAssetName: "ProjectWidgetGuideIconTV", titleKey: "guide.homeScreen.tv", x: 776.8, y: 216.5),
        IPadApp(iconAssetName: "ProjectWidgetGuideIconNews", titleKey: "guide.homeScreen.news", x: 940, y: 216.5)
    ]
}

private struct SettingsProjectWidgetStepRow: View {
    let index: Int
    let textKey: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(AppTheme.deepWater, in: Circle())

            Text(AppStrings.localized(textKey))
                .font(.system(size: 15))
                .foregroundStyle(AppTheme.contentPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}

private struct SettingsPreferenceOption: Identifiable {
    let rawValue: String
    let titleKey: String

    var id: String { rawValue }
}

private struct SettingsPreferenceSelectionView: View {
    let titleKey: String
    let options: [SettingsPreferenceOption]
    @Binding var selectionRawValue: String
    let containerStyle: SettingsContainerStyle

    var body: some View {
        styledSelectionList
        .navigationTitle(AppStrings.localized(titleKey))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var styledSelectionList: some View {
        switch containerStyle {
        case .appBackground:
            ZStack {
                AppPageBackground()
                selectionList
                    .scrollContentBackground(.hidden)
            }
        case .systemPopover:
            selectionList
        }
    }

    private var selectionList: some View {
        List {
            Section {
                ForEach(options) { option in
                    Button {
                        selectionRawValue = option.rawValue
                    } label: {
                        SettingsPreferenceOptionRow(
                            title: AppStrings.localized(option.titleKey),
                            isSelected: option.rawValue == selectionRawValue
                        )
                    }
                    .buttonStyle(.plain)
                    .settingsListRowSurface()
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

private struct SettingsPreferenceOptionRow: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 17))
                .foregroundStyle(AppTheme.listItemTitle)
                .lineLimit(1)

            Spacer(minLength: 12)

            if isSelected {
                Image(systemName: "checkmark")
                    .flipsForRightToLeftLayoutDirection(false)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.deepWater)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct SettingsSupportShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {
    }
}

private struct SettingsVersionFooter: View {
    @Environment(\.colorScheme) private var colorScheme

    let version: String
    let build: String

    @Binding var isExpertModeEnabled: Bool

    init(version: String, build: String, isExpertModeEnabled: Binding<Bool>) {
        self.version = version
        self.build = build
        _isExpertModeEnabled = isExpertModeEnabled
    }

    var body: some View {
        VStack(spacing: 0) {
            Image("BrandLogoSticker")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)

            OutlinedText(
                versionText,
                font: SettingsVersionFooterPalette.font,
                fillColor: palette.text,
                strokeColor: palette.outline,
                outerStrokeWidth: 2,
                shadow: .init(
                    color: palette.textShadow,
                    offset: CGSize(width: 0, height: 1)
                )
            )
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            isExpertModeEnabled.toggle()
        }
        .accessibilityAction(named: isExpertModeEnabled ? AppStrings.localized("关闭专家模式") : AppStrings.localized("开启专家模式")) {
            isExpertModeEnabled.toggle()
        }
    }

    private var versionText: String {
        if isExpertModeEnabled {
            return "Ver \(version) (\(build))"
        }

        return "Ver \(version)"
    }

    private var palette: SettingsVersionFooterPalette {
        colorScheme == .dark ? .dark : .light
    }
}

private struct SettingsVersionFooterPalette {
    let text: Color
    let textShadow: Color
    let outline: Color

    static let light = SettingsVersionFooterPalette(
        text: Color(red: 0.39, green: 0.47, blue: 0.62),
        textShadow: Color(red: 0.83, green: 0.85, blue: 0.88),
        outline: .white
    )

    static let dark = SettingsVersionFooterPalette(
        text: Color(red: 0.78, green: 0.84, blue: 0.96),
        textShadow: Color(red: 0.03, green: 0.05, blue: 0.09).opacity(0.78),
        outline: Color(red: 0.16, green: 0.21, blue: 0.31)
    )

    static let font: UIFont = UIFont(name: "YeYa-Bold", size: 14)
        ?? UIFont.systemFont(ofSize: 14, weight: .semibold)
}

private struct OutlinedText: View {
    struct Shadow {
        let color: Color
        let offset: CGSize
        let blurRadius: CGFloat

        init(color: Color, offset: CGSize, blurRadius: CGFloat = 0) {
            self.color = color
            self.offset = offset
            self.blurRadius = blurRadius
        }
    }

    let text: String
    let font: UIFont
    let fillColor: Color
    let strokeColor: Color
    let outerStrokeWidth: CGFloat
    let shadow: Shadow?

    init(
        _ text: String,
        font: UIFont,
        fillColor: Color,
        strokeColor: Color = .white,
        outerStrokeWidth: CGFloat = 2,
        shadow: Shadow? = nil
    ) {
        self.text = text
        self.font = font
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        self.outerStrokeWidth = outerStrokeWidth
        self.shadow = shadow
    }

    var body: some View {
        ZStack {
            OutlinedTextLabel(attributedText: outlineAttributedText, horizontalInset: horizontalDrawingInset)
                .accessibilityHidden(true)

            OutlinedTextLabel(attributedText: fillAttributedText, horizontalInset: horizontalDrawingInset)
        }
    }

    private var horizontalDrawingInset: CGFloat {
        let shadowInset = abs(shadow?.offset.width ?? 0) + (shadow?.blurRadius ?? 0)
        return ceil(outerStrokeWidth + shadowInset + 2)
    }

    private var outlineAttributedText: NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor(strokeColor),
            .strokeColor: UIColor(strokeColor),
            .strokeWidth: -(outerStrokeWidth * 2) / font.pointSize * 100
        ]

        if let shadow {
            let nsShadow = NSShadow()
            nsShadow.shadowColor = UIColor(shadow.color)
            nsShadow.shadowOffset = shadow.offset
            nsShadow.shadowBlurRadius = shadow.blurRadius
            attributes[.shadow] = nsShadow
        }

        return NSAttributedString(string: text, attributes: attributes)
    }

    private var fillAttributedText: NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: UIColor(fillColor)
            ]
        )
    }
}

private struct OutlinedTextLabel: UIViewRepresentable {
    let attributedText: NSAttributedString
    let horizontalInset: CGFloat

    func makeUIView(context _: Context) -> OutlinedTextInsetLabel {
        let label = OutlinedTextInsetLabel()
        label.backgroundColor = .clear
        label.textAlignment = .center
        label.numberOfLines = 1
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }

    func updateUIView(_ label: OutlinedTextInsetLabel, context _: Context) {
        label.attributedText = attributedText
        label.horizontalTextInset = horizontalInset
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: OutlinedTextInsetLabel, context _: Context) -> CGSize? {
        let measuredSize = uiView.sizeThatFits(CGSize(
            width: proposal.width ?? .greatestFiniteMagnitude,
            height: proposal.height ?? .greatestFiniteMagnitude
        ))
        return CGSize(
            width: measuredSize.width + horizontalInset * 2,
            height: measuredSize.height
        )
    }
}

private final class OutlinedTextInsetLabel: UILabel {
    var horizontalTextInset: CGFloat = 0 {
        didSet {
            invalidateIntrinsicContentSize()
            setNeedsDisplay()
        }
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + horizontalTextInset * 2, height: size.height)
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.insetBy(dx: horizontalTextInset, dy: 0))
    }

    override func textRect(forBounds bounds: CGRect, limitedToNumberOfLines numberOfLines: Int) -> CGRect {
        let insetBounds = bounds.insetBy(dx: horizontalTextInset, dy: 0)
        let rect = super.textRect(forBounds: insetBounds, limitedToNumberOfLines: numberOfLines)
        return rect.insetBy(dx: -horizontalTextInset, dy: 0)
    }
}
