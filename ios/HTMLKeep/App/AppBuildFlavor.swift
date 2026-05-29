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
