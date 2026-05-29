import SwiftUI
import UIKit

struct SystemNavigationBarMenuInstaller: UIViewControllerRepresentable {
    let onOpenSettings: (UIBarButtonItem?) -> Void
    let onOpenSearch: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onOpenSettings: onOpenSettings, onOpenSearch: onOpenSearch)
    }

    func makeUIViewController(context: Context) -> SystemNavigationBarMenuViewController {
        SystemNavigationBarMenuViewController(coordinator: context.coordinator)
    }

    func updateUIViewController(_ uiViewController: SystemNavigationBarMenuViewController, context: Context) {
        context.coordinator.onOpenSettings = onOpenSettings
        context.coordinator.onOpenSearch = onOpenSearch
        uiViewController.applyMenuItem()
    }

    final class Coordinator: NSObject {
        var onOpenSettings: (UIBarButtonItem?) -> Void
        var onOpenSearch: () -> Void
        var menuItem: UIBarButtonItem?
        var searchItem: UIBarButtonItem?

        init(onOpenSettings: @escaping (UIBarButtonItem?) -> Void, onOpenSearch: @escaping () -> Void) {
            self.onOpenSettings = onOpenSettings
            self.onOpenSearch = onOpenSearch
        }

        @objc func openSettings() {
            onOpenSettings(menuItem)
        }

        @objc func openSearch() {
            onOpenSearch()
        }
    }
}

final class SystemNavigationBarMenuViewController: UIViewController {
    weak var coordinator: SystemNavigationBarMenuInstaller.Coordinator?

    init(coordinator: SystemNavigationBarMenuInstaller.Coordinator) {
        self.coordinator = coordinator
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyMenuItem()
    }

    func applyMenuItem() {
        guard let navigationController,
              let coordinator else {
            return
        }

        guard let homeViewController = owningNavigationStackViewController(in: navigationController),
              navigationController.topViewController === homeViewController else {
            removeMenuItemFromCurrentTopViewController(in: navigationController)
            return
        }

        let settingsItem: UIBarButtonItem
        if let existingItem = coordinator.menuItem {
            settingsItem = existingItem
        } else {
            settingsItem = UIBarButtonItem(
                image: UIImage(systemName: "gearshape"),
                style: .plain,
                target: coordinator,
                action: #selector(SystemNavigationBarMenuInstaller.Coordinator.openSettings)
            )
            coordinator.menuItem = settingsItem
        }
        settingsItem.accessibilityLabel = AppStrings.localized("设置")

        let searchItem: UIBarButtonItem
        if let existingItem = coordinator.searchItem {
            searchItem = existingItem
        } else {
            searchItem = UIBarButtonItem(
                image: UIImage(systemName: "magnifyingglass"),
                style: .plain,
                target: coordinator,
                action: #selector(SystemNavigationBarMenuInstaller.Coordinator.openSearch)
            )
            coordinator.searchItem = searchItem
        }
        searchItem.accessibilityLabel = AppStrings.localized("搜索")

        homeViewController.navigationItem.leftBarButtonItem = settingsItem
        homeViewController.navigationItem.rightBarButtonItem = searchItem
    }

    private func owningNavigationStackViewController(in navigationController: UINavigationController) -> UIViewController? {
        var current: UIViewController? = self
        while let parent = current?.parent, parent !== navigationController {
            current = parent
        }
        return current
    }

    private func removeMenuItemFromCurrentTopViewController(in navigationController: UINavigationController) {
        guard let coordinator,
              let navigationItem = navigationController.topViewController?.navigationItem else {
            return
        }
        let removableItems = [coordinator.menuItem, coordinator.searchItem].compactMap { $0 }

        if let leftItem = navigationItem.leftBarButtonItem,
           removableItems.contains(where: { $0 === leftItem }) {
            navigationItem.leftBarButtonItem = nil
        }
        if let rightItem = navigationItem.rightBarButtonItem,
           removableItems.contains(where: { $0 === rightItem }) {
            navigationItem.rightBarButtonItem = nil
        }
    }
}

#if DEBUG
struct DebugNavigationTitleLongPressInstaller: UIViewControllerRepresentable {
    let onLongPress: () -> Void

    func makeUIViewController(context _: Context) -> DebugNavigationTitleLongPressViewController {
        DebugNavigationTitleLongPressViewController(onLongPress: onLongPress)
    }

    func updateUIViewController(
        _ uiViewController: DebugNavigationTitleLongPressViewController,
        context _: Context
    ) {
        uiViewController.onLongPress = onLongPress
    }

    static func dismantleUIViewController(
        _ uiViewController: DebugNavigationTitleLongPressViewController,
        coordinator _: ()
    ) {
        uiViewController.uninstallLongPressRecognizer()
    }
}

final class DebugNavigationTitleLongPressViewController: UIViewController {
    var onLongPress: () -> Void
    private weak var installedNavigationBar: UINavigationBar?
    private var longPressRecognizer: UILongPressGestureRecognizer?

    init(onLongPress: @escaping () -> Void) {
        self.onLongPress = onLongPress
        super.init(nibName: nil, bundle: nil)
        view.isHidden = true
        view.isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        installLongPressRecognizerIfNeeded()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        uninstallLongPressRecognizer()
    }

    func uninstallLongPressRecognizer() {
        guard let longPressRecognizer else { return }
        installedNavigationBar?.removeGestureRecognizer(longPressRecognizer)
        self.longPressRecognizer = nil
        installedNavigationBar = nil
    }

    private func installLongPressRecognizerIfNeeded() {
        guard let navigationBar = navigationController?.navigationBar else { return }
        guard installedNavigationBar !== navigationBar else { return }

        uninstallLongPressRecognizer()

        let recognizer = UILongPressGestureRecognizer(
            target: self,
            action: #selector(handleLongPress(_:))
        )
        recognizer.minimumPressDuration = 0.7
        recognizer.cancelsTouchesInView = false
        navigationBar.addGestureRecognizer(recognizer)
        installedNavigationBar = navigationBar
        longPressRecognizer = recognizer
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        onLongPress()
    }
}
#endif
