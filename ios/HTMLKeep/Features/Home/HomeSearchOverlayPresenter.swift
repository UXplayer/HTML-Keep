import SwiftUI
import UIKit

@MainActor
final class HomeSearchOverlayPresenter: ObservableObject {
    private var pendingPresentation: DispatchWorkItem?
    private weak var previousKeyWindow: UIWindow?
    private var window: UIWindow?
    private var model: HomeSearchOverlayModel?
    private var configuration: HomeSearchOverlayConfiguration?
    private var onDidDismiss: (() -> Void)?

    var isPresented: Bool {
        window != nil
    }

    func present(
        pages: [WebPage],
        projectIconURL: @escaping (WebPage) -> URL?,
        hasFullContentSearchIndex: Bool,
        searchResults: @escaping (String, WebPageSearchScope) -> [WebPageSearchResult],
        onSearchFullContent: @escaping () async -> Void,
        onSelectEntry: @escaping (WebPage, WebPageEntry) -> Void,
        initialProgress: CGFloat,
        initialCardScale: CGFloat?,
        animated: Bool,
        focusWhenSettled: Bool,
        activateAfterAnimation: Bool,
        onDidDismiss: @escaping () -> Void
    ) {
        if window != nil {
            if !animated {
                updateInteractiveProgress(
                    initialProgress,
                    cardScale: initialCardScale ?? Self.defaultCardScale(for: initialProgress)
                )
            }
            return
        }
        guard let windowScene = Self.activeWindowScene else {
            let workItem = DispatchWorkItem { [weak self] in
                self?.present(
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
                    onDidDismiss: onDidDismiss
                )
            }
            pendingPresentation = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
            return
        }
        pendingPresentation?.cancel()
        pendingPresentation = nil
        self.onDidDismiss = onDidDismiss

        previousKeyWindow = Self.keyWindow

        let overlayWindow = UIWindow(windowScene: windowScene)
        overlayWindow.frame = windowScene.coordinateSpace.bounds
        overlayWindow.windowLevel = .alert + 1
        overlayWindow.backgroundColor = .clear
        overlayWindow.isUserInteractionEnabled = focusWhenSettled

        let overlayModel = HomeSearchOverlayModel(progress: initialProgress)
        overlayModel.cardScale = initialCardScale
        let overlayConfiguration = HomeSearchOverlayConfiguration(
            windowScene: windowScene,
            pages: pages
        )

        let hostingController = UIHostingController(
            rootView: HomeSearchOverlayView(
                model: overlayModel,
                configuration: overlayConfiguration,
                projectIconURL: projectIconURL,
                hasFullContentSearchIndex: hasFullContentSearchIndex,
                searchResults: searchResults,
                onSearchFullContent: onSearchFullContent,
                onSelectEntry: onSelectEntry,
                onDismiss: { [weak self] completion in
                    self?.dismissAnimated(completion: completion)
                }
            )
        )
        hostingController.view.backgroundColor = .clear
        hostingController.view.frame = overlayWindow.bounds
        hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hostingController.safeAreaRegions = [.container]

        overlayWindow.rootViewController = hostingController
        if focusWhenSettled {
            overlayWindow.makeKeyAndVisible()
        } else {
            overlayWindow.isHidden = false
        }
        window = overlayWindow
        model = overlayModel
        configuration = overlayConfiguration

        if animated {
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: homeSearchOverlayOpenAnimationDuration)) {
                    overlayModel.isDismissing = false
                    overlayModel.cardScale = nil
                    overlayModel.setProgress(1, force: true)
                }
            }
            if activateAfterAnimation {
                DispatchQueue.main.asyncAfter(deadline: .now() + homeSearchOverlayOpenAnimationDuration + 0.03) { [weak self, weak overlayModel] in
                    guard let self,
                          self.model === overlayModel,
                          overlayModel?.progress == 1 else {
                        return
                    }
                    self.activateOverlayAndRequestFocus()
                }
            }
        }
        if focusWhenSettled {
            requestFocusAfterOpening()
        }
    }

    func updateInteractiveProgress(_ progress: CGFloat, cardScale: CGFloat) {
        model?.cardScale = cardScale
        model?.isDismissing = false
        model?.setProgress(Self.clampedProgress(progress))
    }

    func finishInteractiveOpening(focusDelay: TimeInterval = 0.28) {
        guard let model else { return }
        window?.isUserInteractionEnabled = true
        window?.makeKey()
        withAnimation(.easeInOut(duration: homeSearchOverlaySettleAnimationDuration)) {
            model.isDismissing = false
            model.cardScale = 1
            model.setProgress(1, force: true)
        }
        requestFocusAfterOpening(after: focusDelay)
    }

    func activateInteractiveKeyboard() {
        guard let model else { return }
        window?.isUserInteractionEnabled = true
        window?.makeKey()
        model.focusRequestID += 1
    }

    func deactivateInteractiveKeyboard() {
        guard let model else { return }
        model.focusRequestID = 0
        window?.endEditing(true)
        window?.isUserInteractionEnabled = false
        previousKeyWindow?.makeKey()
    }

    func cancelInteractiveOpening(animated: Bool = true) {
        if animated {
            dismissAnimated(completion: {})
        } else {
            model?.cardScale = nil
            model?.setProgress(0, force: true)
            dismissImmediately()
        }
    }

    private func activateOverlayAndRequestFocus() {
        window?.isUserInteractionEnabled = true
        window?.makeKey()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, self.model?.progress == 1 else { return }
            self.model?.focusRequestID += 1
        }
    }

    private func dismissAnimated(completion: @escaping () -> Void) {
        guard let model else {
            dismissImmediately()
            completion()
            return
        }

        model.focusRequestID = 0
        withAnimation(.easeInOut(duration: homeSearchOverlayCloseAnimationDuration)) {
            model.isDismissing = true
            model.cardScale = nil
            model.setProgress(0, force: true)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + homeSearchOverlayCloseAnimationDuration) { [weak self] in
            self?.dismissImmediately()
            completion()
        }
    }

    private func dismissImmediately() {
        pendingPresentation?.cancel()
        pendingPresentation = nil
        window?.isHidden = true
        window = nil
        model = nil
        configuration = nil
        previousKeyWindow?.makeKey()
        previousKeyWindow = nil
        let onDidDismiss = onDidDismiss
        self.onDidDismiss = nil
        onDidDismiss?()
    }

    private func requestFocusAfterOpening(after delay: TimeInterval = 0.28) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.model?.progress == 1 else { return }
            self.model?.focusRequestID += 1
        }
    }

    private static func clampedProgress(_ progress: CGFloat) -> CGFloat {
        min(max(progress, 0), 1)
    }

    private static func defaultCardScale(for progress: CGFloat) -> CGFloat {
        let clampedProgress = clampedProgress(progress)
        return 1 + homeSearchOverlayScaleExpansion * (1 - clampedProgress)
    }

    private static var activeWindowScene: UIWindowScene? {
        if let keyWindowScene = keyWindow?.windowScene {
            return keyWindowScene
        }

        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }
}

@MainActor
final class HomeSearchOverlayModel: ObservableObject {
    @Published var progress: CGFloat
    @Published var cardScale: CGFloat?
    @Published var focusRequestID = 0
    @Published var isDismissing = false

    init(progress: CGFloat) {
        self.progress = min(max(progress, 0), 1)
    }

    func setProgress(_ progress: CGFloat, force: Bool = false) {
        let clampedProgress = min(max(progress, 0), 1)
        guard force
            || clampedProgress == 0
            || clampedProgress == 1
            || abs(self.progress - clampedProgress) >= homeSearchProgressUpdateTolerance else {
            return
        }
        self.progress = clampedProgress
    }
}

struct HomeSearchOverlayConfiguration {
    let screenSize: CGSize
    let cardMaxHeight: CGFloat
    let contentMaxHeight: CGFloat
    let topInset: CGFloat
    let recommendations: [WebPage]

    init(windowScene: UIWindowScene, pages: [WebPage]) {
        let screenSize = windowScene.coordinateSpace.bounds.size
        let cardMaxHeight = max(288, min(screenSize.height * 0.42, 330))
        let safeAreaTop = windowScene.windows.first(where: \.isKeyWindow)?.safeAreaInsets.top
            ?? windowScene.windows.first?.safeAreaInsets.top
            ?? 0

        self.screenSize = screenSize
        self.cardMaxHeight = cardMaxHeight
        self.contentMaxHeight = max(150, cardMaxHeight - 72)
        self.topInset = max(safeAreaTop + 14, 60)
        self.recommendations = Array(
            pages
                .sorted { lhs, rhs in
                    if lhs.lastOpenedAt != rhs.lastOpenedAt {
                        return lhs.lastOpenedAt > rhs.lastOpenedAt
                    }
                    return lhs.createdAt > rhs.createdAt
                }
                .prefix(homeSearchVisibleRowCount)
        )
    }
}
