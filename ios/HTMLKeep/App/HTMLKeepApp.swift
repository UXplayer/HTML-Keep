import SwiftUI
import UIKit

@main
struct HTMLKeepApp: App {
    @UIApplicationDelegateAdaptor(HTMLKeepAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
    }
}

final class HTMLKeepAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        if connectingSceneSession.role == .windowApplication {
            configuration.delegateClass = HTMLKeepSceneDelegate.self
        }
        return configuration
    }
}

struct ProjectWidgetLaunchContext {
    let id = UUID()
    let url: URL
    let background: String?
}

@MainActor
final class ProjectWidgetLaunchStore: ObservableObject {
    static let shared = ProjectWidgetLaunchStore()

    @Published private(set) var context: ProjectWidgetLaunchContext?

    private init() {}

    func captureProjectWidgetURL(from urls: [URL]) {
        guard let url = urls.first(where: { $0.scheme == ProjectWidgetShared.openProjectScheme }) else {
            return
        }

        let urlBackground = ProjectWidgetShared.launchBackground(from: url)
        guard let projectID = ProjectWidgetShared.projectID(from: url) else {
            context = ProjectWidgetLaunchContext(url: url, background: urlBackground)
            return
        }

        let snapshot = ProjectWidgetShared.readSnapshot()
        let snapshotBackground = snapshot.projects.first { $0.id == projectID }?.safeAreaTopBackground
        context = ProjectWidgetLaunchContext(
            url: url,
            background: urlBackground ?? snapshotBackground
        )
    }
}

@MainActor
final class HTMLKeepSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        ProjectWidgetLaunchStore.shared.captureProjectWidgetURL(from: connectionOptions.urlContexts.map(\.url))
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        ProjectWidgetLaunchStore.shared.captureProjectWidgetURL(from: URLContexts.map(\.url))
    }
}
