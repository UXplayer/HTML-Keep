import Foundation

enum AppDistribution {
    case community
    case official

    static var current: AppDistribution {
        #if HTMLKEEP_COMMUNITY
        return .community
        #else
        return .official
        #endif
    }

    var unlocksLocalProEntitlementFeatures: Bool {
        self == .community
    }

    var supportsOfficialICloudSync: Bool {
        self == .official
    }

    var supportsHubShareAuthoring: Bool {
        self == .official
    }

    var usesOfficialStoreKit: Bool {
        self == .official
    }

    var usesRemoteAppVersionCheck: Bool {
        self == .official
    }

    var showsOfficialProEntitlementUI: Bool {
        self == .official
    }

    var showsOfficialDebugPanels: Bool {
        self == .official
    }
}

enum AppBuildFlavor {
    case testing
    case production

    static var current: AppBuildFlavor {
        #if DEBUG
        return .testing
        #else
        return .production
        #endif
    }

    var isTestingBuild: Bool {
        self == .testing
    }

    var defaultIsExpertModeEnabled: Bool {
        self == .testing
    }
}

enum HubRuntimeConfiguration {
    private static let productionOrigin = URL(string: "https://hub.htmlkeep.com")!
    private static let stagingOrigin = URL(string: "https://hubstaging.htmlkeep.com")!

    static var primaryOrigin: URL {
        AppBuildFlavor.current.isTestingBuild ? stagingOrigin : productionOrigin
    }

    static var importOrigins: [URL] {
        AppBuildFlavor.current.isTestingBuild ? [stagingOrigin, productionOrigin] : [productionOrigin]
    }

    static var uploadURL: URL {
        primaryOrigin
            .appendingPathComponent("api", isDirectory: true)
            .appendingPathComponent("upload", isDirectory: false)
    }

    static var mySharesURL: URL {
        primaryOrigin
            .appendingPathComponent("api", isDirectory: true)
            .appendingPathComponent("me", isDirectory: true)
            .appendingPathComponent("shares", isDirectory: false)
    }

    static var approveLoginURL: URL {
        approveLoginURL(for: primaryOrigin)
    }

    static var loginApprovalOrigins: [URL] {
        AppBuildFlavor.current.isTestingBuild ? [stagingOrigin, productionOrigin] : [productionOrigin]
    }

    static func approveLoginURL(for origin: URL) -> URL {
        origin
            .appendingPathComponent("api", isDirectory: true)
            .appendingPathComponent("auth", isDirectory: true)
            .appendingPathComponent("approve", isDirectory: false)
    }

    static func loginApprovalOrigin(for url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased() else {
            return nil
        }

        return loginApprovalOrigins.first { origin in
            origin.scheme?.lowercased() == scheme &&
            origin.host?.lowercased() == host &&
            origin.port == url.port
        }
    }

    static func shareURL(for code: String, origin: URL) -> URL {
        origin
            .appendingPathComponent("s", isDirectory: true)
            .appendingPathComponent(code, isDirectory: false)
    }
}

enum AppDiagnosticsLogLevel: String {
    case info
    case error
}

func appDiagnosticsLog(
    category: String,
    message: String,
    level: AppDiagnosticsLogLevel = .info
) {
    #if DEBUG
    print("[\(level.rawValue.uppercased())][\(category)] \(message)")
    #endif
}

func formatICloudSyncErrorDetails(_ error: Error) -> String {
    error.localizedDescription
}
