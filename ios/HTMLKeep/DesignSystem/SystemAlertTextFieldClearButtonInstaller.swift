import SwiftUI
import UIKit

struct SystemAlertTextFieldClearButtonInstaller: UIViewControllerRepresentable {
    let isActive: Bool

    func makeUIViewController(context _: Context) -> SystemAlertTextFieldClearButtonViewController {
        SystemAlertTextFieldClearButtonViewController()
    }

    func updateUIViewController(
        _ uiViewController: SystemAlertTextFieldClearButtonViewController,
        context _: Context
    ) {
        uiViewController.isActive = isActive
        uiViewController.configureIfNeeded()
    }
}

final class SystemAlertTextFieldClearButtonViewController: UIViewController {
    var isActive = false {
        didSet {
            if !isActive {
                configurationID = UUID()
            }
        }
    }

    private var configurationID = UUID()

    override func loadView() {
        let view = UIView()
        view.isHidden = true
        view.isUserInteractionEnabled = false
        self.view = view
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        configureIfNeeded()
    }

    func configureIfNeeded() {
        guard isActive else { return }
        let configurationID = UUID()
        self.configurationID = configurationID
        configureAlertTextFields(configurationID: configurationID, remainingAttempts: 12)
    }

    private func configureAlertTextFields(configurationID: UUID, remainingAttempts: Int) {
        guard isActive, self.configurationID == configurationID else { return }

        if let alertController = view.window?.rootViewController?.presentedAlertController {
            let textFields = alertController.textFields ?? []
            if !textFields.isEmpty {
                textFields.forEach { textField in
                    textField.clearButtonMode = .whileEditing
                }
                return
            }
        }

        guard remainingAttempts > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.configureAlertTextFields(
                configurationID: configurationID,
                remainingAttempts: remainingAttempts - 1
            )
        }
    }
}

private extension UIViewController {
    var presentedAlertController: UIAlertController? {
        if let alertController = self as? UIAlertController {
            return alertController
        }

        if let presentedViewController {
            return presentedViewController.presentedAlertController
        }

        if let navigationController = self as? UINavigationController {
            return navigationController.visibleViewController?.presentedAlertController
        }

        if let tabBarController = self as? UITabBarController {
            return tabBarController.selectedViewController?.presentedAlertController
        }

        return nil
    }
}
