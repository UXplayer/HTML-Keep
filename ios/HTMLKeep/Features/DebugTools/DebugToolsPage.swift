import SwiftUI

struct DebugFloatingBallPositionStore {
    private static let storedCenterXKey = "debug_floating_ball_x"
    private static let storedCenterYKey = "debug_floating_ball_y"

    func reset() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.storedCenterXKey)
        defaults.removeObject(forKey: Self.storedCenterYKey)
    }

    static var centerXKey: String { Self.storedCenterXKey }
    static var centerYKey: String { Self.storedCenterYKey }
}

struct DebugFloatingBallVisibilityPreferenceStore {
    private static let floatingBallVisibleKey = "debug_floating_ball_visible"

    func isFloatingBallVisible() -> Bool {
        guard AppBuildFlavor.current.isTestingBuild else {
            return false
        }

        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Self.floatingBallVisibleKey) != nil else {
            return true
        }

        return defaults.bool(forKey: Self.floatingBallVisibleKey)
    }

    func setFloatingBallVisible(_ isVisible: Bool) {
        UserDefaults.standard.set(isVisible, forKey: Self.floatingBallVisibleKey)
    }
}

@MainActor
final class DebugFloatingBallVisibilityStore: ObservableObject {
    @Published private(set) var isVisible: Bool

    private let preferenceStore = DebugFloatingBallVisibilityPreferenceStore()

    init() {
        isVisible = preferenceStore.isFloatingBallVisible()
    }

    func setVisible(_ isVisible: Bool) {
        preferenceStore.setFloatingBallVisible(isVisible)
        self.isVisible = preferenceStore.isFloatingBallVisible()
    }
}

struct DebugICloudSyncSnapshot: Equatable {
    let access: ICloudWebPageSyncAccess
    let isUserPreferenceEnabled: Bool
    let isServiceCreated: Bool
    let latestRecord: ICloudWebPageSyncUserRecord?
    let presenceLines: [String]
}

private enum DebugColorPalette {
    static let background = Color(red: 1.0, green: 243.0 / 255.0, blue: 249.0 / 255.0)
    static let surface = Color(red: 1.0, green: 249.0 / 255.0, blue: 252.0 / 255.0)
    static let surfaceEmphasis = Color(red: 1.0, green: 236.0 / 255.0, blue: 245.0 / 255.0)
    static let border = Color(red: 248.0 / 255.0, green: 210.0 / 255.0, blue: 229.0 / 255.0)
    static let fill = Color(red: 244.0 / 255.0, green: 116.0 / 255.0, blue: 181.0 / 255.0)
    static let fillStrong = Color(red: 224.0 / 255.0, green: 76.0 / 255.0, blue: 151.0 / 255.0)
    static let primaryText = Color(red: 153.0 / 255.0, green: 37.0 / 255.0, blue: 98.0 / 255.0)
    static let secondaryText = Color(red: 188.0 / 255.0, green: 106.0 / 255.0, blue: 145.0 / 255.0)
    static let shadow = Color(red: 153.0 / 255.0, green: 37.0 / 255.0, blue: 98.0 / 255.0, opacity: 0.16)
    static let positive = Color(red: 194.0 / 255.0, green: 59.0 / 255.0, blue: 128.0 / 255.0)
}

private struct DebugFloatingOverlayModifier: ViewModifier {
    @ObservedObject var proEntitlementStore: ProEntitlementStore
    @ObservedObject var visibilityStore: DebugFloatingBallVisibilityStore
    let iCloudSyncDebugSnapshot: DebugICloudSyncSnapshot
    let onRunICloudSyncTest: () async -> ICloudWebPageSyncDebugResult
    let onResetICloudSyncEnvironment: () async -> ICloudWebPageSyncDebugResult

    func body(content: Content) -> some View {
        if AppBuildFlavor.current.isTestingBuild {
            content.overlay {
                if visibilityStore.isVisible {
                    DebugFloatingToolsHost(
                        proEntitlementStore: proEntitlementStore,
                        iCloudSyncDebugSnapshot: iCloudSyncDebugSnapshot,
                        onRunICloudSyncTest: onRunICloudSyncTest,
                        onResetICloudSyncEnvironment: onResetICloudSyncEnvironment
                    )
                }
            }
        } else {
            content
        }
    }
}

extension View {
    func debugFloatingToolsOverlay(
        proEntitlementStore: ProEntitlementStore,
        visibilityStore: DebugFloatingBallVisibilityStore,
        iCloudSyncDebugSnapshot: DebugICloudSyncSnapshot,
        onRunICloudSyncTest: @escaping () async -> ICloudWebPageSyncDebugResult,
        onResetICloudSyncEnvironment: @escaping () async -> ICloudWebPageSyncDebugResult
    ) -> some View {
        modifier(
            DebugFloatingOverlayModifier(
                proEntitlementStore: proEntitlementStore,
                visibilityStore: visibilityStore,
                iCloudSyncDebugSnapshot: iCloudSyncDebugSnapshot,
                onRunICloudSyncTest: onRunICloudSyncTest,
                onResetICloudSyncEnvironment: onResetICloudSyncEnvironment
            )
        )
    }
}

private struct DebugFloatingToolsHost: View {
    @AppStorage(DebugFloatingBallPositionStore.centerXKey) private var storedCenterX = -1.0
    @AppStorage(DebugFloatingBallPositionStore.centerYKey) private var storedCenterY = -1.0
    @ObservedObject var proEntitlementStore: ProEntitlementStore
    let iCloudSyncDebugSnapshot: DebugICloudSyncSnapshot
    let onRunICloudSyncTest: () async -> ICloudWebPageSyncDebugResult
    let onResetICloudSyncEnvironment: () async -> ICloudWebPageSyncDebugResult
    @State private var dragOffset: CGSize = .zero
    @State private var isShowingDebugSheet = false
    @State private var debugSheetDetent: PresentationDetent = .large
    @State private var isDragging = false

    private let diameter: CGFloat = 58
    private let margin: CGFloat = 28

    var body: some View {
        GeometryReader { proxy in
            let bounds = availableBounds(in: proxy)
            let defaultCenter = CGPoint(x: bounds.maxX, y: bounds.minY + 96)
            let baseCenter = CGPoint(
                x: clamp(
                    storedCenterX >= 0 ? CGFloat(storedCenterX) : defaultCenter.x,
                    min: bounds.minX,
                    max: bounds.maxX
                ),
                y: clamp(
                    storedCenterY >= 0 ? CGFloat(storedCenterY) : defaultCenter.y,
                    min: bounds.minY,
                    max: bounds.maxY
                )
            )
            let displayedCenter = CGPoint(
                x: clamp(baseCenter.x + dragOffset.width, min: bounds.minX, max: bounds.maxX),
                y: clamp(baseCenter.y + dragOffset.height, min: bounds.minY, max: bounds.maxY)
            )
            let displayedOrigin = CGPoint(
                x: displayedCenter.x - diameter / 2,
                y: displayedCenter.y - diameter / 2
            )

            ZStack(alignment: .topLeading) {
                Color.clear
                    .allowsHitTesting(false)

                Button {
                    guard !isDragging else { return }
                    debugSheetDetent = .large
                    isShowingDebugSheet = true
                } label: {
                    Circle()
                        .fill(DebugColorPalette.fillStrong)
                        .overlay {
                            VStack(spacing: 1) {
                                Image(systemName: "ladybug.fill")
                                    .font(.system(size: 18, weight: .bold))
                                Text("Debug")
                                    .font(.system(size: 10, weight: .heavy))
                            }
                            .foregroundStyle(.white)
                        }
                        .frame(width: diameter, height: diameter)
                        .shadow(color: DebugColorPalette.shadow, radius: 8, x: 0, y: 6)
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
                .frame(width: diameter, height: diameter)
                .offset(x: displayedOrigin.x, y: displayedOrigin.y)
                .highPriorityGesture(
                    DragGesture(minimumDistance: 6)
                        .onChanged { value in
                            isDragging = true
                            dragOffset = value.translation
                        }
                        .onEnded { value in
                            let finalCenterX = clamp(
                                baseCenter.x + value.translation.width,
                                min: bounds.minX,
                                max: bounds.maxX
                            )
                            let finalCenterY = clamp(
                                baseCenter.y + value.translation.height,
                                min: bounds.minY,
                                max: bounds.maxY
                            )
                            storedCenterX = Double(finalCenterX)
                            storedCenterY = Double(finalCenterY)
                            dragOffset = .zero

                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                isDragging = false
                            }
                        }
                )
                .accessibilityElement()
                .accessibilityLabel(AppStrings.localized("debug.floating.open"))
                .accessibilityAddTraits(.isButton)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .ignoresSafeArea()
        .sheet(isPresented: $isShowingDebugSheet) {
            NavigationStack {
                DebugToolsPage(
                    proEntitlementStore: proEntitlementStore,
                    iCloudSyncDebugSnapshot: iCloudSyncDebugSnapshot,
                    onRunICloudSyncTest: onRunICloudSyncTest,
                    onResetICloudSyncEnvironment: onResetICloudSyncEnvironment,
                    showsDoneButton: true
                )
            }
            .presentationDetents([.height(440), .medium, .large], selection: $debugSheetDetent)
            .presentationDragIndicator(.visible)
        }
    }

    private func availableBounds(in proxy: GeometryProxy) -> CGRect {
        let radius = diameter / 2
        let minX = proxy.safeAreaInsets.leading + margin + radius
        let maxX = proxy.size.width - proxy.safeAreaInsets.trailing - margin - radius
        let minY = proxy.safeAreaInsets.top + margin + radius
        let maxY = proxy.size.height - proxy.safeAreaInsets.bottom - margin - radius
        return CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }

    private func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.max(min, Swift.min(max, value))
    }
}

struct DebugToolsPage: View {
    let showsDoneButton: Bool
    var containerStyle: SettingsContainerStyle
    let iCloudSyncDebugSnapshot: DebugICloudSyncSnapshot
    let onRunICloudSyncTest: () async -> ICloudWebPageSyncDebugResult
    let onResetICloudSyncEnvironment: () async -> ICloudWebPageSyncDebugResult

    @Environment(\.dismiss) private var dismiss
    @Environment(WebPageLibrary.self) private var library
    @ObservedObject private var proEntitlementStore: ProEntitlementStore
    @State private var statusMessage: String?
    @State private var resetConfirmationPresented = false
    @State private var isRunningICloudSyncTest = false

    init(
        proEntitlementStore: ProEntitlementStore,
        iCloudSyncDebugSnapshot: DebugICloudSyncSnapshot,
        onRunICloudSyncTest: @escaping () async -> ICloudWebPageSyncDebugResult,
        onResetICloudSyncEnvironment: @escaping () async -> ICloudWebPageSyncDebugResult,
        showsDoneButton: Bool = false,
        containerStyle: SettingsContainerStyle = .appBackground
    ) {
        self.proEntitlementStore = proEntitlementStore
        self.iCloudSyncDebugSnapshot = iCloudSyncDebugSnapshot
        self.onRunICloudSyncTest = onRunICloudSyncTest
        self.onResetICloudSyncEnvironment = onResetICloudSyncEnvironment
        self.showsDoneButton = showsDoneButton
        self.containerStyle = containerStyle
    }

    var body: some View {
        styledContent
            .navigationTitle(titleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsDoneButton {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(AppStrings.localized("完成")) {
                            dismiss()
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DebugColorPalette.primaryText)
                    }
                }
            }
            .confirmationDialog(
                AppStrings.localized("debug.iCloudSync.reset.confirm.title"),
                isPresented: $resetConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button(AppStrings.localized("debug.iCloudSync.reset.confirm.action"), role: .destructive) {
                    runICloudSyncEnvironmentReset()
                }
                Button(AppStrings.localized("取消"), role: .cancel) {}
            } message: {
                Text(AppStrings.localized("debug.iCloudSync.reset.confirm.message"))
            }
    }

    private var titleText: String {
        let version = nonEmptyBundleValue(for: "CFBundleShortVersionString") ?? "0.0.0"
        let build = nonEmptyBundleValue(for: "CFBundleVersion") ?? "0"
        return "Debug - \(version) (\(build))"
    }

    @ViewBuilder
    private var styledContent: some View {
        switch containerStyle {
        case .appBackground:
            ZStack {
                AppPageBackground()
                    .overlay(DebugColorPalette.background.opacity(0.62))
                debugScrollContent
            }
        case .systemPopover:
            debugScrollContent
                .background(DebugColorPalette.background.opacity(0.62))
        }
    }

    private var debugScrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                introCard
                if AppDistribution.current.showsOfficialDebugPanels {
                    proEntitlementCard
                }
                recentlyDeletedDataCard
                if AppDistribution.current.showsOfficialDebugPanels {
                    iCloudSyncTestCard
                }
                if let statusMessage {
                    feedbackCard(statusMessage)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
    }

    private var introCard: some View {
        DebugCard {
            Text(AppStrings.localized("debug.panel.intro.title"))
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(DebugColorPalette.primaryText)

            Text(AppStrings.localized("debug.panel.intro.detail"))
                .font(.system(size: 14))
                .foregroundStyle(DebugColorPalette.secondaryText)
        }
    }

    private var proEntitlementCard: some View {
        DebugCard {
            Text(AppStrings.localized("debug.proEntitlement.section.title"))
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(DebugColorPalette.primaryText)

            Text(AppStrings.localized("debug.proEntitlement.section.description"))
                .font(.system(size: 14))
                .foregroundStyle(DebugColorPalette.secondaryText)

            VStack(alignment: .leading, spacing: 8) {
                Text(AppStrings.localized("debug.proEntitlement.override"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DebugColorPalette.primaryText)

                Menu {
                    Picker(
                        AppStrings.localized("debug.proEntitlement.override"),
                        selection: debugProEntitlementOverrideBinding
                    ) {
                        ForEach(ProEntitlementDebugOverride.allCases) { override in
                            Text(override.debugPanelDisplayTitle)
                                .tag(override)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(proEntitlementStore.debugProEntitlementOverride.debugPanelDisplayTitle)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DebugColorPalette.primaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DebugColorPalette.surfaceEmphasis)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Text(proEntitlementStore.debugProEntitlementOverride.debugPanelDetailText)
                    .font(.system(size: 13))
                    .foregroundStyle(DebugColorPalette.secondaryText)

                if let overrideSummary = localizedDebugProEntitlementOverrideSummary {
                    Text(overrideSummary)
                        .font(.system(size: 12))
                        .foregroundStyle(DebugColorPalette.secondaryText)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                DebugValueRow(
                    title: AppStrings.localized("debug.proEntitlement.effectiveStatus"),
                    value: proEntitlementStore.proEntitlementState.debugPanelDisplayTitle
                )
                DebugValueRow(
                    title: AppStrings.localized("debug.proEntitlement.effectivePlan"),
                    value: effectivePlanText
                )
            }
        }
    }

    private var recentlyDeletedDataCard: some View {
        DebugCard {
            Text(AppStrings.localized("debug.recentlyDeleted.section.title"))
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(DebugColorPalette.primaryText)

            Text(AppStrings.localized("debug.recentlyDeleted.section.description"))
                .font(.system(size: 14))
                .foregroundStyle(DebugColorPalette.secondaryText)

            Button(action: buildRecentlyDeletedDebugFixtures) {
                HStack(spacing: 10) {
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(DebugColorPalette.fillStrong, in: Circle())
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(AppStrings.localized("debug.recentlyDeleted.seed.title"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(DebugColorPalette.primaryText)

                        Text(AppStrings.localized("debug.recentlyDeleted.seed.detail"))
                            .font(.system(size: 13))
                            .foregroundStyle(DebugColorPalette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(DebugColorPalette.primaryText)
                        .accessibilityHidden(true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DebugColorPalette.surfaceEmphasis)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var iCloudSyncTestCard: some View {
        DebugCard {
            Text(AppStrings.localized("debug.iCloudSync.section.title"))
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(DebugColorPalette.primaryText)

            Text(AppStrings.localized("debug.iCloudSync.section.description"))
                .font(.system(size: 14))
                .foregroundStyle(DebugColorPalette.secondaryText)

            VStack(alignment: .leading, spacing: 6) {
                DebugValueRow(
                    title: AppStrings.localized("debug.iCloudSync.access"),
                    value: iCloudSyncDebugSnapshot.access.debugStatusText
                )
                DebugValueRow(
                    title: AppStrings.localized("debug.iCloudSync.preference"),
                    value: iCloudSyncDebugSnapshot.isUserPreferenceEnabled
                        ? AppStrings.localized("已开启")
                        : AppStrings.localized("已关闭")
                )
                DebugValueRow(
                    title: AppStrings.localized("debug.iCloudSync.service"),
                    value: iCloudSyncDebugSnapshot.isServiceCreated
                        ? AppStrings.localized("已创建")
                        : AppStrings.localized("未创建")
                )
                DebugValueRow(
                    title: AppStrings.localized("debug.iCloudSync.latestRecord"),
                    value: latestICloudSyncRecordText
                )
            }

            DebugInsetLines(lines: iCloudSyncDebugSnapshot.presenceLines)

            HStack(spacing: 10) {
                DebugActionButton(
                    title: AppStrings.localized("debug.iCloudSync.runNow"),
                    systemImage: "arrow.triangle.2.circlepath",
                    isDisabled: !iCloudSyncDebugSnapshot.access.allowsPrivateDatabaseAccess || isRunningICloudSyncTest,
                    action: runICloudSyncTest
                )

                DebugActionButton(
                    title: AppStrings.localized("debug.iCloudSync.reset.title"),
                    systemImage: "trash.circle.fill",
                    isDestructive: true,
                    isDisabled: isRunningICloudSyncTest,
                    action: {
                        resetConfirmationPresented = true
                    }
                )
            }
        }
    }

    private func feedbackCard(_ message: String) -> some View {
        DebugCard {
            Text(message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DebugColorPalette.positive)
        }
    }

    private var effectivePlanText: String {
        guard let activeProEntitlementProductKind = proEntitlementStore.activeProEntitlementProductKind else {
            return AppStrings.localized("debug.proEntitlement.plan.none")
        }

        return activeProEntitlementProductKind.debugPanelDisplayTitle
    }

    private var latestICloudSyncRecordText: String {
        guard let record = iCloudSyncDebugSnapshot.latestRecord else {
            return AppStrings.localized("还没有同步过")
        }
        return "\(record.kind.debugPanelDisplayTitle) · \(record.localPageCount)"
    }

    private var localizedDebugProEntitlementOverrideSummary: String? {
        guard proEntitlementStore.isUsingDebugProEntitlementOverride else { return nil }
        return String(
            format: AppStrings.localized("debug.proEntitlement.overrideSummaryFormat"),
            proEntitlementStore.debugProEntitlementOverride.debugPanelDisplayTitle
        )
    }

    private var debugProEntitlementOverrideBinding: Binding<ProEntitlementDebugOverride> {
        Binding(
            get: { proEntitlementStore.debugProEntitlementOverride },
            set: { newValue in
                applyDebugProEntitlementOverride(newValue)
            }
        )
    }

    private func applyDebugProEntitlementOverride(_ override: ProEntitlementDebugOverride) {
        guard override != proEntitlementStore.debugProEntitlementOverride else { return }

        Task { @MainActor in
            await proEntitlementStore.setDebugProEntitlementOverride(override)
            let messageKey = override == .followStoreKit
                ? "debug.proEntitlement.overrideAppliedFollowStoreKit"
                : "debug.proEntitlement.overrideAppliedFormat"
            statusMessage = override == .followStoreKit
                ? AppStrings.localized(messageKey)
                : String(
                    format: AppStrings.localized(messageKey),
                    override.debugPanelDisplayTitle
                )
        }
    }

    private func buildRecentlyDeletedDebugFixtures() {
        do {
            let count = try library.buildRecentlyDeletedDebugFixtures()
            statusMessage = String(
                format: AppStrings.localized("debug.recentlyDeleted.seed.statusFormat"),
                count
            )
        } catch {
            statusMessage = String(
                format: AppStrings.localized("debug.recentlyDeleted.seed.failureFormat"),
                error.localizedDescription
            )
        }
    }

    private func runICloudSyncTest() {
        guard !isRunningICloudSyncTest else { return }
        isRunningICloudSyncTest = true
        statusMessage = AppStrings.localized("debug.iCloudSync.running")
        Task { @MainActor in
            let result = await onRunICloudSyncTest()
            statusMessage = "\(result.title)\n\(firstDiagnosticLine(from: result.message))"
            isRunningICloudSyncTest = false
        }
    }

    private func runICloudSyncEnvironmentReset() {
        guard !isRunningICloudSyncTest else { return }
        isRunningICloudSyncTest = true
        statusMessage = AppStrings.localized("debug.iCloudSync.reset.running")
        Task { @MainActor in
            let result = await onResetICloudSyncEnvironment()
            statusMessage = "\(result.title)\n\(firstDiagnosticLine(from: result.message))"
            isRunningICloudSyncTest = false
        }
    }

    private func firstDiagnosticLine(from message: String) -> String {
        message
            .split(separator: "\n")
            .map(String.init)
            .first(where: { !$0.hasPrefix("【") }) ?? message
    }

    private func nonEmptyBundleValue(for key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String, !value.isEmpty else {
            return nil
        }

        return value
    }
}

private struct DebugCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DebugColorPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(DebugColorPalette.border, lineWidth: 1)
        }
        .shadow(color: DebugColorPalette.shadow, radius: 6, x: 0, y: 4)
    }
}

private struct DebugValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(DebugColorPalette.secondaryText)

            Spacer(minLength: 12)

            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DebugColorPalette.primaryText)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct DebugInsetLines: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(DebugColorPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DebugColorPalette.surfaceEmphasis)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct DebugActionButton: View {
    let title: String
    let systemImage: String
    var isDestructive = false
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .padding(.horizontal, 8)
                .foregroundStyle(isDestructive ? Color.white : DebugColorPalette.primaryText)
                .background(
                    isDestructive ? DebugColorPalette.fillStrong : DebugColorPalette.surfaceEmphasis,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
    }
}

extension ProEntitlementDebugOverride {
    var debugPanelDisplayTitle: String {
        switch self {
        case .followStoreKit:
            return AppStrings.localized("debug.proEntitlement.override.followStoreKit.title")
        case .free:
            return AppStrings.localized("debug.proEntitlement.override.free.title")
        case .expired:
            return AppStrings.localized("debug.proEntitlement.override.expired.title")
        case .activeYearly:
            return AppStrings.localized("debug.proEntitlement.override.activeYearly.title")
        case .activeMonthly:
            return AppStrings.localized("debug.proEntitlement.override.activeMonthly.title")
        case .activeLifetime:
            return AppStrings.localized("debug.proEntitlement.override.activeLifetime.title")
        }
    }

    var debugPanelDetailText: String {
        switch self {
        case .followStoreKit:
            return AppStrings.localized("debug.proEntitlement.override.followStoreKit.detail")
        case .free:
            return AppStrings.localized("debug.proEntitlement.override.free.detail")
        case .expired:
            return AppStrings.localized("debug.proEntitlement.override.expired.detail")
        case .activeYearly:
            return AppStrings.localized("debug.proEntitlement.override.activeYearly.detail")
        case .activeMonthly:
            return AppStrings.localized("debug.proEntitlement.override.activeMonthly.detail")
        case .activeLifetime:
            return AppStrings.localized("debug.proEntitlement.override.activeLifetime.detail")
        }
    }
}

private extension ICloudWebPageSyncUserRecordKind {
    var debugPanelDisplayTitle: String {
        switch self {
        case .inProgress:
            return AppStrings.localized("正在同步")
        case .received:
            return AppStrings.localized("下载：从 iCloud 收到更新")
        case .completed:
            return AppStrings.localized("上传：已同步到 iCloud")
        case .noChanges:
            return AppStrings.localized("无变化：已经是最新")
        case .noAccount:
            return AppStrings.localized("未登录 iCloud")
        case .unavailable:
            return AppStrings.localized("iCloud 暂不可用")
        case .failed:
            return AppStrings.localized("同步失败，将自动重试")
        }
    }
}

private extension ProEntitlementState {
    var debugPanelDisplayTitle: String {
        switch self {
        case .unknown:
            return AppStrings.localized("debug.proEntitlement.state.unknown")
        case .free:
            return AppStrings.localized("debug.proEntitlement.state.free")
        case .active:
            return AppStrings.localized("debug.proEntitlement.state.active")
        case .expired:
            return AppStrings.localized("debug.proEntitlement.state.expired")
        }
    }
}

private extension ProEntitlementProductKind {
    var debugPanelDisplayTitle: String {
        switch self {
        case .yearly:
            return AppStrings.localized("debug.proEntitlement.override.activeYearly.title")
        case .monthly:
            return AppStrings.localized("debug.proEntitlement.override.activeMonthly.title")
        case .lifetime, .lifetimePromo:
            return AppStrings.localized("debug.proEntitlement.override.activeLifetime.title")
        }
    }
}
