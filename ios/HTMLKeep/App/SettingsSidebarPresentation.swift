import SideMenu
import SwiftUI
import UIKit

private let settingsSideMenuDimAlpha: CGFloat = 0.03
private let settingsSideMenuLightShadowOpacity: Float = 0.18
private let settingsSideMenuDarkEdgeBorderAlpha: CGFloat = 0.20
private let settingsSideMenuEdgeBorderLayerName = "HTMLKeep.SettingsSideMenuEdgeBorder"

struct SettingsPopoverContainer<MainContent: View, SidebarContent: View>: UIViewControllerRepresentable {
    let presentationRequestID: Int
    let dismissalRequestID: Int
    let anchorItem: UIBarButtonItem?
    let fallbackAnchorOpensFromLeft: Bool
    let preferredColorScheme: ColorScheme?
    let onWillPresent: () -> Void
    let onDismiss: () -> Void
    let mainContent: MainContent
    let sidebarContent: SidebarContent

    init(
        presentationRequestID: Int,
        dismissalRequestID: Int,
        anchorItem: UIBarButtonItem?,
        fallbackAnchorOpensFromLeft: Bool,
        preferredColorScheme: ColorScheme?,
        onWillPresent: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        @ViewBuilder mainContent: () -> MainContent,
        @ViewBuilder sidebar: () -> SidebarContent
    ) {
        self.presentationRequestID = presentationRequestID
        self.dismissalRequestID = dismissalRequestID
        self.anchorItem = anchorItem
        self.fallbackAnchorOpensFromLeft = fallbackAnchorOpensFromLeft
        self.preferredColorScheme = preferredColorScheme
        self.onWillPresent = onWillPresent
        self.onDismiss = onDismiss
        self.mainContent = mainContent()
        self.sidebarContent = sidebar()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> SettingsPopoverContainerViewController<MainContent, SidebarContent> {
        let viewController = SettingsPopoverContainerViewController<MainContent, SidebarContent>()
        viewController.onPopoverWillPresent = onWillPresent
        viewController.onPopoverDismissed = onDismiss
        viewController.preferredColorScheme = preferredColorScheme
        viewController.configure(mainContent: mainContent, sidebarContent: sidebarContent)
        context.coordinator.presentedRequestID = presentationRequestID
        context.coordinator.dismissedRequestID = dismissalRequestID
        return viewController
    }

    func updateUIViewController(
        _ viewController: SettingsPopoverContainerViewController<MainContent, SidebarContent>,
        context: Context
    ) {
        viewController.onPopoverWillPresent = onWillPresent
        viewController.onPopoverDismissed = onDismiss
        viewController.fallbackAnchorOpensFromLeft = fallbackAnchorOpensFromLeft
        viewController.preferredColorScheme = preferredColorScheme
        viewController.configure(mainContent: mainContent, sidebarContent: sidebarContent)

        if dismissalRequestID != context.coordinator.dismissedRequestID {
            context.coordinator.dismissedRequestID = dismissalRequestID
            viewController.dismissPopover()
        }

        guard presentationRequestID != context.coordinator.presentedRequestID else {
            return
        }

        context.coordinator.presentedRequestID = presentationRequestID
        viewController.togglePopover(anchorItem: anchorItem, sidebarContent: sidebarContent)
    }

    final class Coordinator {
        var presentedRequestID = 0
        var dismissedRequestID = 0
    }
}

final class SettingsPopoverContainerViewController<MainContent: View, SidebarContent: View>:
    UIViewController,
    UIPopoverPresentationControllerDelegate
{
    private var mainHostingController: UIHostingController<MainContent>?
    private var sidebarHostingController: UIHostingController<SidebarContent>?
    var onPopoverWillPresent: (() -> Void)?
    var onPopoverDismissed: (() -> Void)?
    var fallbackAnchorOpensFromLeft = true
    var preferredColorScheme: ColorScheme? {
        didSet {
            applyPreferredUserInterfaceStyle()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

    func configure(mainContent: MainContent, sidebarContent: SidebarContent) {
        if let mainHostingController {
            mainHostingController.rootView = mainContent
        } else {
            let hostingController = UIHostingController(rootView: mainContent)
            hostingController.view.backgroundColor = .clear
            hostingController.overrideUserInterfaceStyle = preferredColorScheme.settingsUserInterfaceStyle
            mainHostingController = hostingController
            addChild(hostingController)
            view.addSubview(hostingController.view)
            hostingController.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
                hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            hostingController.didMove(toParent: self)
        }

        if let sidebarHostingController {
            sidebarHostingController.rootView = sidebarContent
        } else {
            let hostingController = UIHostingController(rootView: sidebarContent)
            hostingController.view.backgroundColor = .clear
            hostingController.overrideUserInterfaceStyle = preferredColorScheme.settingsUserInterfaceStyle
            sidebarHostingController = hostingController
        }

        applyPreferredUserInterfaceStyle()
    }

    func togglePopover(anchorItem: UIBarButtonItem?, sidebarContent: SidebarContent) {
        if presentedViewController != nil {
            dismissPopover()
        } else {
            presentPopover(anchorItem: anchorItem, sidebarContent: sidebarContent)
        }
    }

    private func presentPopover(anchorItem: UIBarButtonItem?, sidebarContent: SidebarContent) {
        onPopoverWillPresent?()
        let hostingController = freshSidebarHostingController(sidebarContent: sidebarContent)

        hostingController.modalPresentationStyle = .popover
        hostingController.preferredContentSize = preferredPopoverContentSize()

        guard let popover = hostingController.popoverPresentationController else {
            return
        }

        popover.delegate = self
        popover.permittedArrowDirections = .any
        if let anchorItem {
            popover.sourceItem = anchorItem
        } else {
            popover.sourceView = view
            let fallbackX = fallbackAnchorOpensFromLeft ? view.bounds.minX + 8 : view.bounds.maxX - 44
            popover.sourceRect = CGRect(
                x: fallbackX,
                y: view.safeAreaInsets.top + 18,
                width: 36,
                height: 36
            )
        }

        present(hostingController, animated: true)
    }

    private func freshSidebarHostingController(sidebarContent: SidebarContent) -> UIHostingController<SidebarContent> {
        let hostingController = UIHostingController(rootView: sidebarContent)
        hostingController.view.backgroundColor = .clear
        hostingController.overrideUserInterfaceStyle = preferredColorScheme.settingsUserInterfaceStyle
        sidebarHostingController = hostingController
        return hostingController
    }

    private func applyPreferredUserInterfaceStyle() {
        let userInterfaceStyle = preferredColorScheme.settingsUserInterfaceStyle
        overrideUserInterfaceStyle = userInterfaceStyle
        mainHostingController?.overrideUserInterfaceStyle = userInterfaceStyle
        sidebarHostingController?.overrideUserInterfaceStyle = userInterfaceStyle
        presentedViewController?.overrideUserInterfaceStyle = userInterfaceStyle
    }

    func dismissPopover() {
        guard presentedViewController != nil else {
            return
        }
        dismiss(animated: true) { [weak self] in
            self?.onPopoverDismissed?()
        }
    }

    private func preferredPopoverContentSize() -> CGSize {
        let height = view.bounds.height > 0 ? min(view.bounds.height - 96, 720) : 640
        return CGSize(width: 360, height: max(height, 520))
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        onPopoverDismissed?()
    }

    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        .none
    }
}

struct SettingsSideMenuContainer<MainContent: View, SidebarContent: View>: UIViewControllerRepresentable {
    let presentationRequestID: Int
    let dismissalRequestID: Int
    let opensFromLeft: Bool
    let preferredColorScheme: ColorScheme?
    let onWillPresent: () -> Void
    let onDismiss: () -> Void
    let mainContent: MainContent
    let sidebarContent: SidebarContent

    init(
        presentationRequestID: Int,
        dismissalRequestID: Int,
        opensFromLeft: Bool,
        preferredColorScheme: ColorScheme?,
        onWillPresent: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        @ViewBuilder mainContent: () -> MainContent,
        @ViewBuilder sidebar: () -> SidebarContent
    ) {
        self.presentationRequestID = presentationRequestID
        self.dismissalRequestID = dismissalRequestID
        self.opensFromLeft = opensFromLeft
        self.preferredColorScheme = preferredColorScheme
        self.onWillPresent = onWillPresent
        self.onDismiss = onDismiss
        self.mainContent = mainContent()
        self.sidebarContent = sidebar()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> SideMenuContainerViewController<MainContent, SidebarContent> {
        let viewController = SideMenuContainerViewController<MainContent, SidebarContent>()
        viewController.onMenuWillPresent = onWillPresent
        viewController.onMenuDismissed = onDismiss
        viewController.preferredColorScheme = preferredColorScheme
        viewController.configure(mainContent: mainContent, sidebarContent: sidebarContent, opensFromLeft: opensFromLeft)
        context.coordinator.presentedRequestID = presentationRequestID
        context.coordinator.dismissedRequestID = dismissalRequestID
        return viewController
    }

    func updateUIViewController(
        _ viewController: SideMenuContainerViewController<MainContent, SidebarContent>,
        context: Context
    ) {
        viewController.onMenuWillPresent = onWillPresent
        viewController.onMenuDismissed = onDismiss
        viewController.preferredColorScheme = preferredColorScheme
        viewController.configure(mainContent: mainContent, sidebarContent: sidebarContent, opensFromLeft: opensFromLeft)

        if dismissalRequestID != context.coordinator.dismissedRequestID {
            context.coordinator.dismissedRequestID = dismissalRequestID
            viewController.dismissMenu()
        }

        guard presentationRequestID != context.coordinator.presentedRequestID else {
            return
        }

        context.coordinator.presentedRequestID = presentationRequestID
        viewController.presentMenu(sidebarContent: sidebarContent, opensFromLeft: opensFromLeft)
    }

    final class Coordinator {
        var presentedRequestID = 0
        var dismissedRequestID = 0
    }
}

final class SideMenuContainerViewController<MainContent: View, SidebarContent: View>: UIViewController {
    private var mainHostingController: UIHostingController<MainContent>?
    private var sidebarHostingController: UIHostingController<SidebarContent>?
    private var sideMenuNavigationController: SideMenuNavigationController?
    private let menuLifecycleDelegate = SettingsSideMenuLifecycleDelegate()
    private let dimmingView = SettingsSideMenuDimmingView()
    private var edgePanGestures: [UIScreenEdgePanGestureRecognizer] = []
    private var userInterfaceStyleRegistration: UITraitChangeRegistration?
    private var menuOpensFromLeft: Bool?
    var preferredColorScheme: ColorScheme? {
        didSet {
            applyPreferredUserInterfaceStyle()
        }
    }
    var onMenuWillPresent: (() -> Void)? {
        didSet {
            menuLifecycleDelegate.onWillAppear = onMenuWillPresent
        }
    }
    var onMenuDismissed: (() -> Void)? {
        didSet {
            menuLifecycleDelegate.onDidDisappear = onMenuDismissed
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        userInterfaceStyleRegistration = registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
            (viewController: SideMenuContainerViewController<MainContent, SidebarContent>, _) in
            viewController.updateMenuSurfaceAppearanceIfNeeded()
        }
    }

    func configure(mainContent: MainContent, sidebarContent: SidebarContent, opensFromLeft: Bool) {
        if let mainHostingController {
            mainHostingController.rootView = mainContent
        } else {
            let hostingController = UIHostingController(rootView: mainContent)
            hostingController.view.backgroundColor = .clear
            hostingController.overrideUserInterfaceStyle = preferredColorScheme.settingsUserInterfaceStyle
            addChild(hostingController)
            view.addSubview(hostingController.view)
            hostingController.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
                hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            hostingController.didMove(toParent: self)
            mainHostingController = hostingController
            installDimmingViewIfNeeded()
            installEdgeGesturesIfNeeded()
        }

        if menuOpensFromLeft != opensFromLeft {
            configureSideMenu(rootViewController: sidebarHostingController, opensFromLeft: opensFromLeft)
        }

        if let sidebarHostingController {
            sidebarHostingController.rootView = sidebarContent
        } else {
            let hostingController = UIHostingController(rootView: sidebarContent)
            hostingController.view.backgroundColor = .clear
            hostingController.overrideUserInterfaceStyle = preferredColorScheme.settingsUserInterfaceStyle
            sidebarHostingController = hostingController
            configureSideMenu(rootViewController: hostingController, opensFromLeft: opensFromLeft)
        }

        applyPreferredUserInterfaceStyle()
        updateMenuWidth()
    }

    func presentMenu(sidebarContent: SidebarContent, opensFromLeft: Bool) {
        onMenuWillPresent?()
        rebuildSideMenu(sidebarContent: sidebarContent, opensFromLeft: opensFromLeft)

        guard presentedViewController == nil, let sideMenuNavigationController else {
            return
        }

        updateMenuWidth()
        present(sideMenuNavigationController, animated: true)
    }

    func dismissMenu() {
        guard presentedViewController != nil else {
            return
        }

        dismiss(animated: true) { [weak self] in
            self?.onMenuDismissed?()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateMenuWidth()
    }

    private func configuredSideMenu(rootViewController: UIViewController, opensFromLeft: Bool) -> SideMenuNavigationController {
        var settings = SideMenuSettings()
        settings.presentationStyle = .viewSlideOutMenuIn
        settings.presentationStyle.backgroundColor = .clear
        settings.presentationStyle.presentingEndAlpha = 1
        settings.presentingViewControllerUseSnapshot = false
        settings.enableSwipeToDismissGesture = true
        settings.enableTapToDismissGesture = true
        settings.statusBarEndAlpha = 0
        settings.presentDuration = 0.28
        settings.dismissDuration = 0.24
        settings.completeGestureDuration = 0.24

        let sideMenu = SideMenuNavigationController(rootViewController: rootViewController, settings: settings)
        sideMenu.overrideUserInterfaceStyle = preferredColorScheme.settingsUserInterfaceStyle
        let presentationStyle = SettingsSideMenuPresentationStyle()
        presentationStyle.dimmingView = dimmingView
        sideMenu.presentationStyle = presentationStyle
        sideMenu.leftSide = opensFromLeft
        sideMenu.sideMenuDelegate = menuLifecycleDelegate
        sideMenu.navigationBar.isHidden = true
        return sideMenu
    }

    private func configureSideMenu(rootViewController: UIViewController?, opensFromLeft: Bool) {
        guard let rootViewController else { return }

        clearSideMenuRegistration()
        removeEdgeGestures()

        let sideMenu = configuredSideMenu(rootViewController: rootViewController, opensFromLeft: opensFromLeft)
        sideMenuNavigationController = sideMenu
        menuOpensFromLeft = opensFromLeft
        dimmingView.fadesFromLeft = opensFromLeft

        if opensFromLeft {
            SideMenuManager.default.leftMenuNavigationController = sideMenu
        } else {
            SideMenuManager.default.rightMenuNavigationController = sideMenu
        }

        installEdgeGesturesIfNeeded()
    }

    private func rebuildSideMenu(sidebarContent: SidebarContent, opensFromLeft: Bool) {
        let hostingController = UIHostingController(rootView: sidebarContent)
        hostingController.view.backgroundColor = .clear
        hostingController.overrideUserInterfaceStyle = preferredColorScheme.settingsUserInterfaceStyle
        sidebarHostingController = hostingController
        configureSideMenu(rootViewController: hostingController, opensFromLeft: opensFromLeft)
    }

    private func clearSideMenuRegistration() {
        if menuOpensFromLeft == true {
            SideMenuManager.default.leftMenuNavigationController = nil
        } else if menuOpensFromLeft == false {
            SideMenuManager.default.rightMenuNavigationController = nil
        }
    }

    private func removeEdgeGestures() {
        edgePanGestures.forEach { gesture in
            gesture.view?.removeGestureRecognizer(gesture)
        }
        edgePanGestures.removeAll()
    }

    private func installDimmingViewIfNeeded() {
        guard dimmingView.superview == nil else { return }

        dimmingView.backgroundColor = .black
        dimmingView.alpha = 0
        dimmingView.isUserInteractionEnabled = false
        view.addSubview(dimmingView)
        dimmingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dimmingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimmingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimmingView.topAnchor.constraint(equalTo: view.topAnchor),
            dimmingView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func installEdgeGesturesIfNeeded() {
        guard edgePanGestures.isEmpty, sideMenuNavigationController != nil else { return }
        let menuSide: SideMenuManager.PresentDirection = menuOpensFromLeft == false ? .right : .left

        edgePanGestures.append(SideMenuManager.default.addScreenEdgePanGesturesToPresent(
            toView: view,
            forMenu: menuSide
        ))

        if let mainView = mainHostingController?.view {
            edgePanGestures.append(SideMenuManager.default.addScreenEdgePanGesturesToPresent(
                toView: mainView,
                forMenu: menuSide
            ))
        }
    }

    private func updateMenuWidth() {
        let width = view.bounds.width
        guard width > 0 else { return }
        sideMenuNavigationController?.menuWidth = min(width * 0.82, 360).rounded()
        updateMenuSurfaceAppearanceIfNeeded()
    }

    private func updateMenuSurfaceAppearanceIfNeeded() {
        guard let sideMenuNavigationController,
              sideMenuNavigationController.isViewLoaded,
              sideMenuNavigationController.view.bounds.width > 0 else {
            return
        }
        configureSettingsSideMenuSurface(for: sideMenuNavigationController.view)
    }

    private func applyPreferredUserInterfaceStyle() {
        let userInterfaceStyle = preferredColorScheme.settingsUserInterfaceStyle
        overrideUserInterfaceStyle = userInterfaceStyle
        mainHostingController?.overrideUserInterfaceStyle = userInterfaceStyle
        sidebarHostingController?.overrideUserInterfaceStyle = userInterfaceStyle
        sideMenuNavigationController?.overrideUserInterfaceStyle = userInterfaceStyle
        sideMenuNavigationController?.viewControllers.forEach {
            $0.overrideUserInterfaceStyle = userInterfaceStyle
        }
        updateMenuSurfaceAppearanceIfNeeded()
    }
}

private final class SettingsSideMenuLifecycleDelegate: NSObject, SideMenuNavigationControllerDelegate {
    var onWillAppear: (() -> Void)?
    var onDidDisappear: (() -> Void)?

    func sideMenuWillAppear(menu: SideMenuNavigationController, animated: Bool) {
        onWillAppear?()
    }

    func sideMenuDidDisappear(menu: SideMenuNavigationController, animated: Bool) {
        onDidDisappear?()
    }
}

private final class SettingsSideMenuDimmingView: UIView {
    private let maskLayer = CAGradientLayer()
    private let leadingFadeWidth: CGFloat = 24
    var fadesFromLeft = true {
        didSet {
            setNeedsLayout()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isUserInteractionEnabled = false
        layer.mask = maskLayer
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
        isUserInteractionEnabled = false
        layer.mask = maskLayer
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let fadeLocation = bounds.width > 0 ? min(leadingFadeWidth / bounds.width, 1) : 0
        maskLayer.frame = bounds
        maskLayer.startPoint = CGPoint(x: fadesFromLeft ? 0 : 1, y: 0.5)
        maskLayer.endPoint = CGPoint(x: fadesFromLeft ? 1 : 0, y: 0.5)
        maskLayer.colors = [
            UIColor.clear.cgColor,
            UIColor.black.cgColor,
            UIColor.black.cgColor
        ]
        maskLayer.locations = [
            0,
            NSNumber(value: Double(fadeLocation)),
            1
        ]
    }
}

private final class SettingsSideMenuPresentationStyle: SideMenuPresentationStyle {
    weak var dimmingView: UIView?

    required init() {
        super.init()
        menuOnTop = true
        menuTranslateFactor = -1
        presentingTranslateFactor = 1
        backgroundColor = .clear
        presentingEndAlpha = 1
        onTopShadowColor = .black
        onTopShadowRadius = 8
        onTopShadowOpacity = settingsSideMenuLightShadowOpacity
        onTopShadowOffset = .zero
    }

    override func presentationTransitionWillBegin(
        to presentedViewController: UIViewController,
        from presentingViewController: UIViewController
    ) {
        configureSettingsSideMenuSurface(for: presentedViewController.view)
        setOverlayAlpha(0)
    }

    override func presentationTransition(
        to presentedViewController: UIViewController,
        from presentingViewController: UIViewController
    ) {
        configureSettingsSideMenuSurface(for: presentedViewController.view)
        setOverlayAlpha(1)
    }

    override func presentationTransitionDidEnd(
        to presentedViewController: UIViewController,
        from presentingViewController: UIViewController,
        _ completed: Bool
    ) {
        configureSettingsSideMenuSurface(for: presentedViewController.view)
        setOverlayAlpha(completed ? 1 : 0)
    }

    override func dismissalTransitionWillBegin(
        to presentedViewController: UIViewController,
        from presentingViewController: UIViewController
    ) {
        configureSettingsSideMenuSurface(for: presentedViewController.view)
        setOverlayAlpha(1)
    }

    override func dismissalTransition(
        to presentedViewController: UIViewController,
        from presentingViewController: UIViewController
    ) {
        configureSettingsSideMenuSurface(for: presentedViewController.view)
        setOverlayAlpha(0)
    }

    override func dismissalTransitionDidEnd(
        to presentedViewController: UIViewController,
        from presentingViewController: UIViewController,
        _ completed: Bool
    ) {
        setOverlayAlpha(completed ? 0 : 1)
        if completed {
            removeSettingsSideMenuEdgeBorder(from: presentedViewController.view)
        } else {
            configureSettingsSideMenuSurface(for: presentedViewController.view)
        }
    }

    private func setOverlayAlpha(_ progress: CGFloat) {
        dimmingView?.alpha = settingsSideMenuDimAlpha * progress
    }
}

private func configureSettingsSideMenuSurface(for menuView: UIView) {
    let layer = menuView.layer
    layer.shadowPath = UIBezierPath(rect: menuView.bounds).cgPath

    if menuView.traitCollection.userInterfaceStyle == .dark {
        layer.shadowOpacity = 0
        configureSettingsSideMenuEdgeBorder(on: menuView)
    } else {
        layer.shadowOpacity = settingsSideMenuLightShadowOpacity
        removeSettingsSideMenuEdgeBorder(from: menuView)
    }
}

private func configureSettingsSideMenuEdgeBorder(on menuView: UIView) {
    let borderLayer = settingsSideMenuEdgeBorderLayer(on: menuView)
    let screenScale = menuView.window?.screen.scale ?? UIScreen.main.scale
    let borderWidth = 1 / max(screenScale, 1)
    let containerMidX = menuView.superview?.bounds.midX ?? UIScreen.main.bounds.midX
    let menuOpensFromLeft = menuView.frame.midX <= containerMidX
    let borderX = menuOpensFromLeft ? menuView.bounds.maxX - borderWidth : menuView.bounds.minX

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    borderLayer.backgroundColor = UIColor.white
        .withAlphaComponent(settingsSideMenuDarkEdgeBorderAlpha)
        .cgColor
    borderLayer.frame = CGRect(
        x: borderX,
        y: menuView.bounds.minY,
        width: borderWidth,
        height: menuView.bounds.height
    )
    CATransaction.commit()
}

private func settingsSideMenuEdgeBorderLayer(on menuView: UIView) -> CALayer {
    if let existingLayer = menuView.layer.sublayers?.first(where: { $0.name == settingsSideMenuEdgeBorderLayerName }) {
        return existingLayer
    }

    let borderLayer = CALayer()
    borderLayer.name = settingsSideMenuEdgeBorderLayerName
    borderLayer.zPosition = CGFloat.greatestFiniteMagnitude
    menuView.layer.addSublayer(borderLayer)
    return borderLayer
}

private func removeSettingsSideMenuEdgeBorder(from menuView: UIView) {
    menuView.layer.sublayers?
        .filter { $0.name == settingsSideMenuEdgeBorderLayerName }
        .forEach { $0.removeFromSuperlayer() }
}

private extension Optional where Wrapped == ColorScheme {
    var settingsUserInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .some(let colorScheme):
            switch colorScheme {
            case .dark:
                return .dark
            case .light:
                return .light
            @unknown default:
                return .unspecified
            }
        case .none:
            return .unspecified
        }
    }
}
