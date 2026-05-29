import Foundation

enum ICloudWebPageSyncConfiguration {
    static var containerIdentifier: String { AppRuntimeConfiguration.iCloudContainerIdentifier }
    static let zoneName = "CommunitySyncUnavailable"
}

struct ICloudWebPageSyncDebugResult: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

enum ICloudWebPageSyncUserRecordKind: String, Codable {
    case inProgress
    case received
    case completed
    case noChanges
    case noAccount
    case unavailable
    case failed
}

struct ICloudWebPageSyncUserRecord: Identifiable, Codable, Hashable {
    let id: UUID
    var kind: ICloudWebPageSyncUserRecordKind
    var createdAt: Date
    var localPageCount: Int
    var receivedPageCount: Int

    init(
        id: UUID = UUID(),
        kind: ICloudWebPageSyncUserRecordKind,
        createdAt: Date = .now,
        localPageCount: Int,
        receivedPageCount: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.localPageCount = localPageCount
        self.receivedPageCount = receivedPageCount
    }
}

enum ICloudWebPageSyncAccess: Equatable {
    case allowed
    case proEntitlementUnknown
    case proEntitlementRequired
    case proEntitlementExpired
    case userDisabled

    var allowsPrivateDatabaseAccess: Bool { false }

    var debugStatusText: String {
        AppStrings.localized("HTML Keep 社区版")
    }

    var blockedDebugTitle: String {
        AppStrings.localized("社区版未启用官方 iCloud 同步")
    }

    var blockedDebugMessage: String {
        AppStrings.localized("社区版不包含 HTML Keep 官方 iCloud 同步服务。")
    }
}

struct ICloudWebPagePresenceDeviceSummary: Codable, Hashable, Identifiable {
    let installationID: String
    var updatedAt: Date
    var activeProjectCount: Int
    var contentChangedAt: Date

    var id: String { installationID }
}

@MainActor
@Observable
final class ICloudWebPagePresenceStore {
    private(set) var localSummary: ICloudWebPagePresenceDeviceSummary?
    private(set) var remoteSummaries: [ICloudWebPagePresenceDeviceSummary] = []
    private(set) var lastRefreshErrorDescription: String?
    private(set) var lastSynchronizeResult: Bool?
    private(set) var lastSynchronizeAt: Date?
    private(set) var lastExternalChangeAt: Date?
    private(set) var lastExternalChangedKeys: [String] = []
    private(set) var revision = 0
    private(set) var didDismissRemotePromptForCurrentSession = false

    init() {}

    func updateLocalSummary(activeProjectCount: Int, contentChangedAt: Date) {
        localSummary = ICloudWebPagePresenceDeviceSummary(
            installationID: ICloudWebPageSyncService.currentInstallationID(),
            updatedAt: .now,
            activeProjectCount: activeProjectCount,
            contentChangedAt: contentChangedAt
        )
        revision += 1
    }

    func refresh() {
        revision += 1
    }

    func hasPossibleRemotePages(comparedToActiveProjectCount localProjectCount: Int) -> Bool {
        false
    }

    func dismissRemotePromptForCurrentSession() {
        didDismissRemotePromptForCurrentSession = true
        revision += 1
    }

    func clearDebugData() {
        localSummary = nil
        remoteSummaries = []
        lastRefreshErrorDescription = nil
        revision += 1
    }

    var debugSummaryLines: [String] {
        [
            "HTML Keep Community：official iCloud sync unavailable",
            "installationID：\(ICloudWebPageSyncService.currentInstallationID())"
        ]
    }
}

@MainActor
@Observable
final class ICloudWebPageSyncService {
    private static let installationIDDefaultsKey = "community_sync_installation_id"

    private(set) var access: ICloudWebPageSyncAccess
    private(set) var userRecords: [ICloudWebPageSyncUserRecord] = []

    init(
        library: WebPageLibrary,
        access: ICloudWebPageSyncAccess = .proEntitlementUnknown,
        fileManager: FileManager = .default
    ) {
        self.access = access
    }

    func updateAccess(_ access: ICloudWebPageSyncAccess) {
        self.access = access
    }

    func scheduleSync(reason: String) {}
    func cancelScheduledSync() {}
    func performSync(reason: String) async {}

    #if DEBUG
    func performDebugSync() async -> ICloudWebPageSyncDebugResult {
        ICloudWebPageSyncDebugResult(
            title: AppStrings.localized("社区版未启用官方 iCloud 同步"),
            message: AppStrings.localized("社区版不包含 HTML Keep 官方 iCloud 同步服务。")
        )
    }

    func performDebugEnvironmentReset() async -> ICloudWebPageSyncDebugResult {
        ICloudWebPageSyncDebugResult(
            title: AppStrings.localized("社区版未启用官方 iCloud 同步"),
            message: AppStrings.localized("没有可清理的官方 iCloud 同步环境。")
        )
    }
    #endif

    static func currentInstallationID() -> String {
        if let existing = UserDefaults.standard.string(forKey: installationIDDefaultsKey) {
            return existing
        }
        let created = UUID().uuidString
        UserDefaults.standard.set(created, forKey: installationIDDefaultsKey)
        return created
    }

    static func iso8601String(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
