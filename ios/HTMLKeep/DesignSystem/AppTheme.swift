import QuartzCore
import SwiftUI
import UIKit

private let appEmptyStateDefaultTargetCenterYRatio: CGFloat = 0.4
private let appEmptyStateDefaultHorizontalPadding: CGFloat = 20

enum AppTheme {
    static let pageTop = Color(lightHex: 0xDDE7FB, darkHex: 0x0D1118)
    static let pageMiddle = Color(lightHex: 0xEEF3FA, darkHex: 0x111722)
    static let pageBottom = Color(lightHex: 0xF6F9FC, darkHex: 0x141B25)
    static let surface = Color(lightHex: 0xFFFFFF, darkHex: 0x151B24, lightOpacity: 0.92)
    static let surfaceStrong = Color(lightHex: 0xFFFFFF, darkHex: 0x1A212B)
    static let surfaceInset = Color(lightHex: 0xF3F3FB, darkHex: 0x202733)
    static let surfaceDock = Color(lightHex: 0xEBEDF9, darkHex: 0x141826)
    static let surfaceDockShadow = Color(lightHex: 0xD5DFED, darkHex: 0x05070D, darkOpacity: 0.62)
    static let surfaceBorder = Color(lightHex: 0xF2F4FA, darkHex: 0x2D3542)
    static let surfaceInsetBorder = Color(lightHex: 0xFFFFFF, darkHex: 0x334052, lightOpacity: 0.72, darkOpacity: 0.72)
    static let surfaceShadow = Color(lightHex: 0xD5DFED, darkHex: 0x05070D, darkOpacity: 0.62)
    static let ink = Color(hex: 0x43536C)
    static let contentPrimary = Color(lightHex: 0x43536C, darkHex: 0xD4D9DC)
    static let contentAccent = Color(lightHex: 0x556397, darkHex: 0xAEB9E6)
    static let listItemTitle = Color(lightHex: 0x43536C, darkHex: 0xD4D9DC)
    static let textSecondary = Color(hex: 0x7B8997)
    static let deepWater = Color(hex: 0x556397)
    static let sky = Color(hex: 0x4CC8FF)
    static let leaf = Color(hex: 0x0FEA94)
    static let gold = Color(hex: 0xFFD100)
    static let premiumGold = Color(hex: 0xFFC107)
    static let coral = Color(hex: 0xFF5553)
    static let orange = Color(hex: 0xFF924B)
    static let aiPurple = Color(hex: 0xC47EFF)
    static let pink = Color(hex: 0xFA78FF)
    static let mint = Color(hex: 0x03D1B2)

    static let pageGradient = LinearGradient(
        colors: [pageTop, pageMiddle, pageBottom],
        startPoint: .top,
        endPoint: .bottom
    )
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    init(lightHex: UInt32, darkHex: UInt32, lightOpacity: Double = 1, darkOpacity: Double = 1) {
        self.init(UIColor { traits in
            let usesDarkColor = traits.userInterfaceStyle == .dark
            let hex = usesDarkColor ? darkHex : lightHex
            let opacity = usesDarkColor ? darkOpacity : lightOpacity

            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: CGFloat(opacity)
            )
        })
    }

    init(rgbaHex: UInt32) {
        self.init(
            red: Double((rgbaHex >> 24) & 0xFF) / 255,
            green: Double((rgbaHex >> 16) & 0xFF) / 255,
            blue: Double((rgbaHex >> 8) & 0xFF) / 255,
            opacity: Double(rgbaHex & 0xFF) / 255
        )
    }

    init(hexString: String) {
        let hex = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

struct AppPageBackground: View {
    var body: some View {
        Rectangle()
            .fill(AppTheme.pageGradient)
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

struct AppSurfaceCard<Content: View>: View {
    var isProminent = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isProminent ? AppTheme.surfaceStrong : AppTheme.surface)
                .shadow(color: AppTheme.surfaceShadow, radius: 4, x: 0, y: isProminent ? 4 : 3)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.surfaceBorder, lineWidth: 1)
        }
    }
}

struct AppInsetSurface<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(12)
        .background(AppTheme.surfaceInset, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.surfaceInsetBorder, lineWidth: 1)
        }
    }
}

struct AppEmptyStateViewport<Content: View>: View {
    let columnWidth: CGFloat
    let contentWidth: CGFloat
    let minHeight: CGFloat
    let targetCenterYRatio: CGFloat
    @ViewBuilder let content: Content

    init(
        columnWidth: CGFloat,
        contentWidth: CGFloat,
        minHeight: CGFloat,
        targetCenterYRatio: CGFloat = appEmptyStateDefaultTargetCenterYRatio,
        @ViewBuilder content: () -> Content
    ) {
        self.columnWidth = columnWidth
        self.contentWidth = contentWidth
        self.minHeight = minHeight
        self.targetCenterYRatio = targetCenterYRatio
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(height: minHeight)

            content
                .frame(width: contentWidth, alignment: .leading)
                .position(
                    x: columnWidth / 2,
                    y: minHeight * targetCenterYRatio
                )
        }
        .frame(width: columnWidth)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .top)
    }
}

enum AppEmptyStatePromptActivityStyle {
    case none
    case typingDots

    var id: String {
        switch self {
        case .none:
            return "none"
        case .typingDots:
            return "typingDots"
        }
    }
}

struct AppEmptyStatePromptAction {
    let title: String
    let coloredIconAssetName: String?
    let systemImage: String?
    let scene: AppActionButtonScene
    let size: AppActionButtonSize
    let isDisabled: Bool
    let action: () -> Void

    init(
        title: String,
        coloredIconAssetName: String? = nil,
        systemImage: String? = nil,
        scene: AppActionButtonScene = .sky,
        size: AppActionButtonSize = .medium,
        isDisabled: Bool = false,
        action: @escaping () -> Void = {}
    ) {
        self.title = title
        self.coloredIconAssetName = coloredIconAssetName
        self.systemImage = systemImage
        self.scene = scene
        self.size = size
        self.isDisabled = isDisabled
        self.action = action
    }

    var identityFragment: String {
        [
            title,
            coloredIconAssetName ?? "",
            systemImage ?? "",
            scene.id,
            size.id,
            isDisabled ? "disabled" : "enabled"
        ]
        .joined(separator: ":")
    }
}

enum AppEmptyStatePromptIllustrationPlacement {
    case top
    case leading
    case trailing
    case bottom

    var pointerEdge: Edge {
        switch self {
        case .top:
            return .top
        case .leading:
            return .leading
        case .trailing:
            return .trailing
        case .bottom:
            return .bottom
        }
    }
}

struct AppEmptyStatePrompt: View {
    private static let topPointerSize = CGSize(width: 24, height: 18)
    private static let leadingPointerSize = CGSize(width: 13, height: 18)
    private static let pointerBubbleOverlap: CGFloat = 0.5
    private static let contentFadeOutTransition = Animation.easeOut(duration: 0.12)
    private static let contentFadeInTransition = Animation.easeIn(duration: 0.16)
    private static let bubbleHeightTransition = Animation.spring(response: 0.32, dampingFraction: 0.88)
    private static let contentSwapDelayNs: UInt64 = 120_000_000

    let title: String
    let illustrationAssetName: String
    let illustrationSpriteResourceName: String?
    let illustrationSpriteResourceExtension: String
    let illustrationPlacement: AppEmptyStatePromptIllustrationPlacement
    let illustrationSize: CGFloat
    let message: String?
    let activityStyle: AppEmptyStatePromptActivityStyle
    let primaryAction: AppEmptyStatePromptAction?
    let secondaryAction: AppEmptyStatePromptAction?
    let contentIdentity: String
    let pointerHorizontalOffset: CGFloat

    @State private var activeContent: AppEmptyStatePromptContent
    @State private var contentOpacity: Double = 1
    @State private var contentSwapTask: Task<Void, Never>?

    init(
        title: String,
        illustrationAssetName: String,
        illustrationSpriteResourceName: String? = nil,
        illustrationSpriteResourceExtension: String = "png",
        illustrationPlacement: AppEmptyStatePromptIllustrationPlacement = .leading,
        illustrationSize: CGFloat = 72,
        message: String? = nil,
        activityStyle: AppEmptyStatePromptActivityStyle = .none,
        primaryAction: AppEmptyStatePromptAction? = nil,
        secondaryAction: AppEmptyStatePromptAction? = nil,
        contentIdentity: String? = nil,
        pointerHorizontalOffset: CGFloat = 0
    ) {
        self.title = title
        self.illustrationAssetName = illustrationAssetName
        self.illustrationSpriteResourceName = illustrationSpriteResourceName
        self.illustrationSpriteResourceExtension = illustrationSpriteResourceExtension
        self.illustrationPlacement = illustrationPlacement
        self.illustrationSize = illustrationSize
        self.message = message
        self.activityStyle = activityStyle
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
        let resolvedContentIdentity = contentIdentity ?? Self.makeContentIdentity(
            title: title,
            message: message,
            activityStyle: activityStyle,
            primaryAction: primaryAction,
            secondaryAction: secondaryAction
        )
        self.contentIdentity = resolvedContentIdentity
        self.pointerHorizontalOffset = pointerHorizontalOffset

        _activeContent = State(
            initialValue: AppEmptyStatePromptContent(
                id: resolvedContentIdentity,
                title: title,
                message: message,
                activityStyle: activityStyle,
                primaryAction: primaryAction,
                secondaryAction: secondaryAction
            )
        )
    }

    var body: some View {
        switch illustrationPlacement {
        case .top:
            VStack(spacing: 14) {
                illustrationView
                animatedPromptBubble
            }
        case .leading:
            HStack(alignment: .top, spacing: 14) {
                illustrationView
                animatedPromptBubble
            }
        case .trailing:
            HStack(alignment: .top, spacing: 14) {
                animatedPromptBubble
                illustrationView
            }
        case .bottom:
            VStack(spacing: 14) {
                animatedPromptBubble
                illustrationView
            }
        }
    }

    private var illustrationView: some View {
        Group {
            if hasSpriteIllustration, let illustrationSpriteResourceName {
                AppSpriteIllustrationView(
                    resourceName: illustrationSpriteResourceName,
                    resourceExtension: illustrationSpriteResourceExtension
                )
                    .accessibilityHidden(true)
            } else {
                AppColoredIcon(assetName: illustrationAssetName, size: illustrationSize)
                    .frame(width: illustrationFrameSize, height: illustrationFrameSize)
                    .background(AppTheme.surfaceInset, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(AppTheme.surfaceBorder, lineWidth: 1)
                    }
                    .accessibilityHidden(true)
            }
        }
            .frame(width: illustrationFrameSize, height: illustrationFrameSize)
    }

    private var illustrationFrameSize: CGFloat {
        hasSpriteIllustration ? illustrationSize : max(illustrationSize + 20, 54)
    }

    private var hasSpriteIllustration: Bool {
        guard let illustrationSpriteResourceName else { return false }
        return Bundle.main.url(
            forResource: illustrationSpriteResourceName,
            withExtension: illustrationSpriteResourceExtension
        ) != nil
    }

    private var animatedPromptBubble: some View {
        promptBubble(activeContent)
            .opacity(contentOpacity)
            .animation(Self.bubbleHeightTransition, value: activeContent.id)
            .onChange(of: contentIdentity) { _, _ in
                transition(to: desiredContent)
            }
            .onDisappear {
                contentSwapTask?.cancel()
            }
    }

    private var desiredContent: AppEmptyStatePromptContent {
        AppEmptyStatePromptContent(
            id: contentIdentity,
            title: title,
            message: message,
            activityStyle: activityStyle,
            primaryAction: primaryAction,
            secondaryAction: secondaryAction
        )
    }

    private func promptBubble(_ content: AppEmptyStatePromptContent) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(content.title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(AppTheme.contentPrimary)

            if let message = content.message, !message.isEmpty {
                Text(message)
                    .font(.system(size: 16))
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if content.activityStyle == .typingDots {
                AppEmptyStateTypingDots()
                    .padding(.top, 2)
            }

            if content.primaryAction != nil || content.secondaryAction != nil {
                VStack(spacing: 10) {
                    if let primaryAction = content.primaryAction {
                        AppEmptyStatePromptButton(promptAction: primaryAction)
                    }

                    if let secondaryAction = content.secondaryAction {
                        AppEmptyStatePromptButton(promptAction: secondaryAction)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppTheme.surfaceStrong)
                .shadow(color: Color.black.opacity(0.05), radius: 0, x: 0, y: 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppTheme.surfaceBorder, lineWidth: 1)
        }
        .overlay(alignment: pointerAlignment) {
            AppEmptyStatePromptPointer(edge: pointerEdge)
                .fill(AppTheme.surfaceStrong)
                .frame(width: pointerSize.width, height: pointerSize.height)
                .overlay {
                    AppEmptyStatePromptPointerOutline(edge: pointerEdge)
                        .stroke(AppTheme.surfaceBorder, lineWidth: 1)
                }
                .offset(pointerOffset)
        }
        .accessibilityElement(children: .combine)
    }

    private func transition(to newValue: AppEmptyStatePromptContent) {
        guard activeContent.id != newValue.id else {
            activeContent = newValue
            return
        }

        contentSwapTask?.cancel()
        contentSwapTask = Task { @MainActor in
            withAnimation(Self.contentFadeOutTransition) {
                contentOpacity = 0
            }

            try? await Task.sleep(nanoseconds: Self.contentSwapDelayNs)
            guard !Task.isCancelled else { return }

            withAnimation(Self.bubbleHeightTransition) {
                activeContent = newValue
            }

            withAnimation(Self.contentFadeInTransition) {
                contentOpacity = 1
            }
        }
    }

    private static func makeContentIdentity(
        title: String,
        message: String?,
        activityStyle: AppEmptyStatePromptActivityStyle,
        primaryAction: AppEmptyStatePromptAction?,
        secondaryAction: AppEmptyStatePromptAction?
    ) -> String {
        [
            title,
            message ?? "",
            activityStyle.id,
            primaryAction?.identityFragment ?? "",
            secondaryAction?.identityFragment ?? ""
        ]
        .joined(separator: "|")
    }

    private var pointerAlignment: Alignment {
        switch pointerEdge {
        case .leading:
            return .leading
        case .trailing:
            return .trailing
        case .top:
            return .top
        case .bottom:
            return .bottom
        }
    }

    private var pointerEdge: Edge {
        illustrationPlacement.pointerEdge
    }

    private var pointerOffset: CGSize {
        switch pointerEdge {
        case .leading:
            return CGSize(
                width: -Self.leadingPointerSize.width + Self.pointerBubbleOverlap,
                height: Self.leadingPointerSize.height * 0.4
            )
        case .trailing:
            return CGSize(
                width: Self.leadingPointerSize.width - Self.pointerBubbleOverlap,
                height: Self.leadingPointerSize.height * 0.4
            )
        case .top:
            return CGSize(
                width: pointerHorizontalOffset,
                height: -Self.topPointerSize.height + Self.pointerBubbleOverlap
            )
        case .bottom:
            return CGSize(
                width: pointerHorizontalOffset,
                height: Self.topPointerSize.height - Self.pointerBubbleOverlap
            )
        }
    }

    private var pointerSize: CGSize {
        switch pointerEdge {
        case .leading, .trailing:
            return Self.leadingPointerSize
        case .top, .bottom:
            return Self.topPointerSize
        }
    }
}

struct AppEmptyStatePromptContent {
    let id: String
    let title: String
    let message: String?
    let activityStyle: AppEmptyStatePromptActivityStyle
    let primaryAction: AppEmptyStatePromptAction?
    let secondaryAction: AppEmptyStatePromptAction?
}

struct AppEmptyStatePromptButton: View {
    let promptAction: AppEmptyStatePromptAction

    var body: some View {
        AppActionButton(
            promptAction.title,
            coloredIconAssetName: promptAction.coloredIconAssetName,
            systemImage: promptAction.systemImage,
            scene: promptAction.scene,
            size: promptAction.size,
            action: promptAction.action
        )
        .disabled(promptAction.isDisabled)
        .opacity(promptAction.isDisabled ? 0.6 : 1)
    }
}

struct AppEmptyStateTypingDots: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 8.0)) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate

            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    let phase = dotPhase(for: index, elapsed: elapsed)

                    Circle()
                        .fill(AppTheme.textSecondary.opacity(0.95))
                        .frame(width: 8, height: 8)
                        .scaleEffect(0.78 + (0.36 * phase))
                        .opacity(0.28 + (0.72 * phase))
                        .offset(y: -2 * phase)
                }
            }
            .frame(height: 12)
        }
        .accessibilityHidden(true)
    }

    private func dotPhase(for index: Int, elapsed: TimeInterval) -> Double {
        let cycleDuration = 1.15
        let localTime = (elapsed - (Double(index) * 0.14)).truncatingRemainder(dividingBy: cycleDuration)
        let normalized = localTime < 0 ? localTime + cycleDuration : localTime

        if normalized < 0.28 {
            return normalized / 0.28
        }
        if normalized < 0.58 {
            return 1
        }
        if normalized < 0.9 {
            return 1 - ((normalized - 0.58) / 0.32)
        }
        return 0
    }
}

struct AppEmptyStatePromptPointer: Shape {
    let edge: Edge

    func path(in rect: CGRect) -> Path {
        var path = Path()

        switch edge {
        case .leading:
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        case .trailing:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        case .top:
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        case .bottom:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }

        path.closeSubpath()
        return path
    }
}

struct AppEmptyStatePromptPointerOutline: Shape {
    let edge: Edge

    func path(in rect: CGRect) -> Path {
        var path = Path()

        switch edge {
        case .leading:
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        case .trailing:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        case .top:
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        case .bottom:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }

        return path
    }
}

struct AppSpriteIllustrationView: UIViewRepresentable {
    let resourceName: String
    let resourceExtension: String

    func makeUIView(context: Context) -> AppSpriteIllustrationUIView {
        let view = AppSpriteIllustrationUIView()
        view.configure(
            resourceName: resourceName,
            resourceExtension: resourceExtension
        )
        return view
    }

    func updateUIView(_ uiView: AppSpriteIllustrationUIView, context: Context) {
        uiView.configure(
            resourceName: resourceName,
            resourceExtension: resourceExtension
        )
    }

    static func dismantleUIView(_ uiView: AppSpriteIllustrationUIView, coordinator: ()) {
        uiView.stop()
    }
}

final class AppSpriteIllustrationUIView: UIView {
    private static let frameSize: CGFloat = 240
    private static let frameEdgeCrop: CGFloat = 2
    private static let spriteColumns = 8
    private static let frameCount = 61
    private static let targetFrameRate: TimeInterval = 15
    private static let loopHoldDuration: TimeInterval = 0.35
    private static let loopCrossfadeDuration: TimeInterval = 0.22
    private static var cachedSprites: [String: UIImage] = [:]

    private var spriteImage: UIImage?
    private var displayLink: CADisplayLink?
    private var loopStartTime: CFTimeInterval = CACurrentMediaTime()
    private var holdStartTime: CFTimeInterval = 0
    private var fadeStartTime: CFTimeInterval = 0
    private var loopState = LoopState.playing
    private var currentResourceKey: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    deinit {
        stop()
    }

    func configure(
        resourceName: String,
        resourceExtension: String
    ) {
        let resourceKey = "\(resourceName).\(resourceExtension)"
        guard currentResourceKey != resourceKey else { return }
        currentResourceKey = resourceKey

        stop()
        spriteImage = Self.loadSprite(resourceName: resourceName, resourceExtension: resourceExtension)
        loopStartTime = CACurrentMediaTime()
        loopState = .playing
        if spriteImage != nil {
            startDisplayLink()
        }
        setNeedsDisplay()
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        spriteImage = nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            displayLink?.invalidate()
            displayLink = nil
        } else if spriteImage != nil {
            startDisplayLink()
        }
    }

    override func draw(_ rect: CGRect) {
        guard let spriteImage else { return }
        drawAnimatedFrames(spriteImage)
    }

    private func setupView() {
        isOpaque = false
        backgroundColor = .clear
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
    }

    @objc private func tick() {
        setNeedsDisplay()
    }

    private func drawAnimatedFrames(_ spriteImage: UIImage) {
        let now = CACurrentMediaTime()
        let frameInterval = 1 / Self.targetFrameRate
        let playDuration = Double(Self.frameCount) * frameInterval

        switch loopState {
        case .playing:
            let elapsed = now - loopStartTime
            if elapsed >= playDuration {
                loopState = .holding
                holdStartTime = now
                drawFrame(spriteImage, index: Self.frameCount - 1, alpha: 1)
            } else {
                let index = min(Int(elapsed / frameInterval), Self.frameCount - 1)
                drawFrame(spriteImage, index: index, alpha: 1)
            }
        case .holding:
            drawFrame(spriteImage, index: Self.frameCount - 1, alpha: 1)
            if now - holdStartTime >= Self.loopHoldDuration {
                loopState = .fading
                fadeStartTime = now
            }
        case .fading:
            let progress = min(max((now - fadeStartTime) / Self.loopCrossfadeDuration, 0), 1)
            drawFrame(spriteImage, index: 0, alpha: 1)
            drawFrame(spriteImage, index: Self.frameCount - 1, alpha: 1 - progress)
            if progress >= 1 {
                loopState = .playing
                loopStartTime = now
            }
        }
    }

    private func drawFrame(_ spriteImage: UIImage, index: Int, alpha: Double) {
        guard let cgImage = spriteImage.cgImage,
              let context = UIGraphicsGetCurrentContext() else { return }
        let pixelScale = CGFloat(cgImage.width) / spriteImage.size.width
        let frameSize = Self.frameSize
        let sourceLeft = CGFloat(index % Self.spriteColumns) * frameSize + Self.frameEdgeCrop
        let sourceTop = CGFloat(index / Self.spriteColumns) * frameSize + Self.frameEdgeCrop
        let sourceSize = frameSize - Self.frameEdgeCrop * 2
        let sourceRect = CGRect(
            x: sourceLeft * pixelScale,
            y: sourceTop * pixelScale,
            width: sourceSize * pixelScale,
            height: sourceSize * pixelScale
        ).integral
        guard let frame = cgImage.cropping(to: sourceRect) else { return }

        context.saveGState()
        context.setAlpha(CGFloat(alpha))
        UIImage(cgImage: frame, scale: spriteImage.scale, orientation: spriteImage.imageOrientation)
            .draw(in: fitCenterRect(sourceWidth: sourceSize, sourceHeight: sourceSize))
        context.restoreGState()
    }

    private func fitCenterRect(sourceWidth: CGFloat, sourceHeight: CGFloat) -> CGRect {
        guard bounds.width > 0, bounds.height > 0, sourceWidth > 0, sourceHeight > 0 else {
            return bounds
        }
        let scale = min(bounds.width / sourceWidth, bounds.height / sourceHeight)
        let targetSize = CGSize(width: sourceWidth * scale, height: sourceHeight * scale)
        return CGRect(
            x: (bounds.width - targetSize.width) / 2,
            y: (bounds.height - targetSize.height) / 2,
            width: targetSize.width,
            height: targetSize.height
        )
    }

    private static func loadSprite(resourceName: String, resourceExtension: String) -> UIImage? {
        let resourceKey = "\(resourceName).\(resourceExtension)"
        if let cachedSprite = cachedSprites[resourceKey] {
            return cachedSprite
        }
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: resourceExtension),
              let image = UIImage(contentsOfFile: url.path) else {
            return nil
        }
        cachedSprites[resourceKey] = image
        return image
    }

    private enum LoopState {
        case playing
        case holding
        case fading
    }
}

struct AppColoredIcon: View {
    let assetName: String
    let size: CGFloat

    init(assetName: String, size: CGFloat = 28) {
        self.assetName = assetName
        self.size = size
    }

    var body: some View {
        Image(assetName)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct AppListSection<Content: View>: View {
    let title: String
    let footer: String?
    @ViewBuilder let content: Content

    init(
        title: String,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AppListSectionTitle(title)
                .padding(.horizontal, 4)

            content

            if let footer, !footer.isEmpty {
                Text(footer)
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal, 4)
            }
        }
    }
}

struct AppListSectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(AppTheme.textSecondary)
            .textCase(nil)
    }
}

struct AppListGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .background(AppTheme.surfaceStrong)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: Color.black.opacity(0.06), radius: 0, x: 0, y: 2)
    }
}

struct AppListDivider: View {
    var body: some View {
        Rectangle()
            .fill(AppTheme.surfaceDock)
            .frame(height: 1)
            .padding(.horizontal, 16)
            .accessibilityHidden(true)
    }
}

enum AppListItemTitleDisplayMode {
    case truncating
    case scalesToFit

    var minimumScaleFactor: CGFloat {
        switch self {
        case .truncating:
            1
        case .scalesToFit:
            0.7
        }
    }

    var truncationMode: Text.TruncationMode {
        switch self {
        case .truncating:
            .middle
        case .scalesToFit:
            .tail
        }
    }
}

struct AppListItem<LeadingIcon: View>: View {
    @Environment(\.layoutDirection) private var layoutDirection

    let title: String
    let subtitle: String?
    let subtitleSystemImage: String?
    let statusText: String?
    let titleDisplayMode: AppListItemTitleDisplayMode
    let showsChevron: Bool
    let horizontalPadding: CGFloat
    let minimumHeight: CGFloat?
    @ViewBuilder let leadingIcon: LeadingIcon

    init(
        title: String,
        subtitle: String? = nil,
        subtitleSystemImage: String? = nil,
        leadingIconAssetName: String,
        statusText: String? = nil,
        titleDisplayMode: AppListItemTitleDisplayMode = .truncating,
        showsChevron: Bool = true,
        horizontalPadding: CGFloat = 16,
        minimumHeight: CGFloat? = 64
    ) where LeadingIcon == AppColoredIcon {
        self.title = title
        self.subtitle = subtitle
        self.subtitleSystemImage = subtitleSystemImage
        self.statusText = statusText
        self.titleDisplayMode = titleDisplayMode
        self.showsChevron = showsChevron
        self.horizontalPadding = horizontalPadding
        self.minimumHeight = minimumHeight
        self.leadingIcon = AppColoredIcon(assetName: leadingIconAssetName)
    }

    init(
        title: String,
        subtitle: String? = nil,
        subtitleSystemImage: String? = nil,
        statusText: String? = nil,
        titleDisplayMode: AppListItemTitleDisplayMode = .truncating,
        showsChevron: Bool = true,
        horizontalPadding: CGFloat = 16,
        minimumHeight: CGFloat? = 64,
        @ViewBuilder leadingIcon: () -> LeadingIcon
    ) {
        self.title = title
        self.subtitle = subtitle
        self.subtitleSystemImage = subtitleSystemImage
        self.statusText = statusText
        self.titleDisplayMode = titleDisplayMode
        self.showsChevron = showsChevron
        self.horizontalPadding = horizontalPadding
        self.minimumHeight = minimumHeight
        self.leadingIcon = leadingIcon()
    }

    var body: some View {
        HStack(spacing: 12) {
            leadingIcon
                .frame(width: Self.leadingIconSize, height: Self.leadingIconSize)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AppTheme.listItemTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(titleDisplayMode.minimumScaleFactor)
                    .allowsTightening(titleDisplayMode == .scalesToFit)
                    .truncationMode(titleDisplayMode.truncationMode)

                if let subtitle, !subtitle.isEmpty {
                    HStack(spacing: subtitleSystemImage == nil ? 0 : 4) {
                        if let subtitleSystemImage {
                            Image(systemName: subtitleSystemImage)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AppTheme.textSecondary)
                                .frame(width: 12, height: 12)
                                .accessibilityHidden(true)
                        }

                        Text(subtitle)
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .lineLimit(1)
                    .truncationMode(.tail)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                if let statusText, !statusText.isEmpty {
                    Text(statusText)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.trailing)
                }

                if showsChevron {
                    Image(systemName: chevronSymbolName)
                        .flipsForRightToLeftLayoutDirection(false)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .leading)
        .padding(.horizontal, horizontalPadding)
        .contentShape(Rectangle())
    }

    private static var leadingIconSize: CGFloat { 28 }

    private var chevronSymbolName: String {
        layoutDirection == .rightToLeft ? "chevron.left" : "chevron.right"
    }
}

struct BottomActionDock<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: 28,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 28,
                style: .continuous
            )
            .fill(AppTheme.surfaceDock)
            .shadow(color: AppTheme.surfaceDockShadow, radius: 4, x: 0, y: -3)
            .ignoresSafeArea(edges: .bottom)
        }
    }
}

struct AppActionButtonPalette {
    let fill: Color
    let label: Color
    let topGlowStart: Color
    let topGlowEnd: Color
    let innerShadow: Color
    let stroke: Color?
    let topSideStroke: Color?

    static let dropShadow = Color.black.opacity(26.0 / 255.0)
}

enum AppActionButtonScene: CaseIterable, Identifiable {
    case sky
    case leaf
    case gold
    case premiumGold
    case coral
    case orange
    case ai
    case pink
    case mint
    case neutralLight
    case neutralLightWithBorder
    case neutralDark

    private static let neutralSurfaceTopGlowStart = Color(
        lightHex: 0xFFFFFF,
        darkHex: 0x2B3545,
        lightOpacity: 1,
        darkOpacity: 0.88
    )
    private static let neutralSurfaceTopGlowEnd = Color(
        lightHex: 0xFFFFFF,
        darkHex: 0x1A212B,
        lightOpacity: 0,
        darkOpacity: 0
    )
    private static let neutralTopSideStroke = Color(
        lightHex: 0xEBEDF9,
        darkHex: 0x334052,
        lightOpacity: 1,
        darkOpacity: 0.72
    )

    var id: String { title }

    var title: String {
        switch self {
        case .sky: return "Sky"
        case .leaf: return "Leaf"
        case .gold: return "Gold"
        case .premiumGold: return "Premium Gold"
        case .coral: return "Coral"
        case .orange: return "Orange"
        case .ai: return "AI"
        case .pink: return "Pink"
        case .mint: return "Mint"
        case .neutralLight: return "Neutral Light"
        case .neutralLightWithBorder: return "Neutral Light With Border"
        case .neutralDark: return "Neutral Dark"
        }
    }

    var palette: AppActionButtonPalette {
        switch self {
        case .sky:
            return AppActionButtonPalette(
                fill: AppTheme.sky,
                label: Color(hex: 0x0073CC),
                topGlowStart: Color(rgbaHex: 0x00F0FF87),
                topGlowEnd: Color(rgbaHex: 0x00F0FF00),
                innerShadow: Color(hex: 0x499DF1),
                stroke: nil,
                topSideStroke: nil
            )
        case .leaf:
            return AppActionButtonPalette(
                fill: AppTheme.leaf,
                label: Color(hex: 0x007C69),
                topGlowStart: Color(rgbaHex: 0x96FF3087),
                topGlowEnd: Color(rgbaHex: 0xFFFFFF00),
                innerShadow: Color(hex: 0x0CC686),
                stroke: nil,
                topSideStroke: nil
            )
        case .gold:
            return AppActionButtonPalette(
                fill: AppTheme.gold,
                label: Color(hex: 0xBD4E04),
                topGlowStart: Color(rgbaHex: 0xFFFFFF87),
                topGlowEnd: Color(rgbaHex: 0xFFE36087),
                innerShadow: Color(hex: 0xF7B607),
                stroke: nil,
                topSideStroke: nil
            )
        case .premiumGold:
            return AppActionButtonPalette(
                fill: AppTheme.premiumGold,
                label: Color(hex: 0x3D2F00),
                topGlowStart: Color(rgbaHex: 0xFFFFFF91),
                topGlowEnd: Color(rgbaHex: 0xFFD66A78),
                innerShadow: Color(hex: 0xE59A00),
                stroke: nil,
                topSideStroke: nil
            )
        case .coral:
            return AppActionButtonPalette(
                fill: AppTheme.coral,
                label: Color(hex: 0xAF0036),
                topGlowStart: Color(rgbaHex: 0xFF807687),
                topGlowEnd: Color(rgbaHex: 0xFFFFFF00),
                innerShadow: Color(hex: 0xED3A41),
                stroke: nil,
                topSideStroke: nil
            )
        case .orange:
            return AppActionButtonPalette(
                fill: AppTheme.orange,
                label: Color(hex: 0xBF1400),
                topGlowStart: Color(rgbaHex: 0xFEAC5B87),
                topGlowEnd: Color(rgbaHex: 0xFFFFFF00),
                innerShadow: Color(hex: 0xFF7648),
                stroke: nil,
                topSideStroke: nil
            )
        case .ai:
            return AppActionButtonPalette(
                fill: AppTheme.aiPurple,
                label: Color(hex: 0x6D10C1),
                topGlowStart: Color(rgbaHex: 0xFFFFFF88),
                topGlowEnd: Color(rgbaHex: 0xC47EFF87),
                innerShadow: Color(rgbaHex: 0xAB4EFFB2),
                stroke: nil,
                topSideStroke: nil
            )
        case .pink:
            return AppActionButtonPalette(
                fill: AppTheme.pink,
                label: Color(hex: 0xC101A4),
                topGlowStart: Color(rgbaHex: 0xFFFFFF77),
                topGlowEnd: Color(rgbaHex: 0xFF55FF77),
                innerShadow: Color(hex: 0xF65AE5),
                stroke: nil,
                topSideStroke: nil
            )
        case .mint:
            return AppActionButtonPalette(
                fill: AppTheme.mint,
                label: Color(hex: 0x00737D),
                topGlowStart: Color(rgbaHex: 0xFFFFFF77),
                topGlowEnd: Color(rgbaHex: 0x13FFAE73),
                innerShadow: Color(rgbaHex: 0x04B3A9C2),
                stroke: nil,
                topSideStroke: nil
            )
        case .neutralLight:
            return AppActionButtonPalette(
                fill: AppTheme.surfaceStrong,
                label: AppTheme.contentPrimary,
                topGlowStart: Self.neutralSurfaceTopGlowStart,
                topGlowEnd: Self.neutralSurfaceTopGlowEnd,
                innerShadow: AppTheme.surfaceDock,
                stroke: AppTheme.surfaceBorder,
                topSideStroke: nil
            )
        case .neutralLightWithBorder:
            return AppActionButtonPalette(
                fill: AppTheme.surfaceStrong,
                label: AppTheme.contentPrimary,
                topGlowStart: Self.neutralSurfaceTopGlowStart,
                topGlowEnd: Self.neutralSurfaceTopGlowEnd,
                innerShadow: AppTheme.surfaceDock,
                stroke: nil,
                topSideStroke: Self.neutralTopSideStroke
            )
        case .neutralDark:
            return AppActionButtonPalette(
                fill: AppTheme.deepWater,
                label: .white,
                topGlowStart: Color(rgbaHex: 0xFFFFFF87),
                topGlowEnd: Color(rgbaHex: 0x515F9287),
                innerShadow: Color(rgbaHex: 0x465383C2),
                stroke: nil,
                topSideStroke: nil
            )
        }
    }
}

enum AppActionButtonSize: CaseIterable, Identifiable {
    case large
    case medium
    case small

    var id: String { title }

    var title: String {
        switch self {
        case .large: return "Large"
        case .medium: return "Medium"
        case .small: return "Small"
        }
    }

    var metrics: AppActionButtonMetrics {
        switch self {
        case .large:
            return AppActionButtonMetrics(
                fontSize: 21,
                cornerRadius: 16,
                horizontalPadding: 12,
                verticalPadding: 12,
                minimumHeight: 64,
                innerShadowHeight: 4,
                dropShadowYOffset: 3,
                pressedYOffset: 2,
                iconSize: 36,
                iconSpacing: 12
            )
        case .medium:
            return AppActionButtonMetrics(
                fontSize: 17,
                cornerRadius: 8,
                horizontalPadding: 8,
                verticalPadding: 8,
                minimumHeight: 44,
                innerShadowHeight: 2,
                dropShadowYOffset: 1.5,
                pressedYOffset: 1.5,
                iconSize: 29,
                iconSpacing: 8
            )
        case .small:
            return AppActionButtonMetrics(
                fontSize: 15,
                cornerRadius: 6,
                horizontalPadding: 8,
                verticalPadding: 4,
                minimumHeight: 30,
                innerShadowHeight: 1.5,
                dropShadowYOffset: 1.5,
                pressedYOffset: 1.5,
                iconSize: 26,
                iconSpacing: 4
            )
        }
    }
}

struct AppActionButtonMetrics {
    let fontSize: CGFloat
    let cornerRadius: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let minimumHeight: CGFloat
    let innerShadowHeight: CGFloat
    let dropShadowYOffset: CGFloat
    let pressedYOffset: CGFloat
    let iconSize: CGFloat
    let iconSpacing: CGFloat

    var iconOnlyFrameSize: CGFloat {
        minimumHeight
    }
}

struct AppActionButton: View {
    let title: String
    let coloredIconAssetName: String?
    let systemImage: String?
    let scene: AppActionButtonScene
    let size: AppActionButtonSize
    let haptic: AppActionButtonHaptic
    let action: () -> Void

    init(
        _ title: String,
        coloredIconAssetName: String? = nil,
        systemImage: String? = nil,
        scene: AppActionButtonScene,
        size: AppActionButtonSize = .large,
        haptic: AppActionButtonHaptic = .defaultTap,
        action: @escaping () -> Void = {}
    ) {
        self.title = title
        self.coloredIconAssetName = coloredIconAssetName
        self.systemImage = systemImage
        self.scene = scene
        self.size = size
        self.haptic = haptic
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            AppActionButtonLabel(
                title: title,
                coloredIconAssetName: coloredIconAssetName,
                systemImage: systemImage,
                size: size
            )
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(AppActionButtonStyle(scene: scene, size: size, haptic: haptic))
        .frame(maxWidth: .infinity)
    }
}

struct AppActionButtonSurface: View {
    let title: String
    let coloredIconAssetName: String?
    let systemImage: String?
    let scene: AppActionButtonScene
    let size: AppActionButtonSize
    let isEnabled: Bool

    init(
        _ title: String,
        coloredIconAssetName: String? = nil,
        systemImage: String? = nil,
        scene: AppActionButtonScene,
        size: AppActionButtonSize = .large,
        isEnabled: Bool = true
    ) {
        self.title = title
        self.coloredIconAssetName = coloredIconAssetName
        self.systemImage = systemImage
        self.scene = scene
        self.size = size
        self.isEnabled = isEnabled
    }

    var body: some View {
        AppActionButtonFace(
            scene: scene,
            size: size,
            isPressed: false,
            isEnabled: isEnabled
        ) {
            AppActionButtonLabel(
                title: title,
                coloredIconAssetName: coloredIconAssetName,
                systemImage: systemImage,
                size: size
            )
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }
}

struct AppActionIconButton: View {
    let coloredIconAssetName: String?
    let systemImage: String?
    let scene: AppActionButtonScene
    let size: AppActionButtonSize
    let haptic: AppActionButtonHaptic
    let action: () -> Void

    init(
        coloredIconAssetName: String? = nil,
        systemImage: String? = nil,
        scene: AppActionButtonScene = .neutralLight,
        size: AppActionButtonSize = .medium,
        haptic: AppActionButtonHaptic = .defaultTap,
        action: @escaping () -> Void = {}
    ) {
        self.coloredIconAssetName = coloredIconAssetName
        self.systemImage = systemImage
        self.scene = scene
        self.size = size
        self.haptic = haptic
        self.action = action
    }

    var body: some View {
        let metrics = size.metrics

        Button(action: action) {
            ZStack {
                if let coloredIconAssetName {
                    AppColoredIcon(assetName: coloredIconAssetName, size: metrics.iconSize)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: metrics.iconSize * 0.62, weight: .black))
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(AppActionButtonStyle(scene: scene, size: size, haptic: haptic))
        .frame(width: metrics.iconOnlyFrameSize, height: metrics.iconOnlyFrameSize)
    }
}

struct AppActionButtonLabel: View {
    let title: String
    let coloredIconAssetName: String?
    let systemImage: String?
    let size: AppActionButtonSize

    private var metrics: AppActionButtonMetrics {
        size.metrics
    }

    private var hasIcon: Bool {
        coloredIconAssetName != nil || systemImage != nil
    }

    var body: some View {
        HStack(spacing: hasIcon ? metrics.iconSpacing : 0) {
            if let coloredIconAssetName {
                AppColoredIcon(assetName: coloredIconAssetName, size: metrics.iconSize)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: metrics.iconSize * 0.58, weight: .black))
                    .frame(width: metrics.iconSize, height: metrics.iconSize)
                    .accessibilityHidden(true)
            }

            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
        }
    }
}

enum AppActionButtonHaptic {
    case defaultTap
    case none

    func trigger() {
        switch self {
        case .defaultTap:
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.prepare()
            generator.impactOccurred(intensity: 0.65)
        case .none:
            break
        }
    }
}

struct AppActionButtonStyle: ButtonStyle {
    let scene: AppActionButtonScene
    let size: AppActionButtonSize
    let haptic: AppActionButtonHaptic

    func makeBody(configuration: Configuration) -> some View {
        AppActionButtonStyleBody(
            configuration: configuration,
            scene: scene,
            size: size,
            haptic: haptic
        )
    }
}

private struct AppActionButtonStyleBody: View {
    @Environment(\.isEnabled) private var isEnabled

    let configuration: ButtonStyle.Configuration
    let scene: AppActionButtonScene
    let size: AppActionButtonSize
    let haptic: AppActionButtonHaptic

    var body: some View {
        let isPressed = configuration.isPressed && isEnabled

        AppActionButtonFace(
            scene: scene,
            size: size,
            isPressed: isPressed,
            isEnabled: isEnabled
        ) {
            configuration.label
        }
            .modifier(PressDownHapticModifier(isPressed: isPressed, haptic: haptic))
    }
}

private struct AppActionButtonFace<Label: View>: View {
    let scene: AppActionButtonScene
    let size: AppActionButtonSize
    let isPressed: Bool
    let isEnabled: Bool
    let label: Label

    init(
        scene: AppActionButtonScene,
        size: AppActionButtonSize,
        isPressed: Bool,
        isEnabled: Bool,
        @ViewBuilder label: () -> Label
    ) {
        self.scene = scene
        self.size = size
        self.isPressed = isPressed
        self.isEnabled = isEnabled
        self.label = label()
    }

    var body: some View {
        let palette = scene.palette
        let metrics = size.metrics
        let shape = RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)

        label
            .font(.system(size: metrics.fontSize, weight: .bold))
            .foregroundStyle(palette.label)
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.vertical, metrics.verticalPadding)
            .frame(minHeight: metrics.minimumHeight)
            .background(
                LinearGradient(
                    stops: [
                        .init(color: isEnabled ? palette.topGlowStart : palette.topGlowStart.opacity(0.45), location: 0),
                        .init(color: isEnabled ? palette.topGlowEnd : palette.topGlowEnd.opacity(0.45), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .background(palette.fill)
            .overlay {
                if isEnabled {
                    BottomInsetShadowBand(
                        cornerRadius: metrics.cornerRadius,
                        bandHeight: metrics.innerShadowHeight
                    )
                    .fill(palette.innerShadow, style: FillStyle(eoFill: true))
                }
            }
            .overlay {
                if let stroke = palette.stroke {
                    shape.stroke(stroke, lineWidth: 1)
                }
            }
            .overlay {
                if let topSideStroke = palette.topSideStroke {
                    TopSideBorderShape(cornerRadius: metrics.cornerRadius)
                        .stroke(isEnabled ? topSideStroke : topSideStroke.opacity(0.45), lineWidth: 1)
                }
            }
            .clipShape(shape)
            .shadow(
                color: isPressed ? .clear : AppActionButtonPalette.dropShadow,
                radius: 0,
                x: 0,
                y: isEnabled ? metrics.dropShadowYOffset : 0
            )
            .scaleEffect(isPressed ? 0.985 : 1)
            .offset(y: isPressed ? metrics.pressedYOffset : 0)
            .opacity(isEnabled ? 1 : 0.5)
            .animation(.easeOut(duration: 0.12), value: isPressed)
    }
}

struct PressDownHapticModifier: ViewModifier {
    let isPressed: Bool
    let haptic: AppActionButtonHaptic

    @State private var hasTriggeredForCurrentPress = false

    func body(content: Content) -> some View {
        content
            .onChange(of: isPressed, initial: true) { _, newValue in
                if newValue {
                    guard !hasTriggeredForCurrentPress else { return }
                    hasTriggeredForCurrentPress = true
                    haptic.trigger()
                } else {
                    hasTriggeredForCurrentPress = false
                }
            }
    }
}

struct BottomInsetShadowBand: Shape {
    let cornerRadius: CGFloat
    let bandHeight: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let outer = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let shiftedUp = CGRect(origin: CGPoint(x: rect.minX, y: rect.minY - bandHeight), size: rect.size)

        path.addPath(outer.path(in: rect))
        path.addPath(outer.path(in: shiftedUp))
        return path
    }
}

struct TopSideBorderShape: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset = 0.5
        let radius = max(cornerRadius - inset, 0)

        path.move(to: CGPoint(x: rect.minX + inset, y: rect.maxY - cornerRadius))
        path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.minY + cornerRadius))
        path.addArc(
            center: CGPoint(x: rect.minX + cornerRadius, y: rect.minY + cornerRadius),
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY + inset))
        path.addArc(
            center: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY + cornerRadius),
            radius: radius,
            startAngle: .degrees(270),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY - cornerRadius))

        return path
    }
}

struct GalleryEyebrow: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(AppTheme.deepWater)
    }
}

struct SectionHeader: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(AppTheme.contentAccent)
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(AppTheme.contentPrimary)
        }
    }
}

struct BulletRow: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(AppTheme.contentAccent)
                .frame(width: 5, height: 5)
                .padding(.top, 7)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.contentPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
