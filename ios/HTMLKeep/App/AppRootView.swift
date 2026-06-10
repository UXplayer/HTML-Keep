import AVFoundation
import CloudKit
import Foundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WidgetKit

private let remoteWebPageImportMaximumByteCount: Int64 = 200_000_000

private enum RemoteWebPageImportError: LocalizedError {
    case emptyInput
    case invalidInput
    case badStatus(Int)
    case downloadFailed(String)
    case missingDownload
    case fileTooLarge

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return AppStrings.localized("请输入 Hub 暗号。")
        case .invalidInput:
            return AppStrings.localized("请输入有效的 Hub 暗号。")
        case .badStatus(let statusCode):
            return String(
                format: AppStrings.localized("无法下载这个暗号。服务器返回 %@。"),
                "\(statusCode)"
            )
        case .downloadFailed(let message):
            return String(
                format: AppStrings.localized("无法下载这个暗号。%@"),
                message
            )
        case .missingDownload:
            return AppStrings.localized("没有下载到可导入的文件。")
        case .fileTooLarge:
            return String(
                format: AppStrings.localized("这个文件太大，无法导入。请选择不超过 %@ 的文件。"),
                ByteCountFormatter.string(fromByteCount: remoteWebPageImportMaximumByteCount, countStyle: .file)
            )
        }
    }
}

private enum RemoteWebPageImportDownloader {
    static func hubCodeURLs(from rawInput: String) throws -> [URL] {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            throw RemoteWebPageImportError.emptyInput
        }

        guard input.range(of: #"^[0-9]{6,12}$"#, options: .regularExpression) != nil else {
            throw RemoteWebPageImportError.invalidInput
        }

        return HubRuntimeConfiguration.importOrigins.map { origin in
            HubRuntimeConfiguration.shareURL(for: input, origin: origin)
        }
    }

    static func download(from remoteURLs: [URL]) async throws -> URL {
        var lastError: Error = RemoteWebPageImportError.invalidInput
        for remoteURL in remoteURLs {
            do {
                return try await download(from: remoteURL)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private static func download(from remoteURL: URL) async throws -> URL {
        let downloadedURL: URL
        let response: URLResponse
        do {
            (downloadedURL, response) = try await URLSession.shared.download(from: remoteURL)
        } catch {
            throw RemoteWebPageImportError.downloadFailed(error.localizedDescription)
        }

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw RemoteWebPageImportError.badStatus(httpResponse.statusCode)
        }

        if response.expectedContentLength > remoteWebPageImportMaximumByteCount {
            throw RemoteWebPageImportError.fileTooLarge
        }

        let temporaryFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("HTMLKeep-URLImport-\(UUID().uuidString)", isDirectory: true)
        let fileName = safeFileName(response: response, fallbackURL: response.url ?? remoteURL)
        let destinationURL = temporaryFolderURL.appendingPathComponent(fileName, isDirectory: false)

        try FileManager.default.createDirectory(at: temporaryFolderURL, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: downloadedURL, to: destinationURL)

        let byteCount = Int64((try? destinationURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        guard byteCount > 0 else {
            try? FileManager.default.removeItem(at: temporaryFolderURL)
            throw RemoteWebPageImportError.missingDownload
        }
        guard byteCount <= remoteWebPageImportMaximumByteCount else {
            try? FileManager.default.removeItem(at: temporaryFolderURL)
            throw RemoteWebPageImportError.fileTooLarge
        }

        return destinationURL
    }

    private static func safeFileName(response: URLResponse, fallbackURL: URL) -> String {
        let suggestedName = response.suggestedFilename ?? fallbackURL.lastPathComponent
        var fileName = suggestedName.removingPercentEncoding ?? suggestedName
        fileName = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        fileName = fileName.components(separatedBy: CharacterSet(charactersIn: "/\\:")).joined(separator: "-")
        if fileName.isEmpty {
            fileName = "download"
        }

        let fileURL = URL(fileURLWithPath: fileName)
        if fileURL.pathExtension.isEmpty,
           let mimeType = response.mimeType,
           let preferredExtension = UTType(mimeType: mimeType)?.preferredFilenameExtension {
            fileName += ".\(preferredExtension)"
        }

        return fileName
    }
}

enum HubUserIdentityError: LocalizedError {
    case iCloudNotSignedIn
    case iCloudRestricted
    case iCloudStatusUnknown
    case iCloudTemporarilyUnavailable
    case iCloudPermissionDenied
    case iCloudNetworkUnavailable
    case cloudKitContainerUnavailable
    case cloudKitRequestFailed(String)
    case invalidRecordName

    var errorDescription: String? {
        switch self {
        case .iCloudNotSignedIn:
            return AppStrings.localized("需要登录 iCloud 后才能使用 Hub。")
        case .iCloudRestricted:
            return AppStrings.localized("当前 iCloud 账户受限制，无法使用 Hub。")
        case .iCloudStatusUnknown:
            return AppStrings.localized("无法确认 iCloud 登录状态，请稍后重试。")
        case .iCloudTemporarilyUnavailable:
            return AppStrings.localized("iCloud 暂时不可用，请稍后重试。")
        case .iCloudPermissionDenied:
            return AppStrings.localized("无法访问 Hub 需要的 iCloud 权限，请检查系统设置。")
        case .iCloudNetworkUnavailable:
            return AppStrings.localized("网络连接不可用，暂时无法连接 iCloud。")
        case .cloudKitContainerUnavailable:
            return AppStrings.localized("当前安装包无法访问 Hub 使用的 iCloud 容器。")
        case .cloudKitRequestFailed(let message):
            return String(format: AppStrings.localized("无法初始化 Hub 身份：%@"), message)
        case .invalidRecordName:
            return AppStrings.localized("无法识别当前 iCloud 用户。")
        }
    }
}

enum HubUserIdentityProvider {
    static func currentCloudKitUserRecordName() async throws -> String {
        let container = CKContainer(identifier: AppRuntimeConfiguration.iCloudContainerIdentifier)
        try await validateAccountStatus(container: container)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            container.fetchUserRecordID { recordID, error in
                if let error {
                    continuation.resume(throwing: identityError(from: error))
                    appDiagnosticsLog(
                        category: "HubIdentity",
                        message: "fetch_user_record_failed \(diagnosticDescription(for: error))",
                        level: .error
                    )
                    return
                }

                guard let recordName = recordID?.recordName.trimmingCharacters(in: .whitespacesAndNewlines),
                      !recordName.isEmpty else {
                    continuation.resume(throwing: HubUserIdentityError.invalidRecordName)
                    return
                }

                continuation.resume(returning: recordName)
            }
        }
    }

    private static func validateAccountStatus(container: CKContainer) async throws {
        let status = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKAccountStatus, Error>) in
            container.accountStatus { status, error in
                if let error {
                    continuation.resume(throwing: identityError(from: error))
                } else {
                    continuation.resume(returning: status)
                }
            }
        }

        switch status {
        case .available:
            return
        case .noAccount:
            throw HubUserIdentityError.iCloudNotSignedIn
        case .restricted:
            throw HubUserIdentityError.iCloudRestricted
        case .couldNotDetermine:
            throw HubUserIdentityError.iCloudStatusUnknown
        case .temporarilyUnavailable:
            throw HubUserIdentityError.iCloudTemporarilyUnavailable
        @unknown default:
            throw HubUserIdentityError.iCloudStatusUnknown
        }
    }

    private static func identityError(from error: Error) -> HubUserIdentityError {
        guard let ckError = error as? CKError else {
            return .cloudKitRequestFailed(error.localizedDescription)
        }

        switch ckError.code {
        case .notAuthenticated:
            return .iCloudNotSignedIn
        case .networkUnavailable, .networkFailure:
            return .iCloudNetworkUnavailable
        case .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return .iCloudTemporarilyUnavailable
        case .permissionFailure:
            return .iCloudPermissionDenied
        case .badContainer:
            return .cloudKitContainerUnavailable
        default:
            return .cloudKitRequestFailed(ckError.localizedDescription)
        }
    }

    private static func diagnosticDescription(for error: Error) -> String {
        guard let ckError = error as? CKError else {
            return "error=\(error.localizedDescription)"
        }
        return "ck_code=\(ckError.code.rawValue) error=\(ckError.localizedDescription)"
    }
}

struct HubShareListItem: Decodable, Identifiable, Equatable, Sendable {
    let code: String
    let url: URL
    let fileName: String
    let displayName: String?
    let contentType: String?
    let byteSize: Int64
    let createdAt: String
    let retentionPolicy: String?
    let expiresAt: String?
    let downloadCount: Int

    var id: String { code }

    var displayTitle: String {
        let title = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? fileName : title
    }

    var retentionDisplayTitle: String {
        HubShareRetentionPolicy(rawValue: retentionPolicy ?? "30d")?.displayTitle ?? AppStrings.localized("30 天")
    }

    var expiryDisplayText: String {
        guard let expiresAt,
              let date = ISO8601DateFormatter.htmlKeepHubDate(from: expiresAt) else {
            return AppStrings.localized("永久保存")
        }
        return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
    }

    var remainingTimeDisplayText: String {
        guard let expiresAt,
              let expiryDate = ISO8601DateFormatter.htmlKeepHubDate(from: expiresAt) else {
            return AppStrings.localized("永久保存")
        }
        let remaining = expiryDate.timeIntervalSinceNow
        guard remaining > 0 else {
            return AppStrings.localized("已过期")
        }

        let minute: TimeInterval = 60
        let hour: TimeInterval = 60 * minute
        let day: TimeInterval = 24 * hour

        if remaining >= day {
            return String(format: AppStrings.localized("%d天"), Int(remaining / day))
        }
        if remaining >= hour {
            return String(format: AppStrings.localized("%d小时"), Int(remaining / hour))
        }
        return String(format: AppStrings.localized("%d分钟"), max(1, Int(ceil(remaining / minute))))
    }

    var byteSizeDisplayText: String {
        ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file)
    }
}

private struct HubSharesResponse: Decodable {
    let shares: [HubShareListItem]
}

private struct HubServerError: Decodable {
    let message: String?
}

enum HubAPIError: LocalizedError {
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return AppStrings.localized("Hub 返回了无法识别的响应。")
        case .server(let message):
            return message
        }
    }
}

enum HubAPIClient {
    static func fetchMyShares(cloudKitUserRecordName: String) async throws -> [HubShareListItem] {
        var components = URLComponents(url: HubRuntimeConfiguration.mySharesURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "cloudKitUserRecordName", value: cloudKitUserRecordName)
        ]
        guard let url = components.url else {
            throw HubAPIError.invalidResponse
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HubAPIError.invalidResponse
        }

        let decoder = JSONDecoder()
        guard (200...299).contains(httpResponse.statusCode) else {
            let serverError = try? decoder.decode(HubServerError.self, from: data)
            throw HubAPIError.server(serverError?.message ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))
        }

        do {
            return try decoder.decode(HubSharesResponse.self, from: data).shares
        } catch {
            throw HubAPIError.invalidResponse
        }
    }

    static func approveLogin(
        token: String,
        approveURL: URL = HubRuntimeConfiguration.approveLoginURL,
        cloudKitUserRecordName: String,
        clientIsPremium: Bool
    ) async throws {
        var request = URLRequest(url: approveURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: [
                "token": token,
                "cloudKitUserRecordName": cloudKitUserRecordName,
                "clientIsPremium": clientIsPremium
            ],
            options: []
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HubAPIError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let serverError = try? JSONDecoder().decode(HubServerError.self, from: data)
            throw HubAPIError.server(serverError?.message ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))
        }
    }
}

struct HubLoginChallenge: Equatable {
    let token: String
    let approveURL: URL
}

enum HubLoginTokenParser {
    static func challenge(from rawValue: String) -> HubLoginChallenge? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if value.hasPrefix("htmlkeep-hub-login:") {
            let token = String(value.dropFirst("htmlkeep-hub-login:".count))
            guard isValidToken(token) else { return nil }
            return HubLoginChallenge(
                token: token,
                approveURL: HubRuntimeConfiguration.approveLoginURL
            )
        }

        if let url = URL(string: value),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let token = components.queryItems?.first(where: { $0.name == "token" })?.value,
           isValidToken(token),
           let origin = HubRuntimeConfiguration.loginApprovalOrigin(for: url) {
            return HubLoginChallenge(
                token: token,
                approveURL: HubRuntimeConfiguration.approveLoginURL(for: origin)
            )
        }

        guard isValidToken(value) else { return nil }
        return HubLoginChallenge(
            token: value,
            approveURL: HubRuntimeConfiguration.approveLoginURL
        )
    }

    private static func isValidToken(_ value: String) -> Bool {
        value.range(of: #"^[a-fA-F0-9]{24,96}$"#, options: .regularExpression) != nil
    }
}

struct HubQRCodeScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    let onError: (String) -> Void

    func makeUIViewController(context: Context) -> HubQRCodeScannerViewController {
        HubQRCodeScannerViewController(onCode: onCode, onError: onError)
    }

    func updateUIViewController(_ uiViewController: HubQRCodeScannerViewController, context: Context) {}
}

final class HubQRCodeScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let captureSession = AVCaptureSession()
    private let onCode: (String) -> Void
    private let onError: (String) -> Void
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var isConfigured = false
    private var hasEmittedCode = false

    init(onCode: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
        self.onCode = onCode
        self.onError = onError
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        configureAndStartIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession.stopRunning()
    }

    private func configureAndStartIfNeeded() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSessionIfNeeded()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] isGranted in
                DispatchQueue.main.async {
                    if isGranted {
                        self?.configureSessionIfNeeded()
                    } else {
                        self?.onError(AppStrings.localized("需要允许相机权限才能扫码登录。"))
                    }
                }
            }
        case .denied, .restricted:
            onError(AppStrings.localized("需要允许相机权限才能扫码登录。"))
        @unknown default:
            onError(AppStrings.localized("无法启动扫码。"))
        }
    }

    private func configureSessionIfNeeded() {
        guard !isConfigured else {
            startSession()
            return
        }

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              captureSession.canAddInput(input) else {
            onError(AppStrings.localized("无法启动相机。"))
            return
        }
        captureSession.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard captureSession.canAddOutput(output) else {
            onError(AppStrings.localized("无法启动扫码。"))
            return
        }
        captureSession.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.insertSublayer(layer, at: 0)
        previewLayer = layer
        isConfigured = true
        startSession()
    }

    private func startSession() {
        guard !captureSession.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [captureSession] in
            captureSession.startRunning()
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !hasEmittedCode,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue else {
            return
        }
        hasEmittedCode = true
        captureSession.stopRunning()
        onCode(value)
    }
}

@MainActor
struct AppRootView: View {
    private static let settingsProEntitlementPresentationDelay: TimeInterval = 0.35

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.layoutDirection) private var systemLayoutDirection
    @AppStorage(AppPreferenceKeys.language) private var languagePreferenceRaw = AppLanguagePreference.automatic.rawValue
    @AppStorage(AppPreferenceKeys.appearance) private var appearancePreferenceRaw = AppAppearancePreference.automatic.rawValue
    @AppStorage(AppPreferenceKeys.homeDisplayMode) private var homeDisplayModeRaw = HomeDisplayMode.list.rawValue
    @AppStorage(AppPreferenceKeys.iCloudSyncEnabled) private var isICloudSyncEnabled = true
    @AppStorage(AppPreferenceKeys.agentImportGuideCompleted) private var hasCompletedAgentImportGuide = false
    @StateObject private var projectWidgetLaunchStore = ProjectWidgetLaunchStore.shared
    @StateObject private var proEntitlementStore = ProEntitlementStore()
    @StateObject private var proEntitlementMarketingFunnelStore = ProEntitlementMarketingFunnelStore()
    @StateObject private var appReviewShieldStore = AppReviewShieldStore()
    @StateObject private var versionUpdatePromptStore = VersionUpdatePromptStore()
    @StateObject private var debugFloatingBallVisibilityStore = DebugFloatingBallVisibilityStore()
    @State private var library = WebPageLibrary()
    @State private var router = AppRouter()
    @State private var iCloudSyncService: ICloudWebPageSyncService?
    @State private var iCloudPresenceStore = ICloudWebPagePresenceStore()
    @State private var importError: String?
    @State private var importPreview: WebPageImportPreview?
    @State private var fileImportRequestID = 0
    @State private var isURLImportAlertPresented = false
    @State private var urlImportDraft = ""
    @State private var isProjectIconSourceDialogPresented = false
    @State private var isProjectIconImporterPresented = false
    @State private var isProjectIconPhotoPickerPresented = false
    @State private var selectedProjectIconPhotoItem: PhotosPickerItem?
    @State private var projectIconImportTarget: WebPage?
    @State private var settingsMenuRequestID = 0
    @State private var settingsMenuDismissRequestID = 0
    @State private var settingsPopoverAnchorItem: UIBarButtonItem?
    @State private var settingsSidebarPath: [SettingsSidebarRoute] = []
    @State private var settingsSidebarResetID = 0
    @State private var settingsPresentedSheet: SettingsPresentedSheet?
    @State private var rootPresentedSheet: SettingsPresentedSheet?
    @State private var agentImportSession = AgentImportSessionController()
    @State private var agentImportFloatingConnectionPosition: CGPoint?
    @State private var settingsDebugSheetDetent: PresentationDetent = .large
    @State private var debugICloudSyncResult: ICloudWebPageSyncDebugResult?
    @State private var isInitialRouteGateReleased = false
    @State private var hasScheduledInitialRouteGateRelease = false
    @State private var proEntitlementDestination: ProEntitlementDestination?
    @State private var routedProjectWidgetLaunchContextID: UUID?
    @State private var releasedProjectWidgetLaunchContextID: UUID?
    @State private var isHomeCloudSyncDelayElapsed = false
    @State private var homeCloudSyncDelayTask: Task<Void, Never>?
    @State private var hasScheduledPossibleRemoteInitialSync = false

    var body: some View {
        AnyView(rootContainer)
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .id(layoutDirectionIdentity)
            .tint(AppTheme.deepWater)
            .environment(\.locale, languagePreference.locale ?? .autoupdatingCurrent)
            .modifier(AppLayoutDirectionModifier(layoutDirection: layoutDirection))
            .preferredColorScheme(appearancePreference.colorScheme)
            .background(documentPickerPresenter)
            .fileImporter(
                isPresented: $isProjectIconImporterPresented,
                allowedContentTypes: [.image],
                allowsMultipleSelection: false
            ) { result in
                handleProjectIconImportResult(result)
            }
            .photosPicker(
                isPresented: $isProjectIconPhotoPickerPresented,
                selection: $selectedProjectIconPhotoItem,
                matching: .images
            )
            .confirmationDialog(
                AppStrings.localized("选择图标来源"),
                isPresented: $isProjectIconSourceDialogPresented,
                titleVisibility: .visible,
                actions: { projectIconSourceDialogActions }
            )
            .sheet(item: $rootPresentedSheet) { sheet in
                settingsSheet(for: sheet, host: .root)
                    .preferredColorScheme(appearancePreference.colorScheme)
            }
            .alert(AppStrings.localized("输入暗号"), isPresented: $isURLImportAlertPresented) {
                TextField(AppStrings.localized("Hub 暗号"), text: $urlImportDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.numberPad)
                Button(AppStrings.localized("取消"), role: .cancel) {
                    urlImportDraft = ""
                }
                Button(AppStrings.localized("导入")) {
                    submitURLImport()
                }
            } message: {
                Text(AppStrings.localized("输入 Hub 分享暗号。"))
            }
            .modifier(rootAlertModifier)
            .modifier(runtimePresentationModifier)
            .debugFloatingToolsOverlay(
                proEntitlementStore: proEntitlementStore,
                visibilityStore: debugFloatingBallVisibilityStore,
                iCloudSyncDebugSnapshot: iCloudSyncDebugSnapshot,
                onRunICloudSyncTest: runDebugICloudSyncTest,
                onResetICloudSyncEnvironment: resetDebugICloudSyncEnvironment
            )
            .onOpenURL(perform: handleOpenURL)
            .onAppear(perform: handleAppear)
            .onChange(of: scenePhase) { _, phase in
                handleScenePhaseChange(phase)
            }
            .onChange(of: selectedProjectIconPhotoItem) { _, item in
                handleProjectIconPhotoItemChange(item)
            }
            .onChange(of: isProjectIconPhotoPickerPresented) { _, isPresented in
                if !isPresented, selectedProjectIconPhotoItem == nil {
                    projectIconImportTarget = nil
                }
            }
            .onChange(of: proEntitlementStore.proEntitlementState) { _, _ in
                proEntitlementMarketingFunnelStore.updateProEntitlementStatus(hasProEntitlement: proEntitlementStore.hasProEntitlement)
                refreshProjectWidgetEntitlementSnapshot()
                handleICloudSyncAccessChanged()
            }
            .onChange(of: isICloudSyncEnabled) { _, _ in
                handleICloudSyncAccessChanged()
            }
            .onChange(of: projectWidgetLaunchStore.context?.id) { _, _ in
                processProjectWidgetLaunchContextIfNeeded()
            }
            .onChange(of: library.pages) { _, _ in
                refreshICloudPresenceSummary()
                handleICloudPresenceChanged()
            }
            .onChange(of: library.deletionTombstones) { _, _ in
                refreshICloudPresenceSummary()
                handleICloudPresenceChanged()
            }
            .onChange(of: library.restoreRevisions) { _, _ in
                refreshICloudPresenceSummary()
                handleICloudPresenceChanged()
            }
            .onChange(of: iCloudPresenceStore.revision) { _, _ in
                handleICloudPresenceChanged()
            }
            .onChange(of: latestICloudSyncRecord) { _, _ in
                refreshHomeCloudSyncDelayState()
            }
            .onChange(of: appReviewShieldStore.isEnabled) { _, isEnabled in
                proEntitlementMarketingFunnelStore.updateAppReviewShield(isEnabled: isEnabled)
            }
            .environment(library)
            .environmentObject(proEntitlementStore)
            .environmentObject(proEntitlementMarketingFunnelStore)
            .environmentObject(debugFloatingBallVisibilityStore)
    }

    private var rootContainer: some View {
        let effectiveLayoutDirection = layoutDirection ?? systemLayoutDirection
        let settingsMenuOpensFromLeft = effectiveLayoutDirection == .leftToRight
        let usesIPadSettingsPopover = Self.usesIPadSettingsPopover
        let projectWidgetLaunchContext = projectWidgetLaunchStore.context
        let isProjectWidgetLaunchGateActive = projectWidgetLaunchContext != nil &&
            releasedProjectWidgetLaunchContextID != projectWidgetLaunchContext?.id

        return ZStack {
            if isProjectWidgetLaunchGateActive {
                ProjectWidgetLaunchBackground(cssBackground: projectWidgetLaunchContext?.background)
            } else {
                AppPageBackground()
            }

            Group {
                if !isProjectWidgetLaunchGateActive, isInitialRouteGateReleased {
                    if usesIPadSettingsPopover {
                        SettingsPopoverContainer(
                            presentationRequestID: settingsMenuRequestID,
                            dismissalRequestID: settingsMenuDismissRequestID,
                            anchorItem: settingsPopoverAnchorItem,
                            fallbackAnchorOpensFromLeft: settingsMenuOpensFromLeft,
                            preferredColorScheme: appearancePreference.colorScheme,
                            onWillPresent: {
                                resetSettingsSidebarNavigation()
                            },
                            onDismiss: {
                                resetSettingsSidebarNavigation()
                            }
                        ) {
                            mainNavigationContent
                        } sidebar: {
                            settingsSidebarContent
                        }
                    } else {
                        SettingsSideMenuContainer(
                            presentationRequestID: settingsMenuRequestID,
                            dismissalRequestID: settingsMenuDismissRequestID,
                            opensFromLeft: settingsMenuOpensFromLeft,
                            preferredColorScheme: appearancePreference.colorScheme,
                            onWillPresent: {
                                resetSettingsSidebarNavigation()
                            },
                            onDismiss: {
                                resetSettingsSidebarNavigation()
                            }
                        ) {
                            mainNavigationContent
                        } sidebar: {
                            settingsSidebarContent
                        }
                    }
                }
            }
            .ignoresSafeArea()

            if shouldShowProEntitlementPromoSnackbar {
                VStack {
                    Spacer()
                    Group {
                    #if HTMLKEEP_COMMUNITY
                        ProEntitlementPromoSnackbar(
                            discountText: proEntitlementStore.discountSnackbarDiscountText,
                            fullOfferText: proEntitlementStore.discountSnackbarFullOfferText,
                            compactOfferText: proEntitlementStore.discountSnackbarCompactOfferText,
                            fallbackText: proEntitlementStore.discountSnackbarFallbackText,
                            remainingText: proEntitlementMarketingFunnelStore.promoSnackbarCountdownText,
                            action: {
                                presentProEntitlement()
                            },
                            closeAction: {
                                proEntitlementMarketingFunnelStore.dismissPromoSnackbarForCurrentSession()
                            }
                        )
                    #else
                        HomePromoSnackbar(
                            discountText: proEntitlementStore.discountSnackbarDiscountText,
                            fullOfferText: proEntitlementStore.discountSnackbarFullOfferText,
                            compactOfferText: proEntitlementStore.discountSnackbarCompactOfferText,
                            fallbackText: proEntitlementStore.discountSnackbarFallbackText,
                            remainingText: proEntitlementMarketingFunnelStore.promoSnackbarCountdownText,
                            action: {
                                presentProEntitlement()
                            },
                            closeAction: {
                                proEntitlementMarketingFunnelStore.dismissPromoSnackbarForCurrentSession()
                            }
                        )
                    #endif
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 106)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(10)
            }

            if shouldShowAgentImportFloatingConnection {
                AgentImportFloatingConnectionButton(position: $agentImportFloatingConnectionPosition) {
                    presentAgentImportFromFloatingConnection()
                }
                .transition(.scale(scale: 0.92).combined(with: .opacity))
                .zIndex(20)
            }

            if let importPreview {
                WebPageImportPreviewView(
                    preview: importPreview,
                    onRetry: {
                        retryImport(from: importPreview.source)
                    },
                    onReturnHome: {
                        routeFromExternalEntry {
                            router.popToRoot()
                        }
                    }
                )
                .transition(.opacity)
                .zIndex(30)
            }
        }
    }

    private var languagePreference: AppLanguagePreference {
        AppLanguagePreference.value(for: languagePreferenceRaw)
    }

    private var appearancePreference: AppAppearancePreference {
        AppAppearancePreference.value(for: appearancePreferenceRaw)
    }

    private var layoutDirection: LayoutDirection? {
        languagePreference.layoutDirection
    }

    private var layoutDirectionIdentity: String {
        Self.layoutDirectionIdentity(for: layoutDirection)
    }

    private var documentPickerPresenter: some View {
        WebPageDocumentPickerPresenter(
            presentationRequestID: fileImportRequestID,
            onPick: handleImportResult
        )
        .frame(width: 0, height: 0)
    }

    @ViewBuilder
    private var projectIconSourceDialogActions: some View {
        Button(AppStrings.localized("从相册选择")) {
            isProjectIconPhotoPickerPresented = true
        }
        Button(AppStrings.localized("从文件选择")) {
            isProjectIconImporterPresented = true
        }
        Button(AppStrings.localized("取消"), role: .cancel) {
            projectIconImportTarget = nil
        }
    }

    private var rootAlertModifier: AppRootAlertModifier {
        AppRootAlertModifier(
            importError: $importError,
            debugICloudSyncResult: $debugICloudSyncResult,
            onCopyDebugICloudSyncResult: copyDebugICloudSyncResult
        )
    }

    private func handleOpenURL(_ url: URL) {
        if let context = projectWidgetLaunchStore.context,
           context.url == url {
            processProjectWidgetLaunchContext(context)
            return
        }

        guard !handleProjectWidgetURL(url) else {
            releaseInitialRouteGate()
            return
        }
        startFileImportFlow(from: url)
    }

    private func handleAppear() {
        processProjectWidgetLaunchContextIfNeeded()
        scheduleInitialRouteGateReleaseIfNeeded()
        refreshICloudPresenceSummary()
        handleICloudSyncAccessChanged()
        scheduleICloudSyncIfAllowed(reason: AppStrings.localized("syncReason.appLaunch"))
        library.scheduleOpportunisticFullContentSearchIndexBuildIfNeeded()
        appReviewShieldStore.bootstrap()
        versionUpdatePromptStore.bootstrapAfterLaunchReady()
        proEntitlementMarketingFunnelStore.updateProEntitlementStatus(hasProEntitlement: proEntitlementStore.hasProEntitlement)
        proEntitlementMarketingFunnelStore.updateAppReviewShield(isEnabled: appReviewShieldStore.isEnabled)
        refreshProjectWidgetEntitlementSnapshot(reloadsTimelines: false)
        if scenePhase == .background {
            agentImportSession.stop(reason: .appLifecycle)
        }
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        if phase == .background {
            agentImportSession.stop(reason: .appLifecycle)
            return
        }
        guard phase == .active else { return }
        iCloudPresenceStore.refresh()
        refreshICloudPresenceSummary()
        handleICloudSyncAccessChanged()
        scheduleICloudSyncIfAllowed(reason: AppStrings.localized("syncReason.foreground"))
        library.scheduleOpportunisticFullContentSearchIndexBuildIfNeeded()
        appReviewShieldStore.refreshIfNeeded(reason: "foreground")
        versionUpdatePromptStore.refreshIfNeeded(reason: "foreground")
    }

    private func handleProjectIconPhotoItemChange(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            await handleProjectIconPhotoSelection(item)
        }
    }

    @ViewBuilder
    private var mainNavigationContent: some View {
        NavigationStack(path: $router.path) {
            HomeView(
                pages: library.pages,
                displayMode: homeDisplayMode,
                iCloudEmptyState: homeICloudEmptyState,
                projectIconURL: { page in
                    library.projectIconURL(for: page)
                },
                hasFullContentSearchIndex: library.hasFullContentSearchIndex,
                searchResults: { query, scope in
                    library.searchResults(matching: query, scope: scope)
                },
                onSearchFullContent: {
                    await library.buildFullContentSearchIndexIfNeeded()
                },
                onOpenImporter: { fileImportRequestID += 1 },
                onOpenURLImporter: {
                    presentURLImportAlert()
                },
                onOpenSettings: { anchorItem in
                    settingsPopoverAnchorItem = anchorItem
                    resetSettingsSidebarNavigation()
                    settingsMenuRequestID += 1
                },
                onOpenProEntitlement: {
                    presentProEntitlement()
                },
                onDismissICloudSyncPrompt: {
                    iCloudPresenceStore.dismissRemotePromptForCurrentSession()
                },
                onRetryICloudSync: {
                    scheduleICloudSyncIfAllowed(reason: AppStrings.localized("syncReason.homeRetry"))
                },
                onOpenProject: { page in
                    router.open(page: page, entry: library.defaultEntry(for: page))
                },
                onSelectEntry: { page, entry in
                    router.open(page: page, entry: entry)
                },
                onRenamePage: { page, title in
                    renamePage(page, to: title)
                },
                onSetProjectIcon: { page in
                    projectIconImportTarget = page
                    isProjectIconSourceDialogPresented = true
                },
                onDeletePage: { page in
                    deletePage(page)
                },
                onDebugICloudSync: {
                    requestDebugICloudSync()
                }
            )
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .project(let pageID):
                    if let page = library.page(withID: pageID) {
                        ProjectPageListView(
                            page: page,
                            onSelectEntry: { page, entry in
                                router.push(page: page, entry: entry)
                            }
                        )
                    } else {
                        MissingPageView()
                    }
                case .viewer(let pageID, let entryID):
                    if let page = library.page(withID: pageID) {
                        let entry = library.entry(withID: entryID, in: page) ?? library.defaultEntry(for: page)
                        HTMLViewerView(
                            page: page,
                            entry: entry,
                            onRenameProject: { page, title in
                                renamePage(page, to: title)
                            },
                            onDeletePage: {
                                deletePage(page)
                                router.popToRoot()
                            },
                            onRuntimeStorageChanged: {
                                scheduleRuntimeStorageSync()
                            },
                            onActivityChanged: {
                                scheduleActivitySync()
                            },
                            onOpenProEntitlement: {
                                presentProEntitlement()
                            }
                        )
                    } else {
                        MissingPageView()
                    }
                case .fileViewer(let pageID):
                    if let page = library.page(withID: pageID) {
                        NativeFileViewerView(
                            page: page,
                            folderURL: library.folderURL(for: page),
                            files: library.projectFiles(for: page),
                            onRenameProject: { page, title in
                                renamePage(page, to: title)
                            },
                            onDeletePage: {
                                deletePage(page)
                                router.popToRoot()
                            },
                            onOpenProEntitlement: {
                                presentProEntitlement()
                            }
                        )
                    } else {
                        MissingPageView()
                    }
                case .recentlyDeleted:
                    RecentlyDeletedWebPagesView(
                        deletedPages: library.recentlyDeletedPages,
                        canViewFullHistory: proEntitlementStore.canViewFullRecentlyDeleted,
                        projectIconURL: { deletedPage in
                            library.projectIconURL(for: deletedPage)
                        },
                        onOpenProject: { deletedPage in
                            router.openDeletedViewer(
                                deletedPage: deletedPage,
                                entry: library.defaultEntry(for: deletedPage)
                            )
                        },
                        onSelectEntry: { deletedPage, entry in
                            router.openDeletedViewer(deletedPage: deletedPage, entry: entry)
                        },
                        onRestore: { deletedPage in
                            restoreDeletedPage(deletedPage)
                        },
                        onPermanentlyDelete: { deletedPage in
                            permanentlyDelete(deletedPage)
                        },
                        onOpenProEntitlement: {
                            presentProEntitlement()
                        }
                    )
                case .deletedProject(let pageID):
                    if let deletedPage = accessibleRecentlyDeletedPage(withID: pageID) {
                        RecentlyDeletedProjectPageListView(
                            deletedPage: deletedPage,
                            onSelectEntry: { deletedPage, entry in
                                router.pushDeletedViewer(deletedPage: deletedPage, entry: entry)
                            }
                        )
                    } else {
                        MissingPageView()
                    }
                case .deletedViewer(let pageID, let entryID):
                    if let deletedPage = accessibleRecentlyDeletedPage(withID: pageID) {
                        let entry = library.entry(withID: entryID, in: deletedPage) ??
                            library.defaultEntry(for: deletedPage)
                        HTMLViewerView(
                            page: deletedPage.page,
                            entry: entry,
                            deletedPage: deletedPage,
                            onRenameProject: { _, _ in },
                            onDeletePage: {},
                            onRestoreDeletedPage: {
                                if restoreDeletedPage(deletedPage) {
                                    router.openRecentlyDeleted()
                                    return true
                                }
                                return false
                            },
                            onPermanentlyDeletePage: {
                                permanentlyDelete(deletedPage)
                                router.openRecentlyDeleted()
                            },
                            onRuntimeStorageChanged: {},
                            onOpenProEntitlement: {
                                presentProEntitlement()
                            }
                        )
                    } else {
                        MissingPageView()
                    }
                case .deletedFileViewer(let pageID):
                    if let deletedPage = accessibleRecentlyDeletedPage(withID: pageID) {
                        NativeFileViewerView(
                            page: deletedPage.page,
                            folderURL: library.recoverableFolderURL(for: deletedPage),
                            files: library.projectFiles(for: deletedPage),
                            deletedPage: deletedPage,
                            onRenameProject: { _, _ in },
                            onDeletePage: {},
                            onRestoreDeletedPage: {
                                if restoreDeletedPage(deletedPage) {
                                    router.openRecentlyDeleted()
                                    return true
                                }
                                return false
                            },
                            onPermanentlyDeletePage: {
                                permanentlyDelete(deletedPage)
                                router.openRecentlyDeleted()
                            },
                            onOpenProEntitlement: {
                                presentProEntitlement()
                            }
                        )
                    } else {
                        MissingPageView()
                    }
                }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var homeDisplayMode: HomeDisplayMode {
        HomeDisplayMode.value(for: homeDisplayModeRaw)
    }

    private var shouldShowProEntitlementPromoSnackbar: Bool {
        importPreview == nil &&
        isInitialRouteGateReleased &&
        router.path.isEmpty &&
        proEntitlementMarketingFunnelStore.shouldShowPromoSnackbar
    }

    private var shouldShowAgentImportFloatingConnection: Bool {
        importPreview == nil &&
        agentImportSession.isRunning &&
            settingsPresentedSheet != .agentImport &&
            rootPresentedSheet != .agentImport
    }

    private var runtimePresentationModifier: AppRuntimePresentationModifier {
        AppRuntimePresentationModifier(
            proEntitlementDestination: $proEntitlementDestination,
            proEntitlementStore: proEntitlementStore,
            proEntitlementMarketingFunnelStore: proEntitlementMarketingFunnelStore,
            versionUpdatePromptStore: versionUpdatePromptStore
        )
    }

    @ViewBuilder
    private var settingsSidebarContent: some View {
        SettingsSidebar(
            iCloudSyncService: iCloudSyncService,
            iCloudSyncAccess: iCloudSyncAccess,
            proEntitlementStore: proEntitlementStore,
            debugFloatingBallVisibilityStore: debugFloatingBallVisibilityStore,
            path: $settingsSidebarPath,
            resetID: settingsSidebarResetID,
            containerStyle: Self.usesIPadSettingsPopover ? .systemPopover : .appBackground,
            onICloudSyncEnabled: {
                scheduleICloudSyncIfAllowed(reason: AppStrings.localized("syncReason.settingsEnabled"))
            },
            onICloudSyncDisabled: {
                handleICloudSyncAccessChanged()
            },
            onICloudSyncNow: {
                Task {
                    await performICloudSyncIfAllowed(reason: AppStrings.localized("手动同步 iCloud"))
                }
            },
            onOpenHubShares: {
                presentHubSharesFromSettings()
            },
            onOpenRecentlyDeleted: {
                presentRecentlyDeletedFromSettings()
            },
            onOpenProjectWidgetGuide: {
                presentProjectWidgetGuideFromSettings()
            },
            onOpenICloudSyncProEntitlementGuide: {
                presentICloudSyncProEntitlementGuideFromSettings()
            },
            onOpenAgentImport: {
                presentAgentImportFromSettings()
            },
            onOpenDebugTools: {
                presentDebugToolsFromSettings()
            },
            onOpenProEntitlement: {
                presentProEntitlementFromSettings()
            }
        )
        .id(settingsMenuRequestID)
        .sheet(item: $settingsPresentedSheet) { sheet in
            settingsSheet(for: sheet, host: .settings)
                .preferredColorScheme(appearancePreference.colorScheme)
        }
    }

    @ViewBuilder
    private func settingsSheet(for sheet: SettingsPresentedSheet, host: SettingsSheetHost) -> some View {
        switch sheet {
        case .recentlyDeleted:
            SettingsRecentlyDeletedSheet(
                deletedPages: library.recentlyDeletedPages,
                canViewFullHistory: proEntitlementStore.canViewFullRecentlyDeleted,
                deletedPage: { pageID in
                    library.recentlyDeletedPage(withID: pageID)
                },
                projectIconURL: { deletedPage in
                    library.projectIconURL(for: deletedPage)
                },
                defaultEntry: { deletedPage in
                    library.defaultEntry(for: deletedPage)
                },
                entry: { entryID, deletedPage in
                    library.entry(withID: entryID, in: deletedPage)
                },
                recoverableFolderURL: { deletedPage in
                    library.recoverableFolderURL(for: deletedPage)
                },
                projectFiles: { deletedPage in
                    library.projectFiles(for: deletedPage)
                },
                onRestore: { deletedPage in
                    restoreDeletedPage(deletedPage)
                },
                onPermanentlyDelete: { deletedPage in
                    permanentlyDelete(deletedPage)
                },
                onOpenProEntitlement: {
                    presentProEntitlement(from: host, replacingCurrentSheet: true)
                }
            )
            .environment(library)
        case .hubShares:
            SettingsHubSharesSheet(
                canUseExtendedRetention: proEntitlementStore.hasProEntitlement,
                onOpenProEntitlement: {
                    presentProEntitlement(from: host, replacingCurrentSheet: true)
                }
            )
            .environment(library)
        case .projectWidgetGuide:
            SettingsProjectWidgetGuideSheet()
        case .iCloudSyncProEntitlementGuide:
            SettingsICloudSyncProEntitlementGuideSheet(
                onOpenProEntitlement: {
                    presentProEntitlement(from: host, replacingCurrentSheet: true)
                }
            )
        case .agentImport:
            SettingsAgentImportSheet(
                session: agentImportSession,
                library: library,
                canStartSession: proEntitlementStore.canUseAgentAutomation,
                onImport: { result in
                    handleAgentImport(result)
                },
                onLibraryChanged: { reasonKey in
                    scheduleICloudSyncIfAllowed(reason: AppStrings.localized(reasonKey))
                },
                onOpenProEntitlement: {
                    presentProEntitlement(from: host, replacingCurrentSheet: true)
                }
            )
        case .proEntitlement(let destination):
            SettingsProEntitlementSheet(destination: destination)
                .environmentObject(proEntitlementStore)
                .environmentObject(proEntitlementMarketingFunnelStore)
        case .debugTools:
            NavigationStack {
                DebugToolsPage(
                    proEntitlementStore: proEntitlementStore,
                    iCloudSyncDebugSnapshot: iCloudSyncDebugSnapshot,
                    onRunICloudSyncTest: runDebugICloudSyncTest,
                    onResetICloudSyncEnvironment: resetDebugICloudSyncEnvironment,
                    showsDoneButton: true
                )
            }
            .environment(library)
            .presentationDetents([.height(440), .medium, .large], selection: $settingsDebugSheetDetent)
            .presentationDragIndicator(.visible)
        }
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            startFileImportFlow(from: url)
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    private func handleProjectWidgetURL(_ url: URL) -> Bool {
        guard url.scheme == ProjectWidgetShared.openProjectScheme else {
            return false
        }

        if ProjectWidgetShared.isHomeURL(url) {
            routeFromExternalEntry {
                router.popToRoot()
            }
            return true
        }

        if ProjectWidgetShared.isProEntitlementURL(url) {
            routeFromExternalEntry {
                router.popToRoot()
            }
            presentProEntitlement()
            return true
        }

        guard let projectID = ProjectWidgetShared.projectID(from: url) else {
            routeFromExternalEntry {
                router.popToRoot()
            }
            return true
        }

        guard let page = library.page(withID: projectID) else {
            routeFromExternalEntry {
                router.popToRoot()
            }
            importError = AppStrings.localized("这个网页项目已经不在本机网页列表中。")
            return true
        }

        let defaultEntry = library.defaultEntry(for: page)
        let loadStatus = page.opensInNativeFileViewer || page.opensInSingleFilePreview ? page.lastLoadStatus : defaultEntry.lastLoadStatus
        guard !loadStatus.isCloudPackageUnavailable else {
            routeFromExternalEntry {
                router.popToRoot()
            }
            importError = AppStrings.localized("正在同步中，请稍后再打开。")
            return true
        }

        routeFromExternalEntry {
            router.open(page: page, entry: defaultEntry)
        }
        return true
    }

    private func processProjectWidgetLaunchContextIfNeeded() {
        guard let context = projectWidgetLaunchStore.context,
              routedProjectWidgetLaunchContextID != context.id else {
            return
        }
        processProjectWidgetLaunchContext(context)
    }

    private func processProjectWidgetLaunchContext(_ context: ProjectWidgetLaunchContext) {
        guard routedProjectWidgetLaunchContextID != context.id else { return }
        routedProjectWidgetLaunchContextID = context.id
        _ = handleProjectWidgetURL(context.url)
        scheduleProjectWidgetLaunchGateRelease(for: context.id)
    }

    private func scheduleProjectWidgetLaunchGateRelease(for contextID: UUID) {
        Task {
            try? await Task.sleep(nanoseconds: 160_000_000)
            await MainActor.run {
                guard projectWidgetLaunchStore.context?.id == contextID else { return }
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    releasedProjectWidgetLaunchContextID = contextID
                }
                releaseInitialRouteGate()
            }
        }
    }

    private func releaseInitialRouteGate() {
        guard !isInitialRouteGateReleased else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isInitialRouteGateReleased = true
        }
    }

    private func scheduleInitialRouteGateReleaseIfNeeded() {
        guard !hasScheduledInitialRouteGateRelease else { return }
        hasScheduledInitialRouteGateRelease = true

        Task {
            try? await Task.sleep(nanoseconds: 180_000_000)
            await MainActor.run {
                releaseInitialRouteGate()
            }
        }
    }

    private func prepareForExternalEntryNavigation() {
        importPreview = nil
        settingsPresentedSheet = nil
        rootPresentedSheet = nil
        resetSettingsSidebarNavigation()
        settingsMenuDismissRequestID += 1
    }

    private func routeFromExternalEntry(_ update: () -> Void) {
        prepareForExternalEntryNavigation()
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            update()
        }
    }

    private func refreshProjectWidgetEntitlementSnapshot(reloadsTimelines: Bool = true) {
        guard proEntitlementStore.proEntitlementState != .unknown else { return }

        let didWrite = ProjectWidgetShared.updateEntitlement(
            canBindMultipleProjects: proEntitlementStore.canBindMultipleWidgetProjects,
            activeProjectIDs: Set(library.pages.map(\.id))
        )
        guard didWrite, reloadsTimelines else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: ProjectWidgetShared.widgetKind)
    }

    private func handleProjectIconImportResult(_ result: Result<[URL], Error>) {
        defer {
            projectIconImportTarget = nil
            isProjectIconImporterPresented = false
        }
        guard let page = projectIconImportTarget else { return }
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            if library.setCustomProjectIcon(for: page, from: url) {
                scheduleICloudSyncIfAllowed(reason: AppStrings.localized("syncReason.projectIcon"))
            } else {
                importError = AppStrings.localized("无法设置图标")
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    private func handleProjectIconPhotoSelection(_ item: PhotosPickerItem) async {
        defer {
            selectedProjectIconPhotoItem = nil
            projectIconImportTarget = nil
            isProjectIconPhotoPickerPresented = false
        }
        guard let page = projectIconImportTarget else { return }

        do {
            guard let imageData = try await item.loadTransferable(type: Data.self) else {
                importError = AppStrings.localized("无法设置图标")
                return
            }
            if library.setCustomProjectIcon(for: page, imageData: imageData) {
                scheduleICloudSyncIfAllowed(reason: AppStrings.localized("syncReason.projectIcon"))
            } else {
                importError = AppStrings.localized("无法设置图标")
            }
        } catch {
            importError = error.localizedDescription
        }
    }

    private func startFileImportFlow(from url: URL) {
        releaseInitialRouteGate()

        let previewID = UUID()
        let preview = WebPageImportPreview(
            id: previewID,
            sourceFileName: Self.fileImportDisplayName(for: url),
            source: .file,
            phase: .importing
        )

        routeFromExternalEntry {
            importPreview = preview
            router.popToRoot()
        }

        Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(nanoseconds: 60_000_000)
            guard importPreview?.id == previewID else { return }
            await importAndOpen(url, previewID: previewID)
        }
    }

    private func startURLImportFlow(from rawInput: String) {
        releaseInitialRouteGate()

        let remoteURLs: [URL]
        do {
            remoteURLs = try RemoteWebPageImportDownloader.hubCodeURLs(from: rawInput)
        } catch {
            importError = error.localizedDescription
            return
        }
        guard let displayURL = remoteURLs.first else {
            importError = RemoteWebPageImportError.invalidInput.localizedDescription
            return
        }

        let previewID = UUID()
        let preview = WebPageImportPreview(
            id: previewID,
            sourceFileName: displayURL.absoluteString,
            source: .url,
            phase: .importing
        )

        routeFromExternalEntry {
            importPreview = preview
            router.popToRoot()
        }

        Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(nanoseconds: 60_000_000)
            guard importPreview?.id == previewID else { return }
            await downloadAndImport(remoteURLs, previewID: previewID)
        }
    }

    private func downloadAndImport(_ remoteURLs: [URL], previewID: UUID) async {
        do {
            let localURL = try await RemoteWebPageImportDownloader.download(from: remoteURLs)
            defer {
                try? FileManager.default.removeItem(at: localURL.deletingLastPathComponent())
            }
            guard importPreview?.id == previewID else { return }
            await importAndOpen(localURL, previewID: previewID)
        } catch {
            if importPreview?.id == previewID {
                importPreview?.phase = .failed(error.localizedDescription)
            } else {
                importError = error.localizedDescription
            }
        }
    }

    private func importAndOpen(_ url: URL, previewID: UUID? = nil) async {
        do {
            let result = try library.importWebPage(from: url)
            scheduleICloudSyncIfAllowed(reason: AppStrings.localized("syncReason.import"))
            openImportedProject(result)
        } catch {
            if let previewID, importPreview?.id == previewID {
                importPreview?.phase = .failed(error.localizedDescription)
            } else {
                importError = error.localizedDescription
            }
        }
    }

    private func openImportedProject(_ result: WebPageImportResult) {
        routeFromExternalEntry {
            importPreview = nil
            router.open(page: result.page, entry: result.entry)
        }
    }

    private static func fileImportDisplayName(for url: URL) -> String {
        let name = url.lastPathComponent
        return name.removingPercentEncoding ?? name
    }

    private func retryImport(from source: WebPageImportPreviewSource) {
        switch source {
        case .file:
            fileImportRequestID += 1
        case .url:
            presentURLImportAlert()
        }
    }

    private func presentURLImportAlert() {
        urlImportDraft = ""
        isURLImportAlertPresented = true
    }

    private func submitURLImport() {
        let rawInput = urlImportDraft
        urlImportDraft = ""
        startURLImportFlow(from: rawInput)
    }

    private func handleAgentImport(_ result: WebPageImportResult) {
        scheduleICloudSyncIfAllowed(reason: AppStrings.localized("syncReason.import"))
        openImportedProject(result)
    }

    private func deletePage(_ page: WebPage) {
        library.delete(page)
        scheduleICloudSyncIfAllowed(reason: AppStrings.localized("syncReason.delete"))
    }

    private func presentRecentlyDeletedFromSettings() {
        settingsPresentedSheet = .recentlyDeleted
    }

    private func presentHubSharesFromSettings() {
        settingsPresentedSheet = .hubShares
    }

    private func presentProjectWidgetGuideFromSettings() {
        settingsPresentedSheet = .projectWidgetGuide
    }

    private func presentICloudSyncProEntitlementGuideFromSettings() {
        settingsPresentedSheet = .iCloudSyncProEntitlementGuide
    }

    private func presentAgentImportFromSettings() {
        startAgentImportSessionIfGuideCompleted()
        settingsPresentedSheet = .agentImport
    }

    private func presentAgentImportFromFloatingConnection() {
        rootPresentedSheet = .agentImport
    }

    private func presentProEntitlement() {
        let destination = proEntitlementStore.destination
        proEntitlementDestination = nil
        DispatchQueue.main.async {
            proEntitlementDestination = destination
        }
    }

    private func presentProEntitlementFromSettings() {
        presentProEntitlement(from: .settings, replacingCurrentSheet: settingsPresentedSheet != nil)
    }

    private func presentProEntitlement(from host: SettingsSheetHost, replacingCurrentSheet: Bool) {
        let destination = proEntitlementStore.destination

        switch host {
        case .settings:
            guard replacingCurrentSheet else {
                settingsPresentedSheet = .proEntitlement(destination)
                return
            }

            settingsPresentedSheet = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.settingsProEntitlementPresentationDelay) {
                settingsPresentedSheet = .proEntitlement(destination)
            }
        case .root:
            guard replacingCurrentSheet else {
                presentProEntitlement()
                return
            }

            rootPresentedSheet = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.settingsProEntitlementPresentationDelay) {
                proEntitlementDestination = nil
                DispatchQueue.main.async {
                    proEntitlementDestination = destination
                }
            }
        }
    }

    private func startAgentImportSessionIfGuideCompleted() {
        guard proEntitlementStore.canUseAgentAutomation,
              hasCompletedAgentImportGuide,
              scenePhase == .active,
              agentImportSession.status == .stopped || agentImportSession.status == .failed else {
            return
        }
        agentImportSession.start(
            library: library,
            onImport: { result in
                handleAgentImport(result)
            },
            onLibraryChanged: { reasonKey in
                scheduleICloudSyncIfAllowed(reason: AppStrings.localized(reasonKey))
            }
        )
    }

    private func presentDebugToolsFromSettings() {
        settingsDebugSheetDetent = .large
        settingsPresentedSheet = .debugTools
    }

    private func accessibleRecentlyDeletedPage(withID pageID: WebPage.ID) -> DeletedWebPage? {
        guard let deletedPage = library.recentlyDeletedPage(withID: pageID),
              RecentlyDeletedVisibilityPolicy.isVisible(
                  deletedPage,
                  canViewFullHistory: proEntitlementStore.canViewFullRecentlyDeleted
              ) else {
            return nil
        }
        return deletedPage
    }

    private func resetSettingsSidebarNavigation() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            settingsSidebarPath = []
            settingsSidebarResetID += 1
        }
    }

    private func restoreDeletedPage(_ deletedPage: DeletedWebPage) -> Bool {
        do {
            _ = try library.restore(deletedPage)
            scheduleICloudSyncIfAllowed(reason: AppStrings.localized("syncReason.restore"))
            return true
        } catch {
            // The item remains in Recently Deleted and continues to show its missing status.
            return false
        }
    }

    private func permanentlyDelete(_ deletedPage: DeletedWebPage) {
        library.permanentlyDelete(deletedPage)
        scheduleICloudSyncIfAllowed(reason: AppStrings.localized("syncReason.permanentDelete"))
    }

    private func renamePage(_ page: WebPage, to title: String) {
        if library.rename(page, to: title) {
            scheduleICloudSyncIfAllowed(reason: AppStrings.localized("syncReason.rename"))
        }
    }

    private func scheduleRuntimeStorageSync() {
        scheduleICloudSyncIfAllowed(reason: AppStrings.localized("syncReason.runtimeStorage"))
    }

    private func scheduleActivitySync() {
        scheduleICloudSyncIfAllowed(reason: AppStrings.localized("syncReason.activity"))
    }

    private var iCloudSyncAccess: ICloudWebPageSyncAccess {
        guard AppDistribution.current.supportsOfficialICloudSync else {
            return .userDisabled
        }

        switch proEntitlementStore.proEntitlementState {
        case .unknown:
            return .proEntitlementUnknown
        case .free:
            return .proEntitlementRequired
        case .expired:
            return .proEntitlementExpired
        case .active:
            return isICloudSyncEnabled ? .allowed : .userDisabled
        }
    }

    private var homeICloudEmptyState: HomeICloudEmptyState {
        guard AppDistribution.current.supportsOfficialICloudSync else {
            return .normal
        }

        guard library.pages.isEmpty else {
            return .normal
        }

        let hasRemotePresenceHint = iCloudPresenceStore.hasPossibleRemotePages(
            comparedToActiveProjectCount: library.pages.count
        )

        switch proEntitlementStore.proEntitlementState {
        case .free, .expired:
            return hasRemotePresenceHint ? .proEntitlementPrompt : .normal
        case .active:
            guard isICloudSyncEnabled else { return .normal }
            if hasRemotePresenceHint,
               latestICloudSyncRecord?.kind == .failed ||
                    latestICloudSyncRecord?.kind == .noAccount ||
                    latestICloudSyncRecord?.kind == .unavailable {
                return .failed
            }
            if hasRemotePresenceHint || latestICloudSyncRecord?.kind == .inProgress {
                return isHomeCloudSyncDelayElapsed ? .syncing : .normal
            }
            return .normal
        case .unknown:
            return .normal
        }
    }

    private var latestICloudSyncRecord: ICloudWebPageSyncUserRecord? {
        iCloudSyncService?.userRecords.first
    }

    private var iCloudSyncDebugSnapshot: DebugICloudSyncSnapshot {
        DebugICloudSyncSnapshot(
            access: iCloudSyncAccess,
            isUserPreferenceEnabled: isICloudSyncEnabled,
            isServiceCreated: iCloudSyncService != nil,
            latestRecord: latestICloudSyncRecord,
            presenceLines: iCloudPresenceStore.debugSummaryLines
        )
    }

    private func ensureICloudSyncService() -> ICloudWebPageSyncService? {
        guard iCloudSyncAccess.allowsPrivateDatabaseAccess else {
            iCloudSyncService?.updateAccess(iCloudSyncAccess)
            iCloudSyncService = nil
            return nil
        }
        if let iCloudSyncService {
            iCloudSyncService.updateAccess(iCloudSyncAccess)
            return iCloudSyncService
        }
        let service = ICloudWebPageSyncService(library: library, access: iCloudSyncAccess)
        iCloudSyncService = service
        return service
    }

    private func handleICloudSyncAccessChanged() {
        refreshHomeCloudSyncDelayState()

        guard iCloudSyncAccess.allowsPrivateDatabaseAccess else {
            iCloudSyncService?.updateAccess(iCloudSyncAccess)
            iCloudSyncService = nil
            return
        }

        let service = ensureICloudSyncService()
        service?.updateAccess(iCloudSyncAccess)
        service?.scheduleSync(reason: AppStrings.localized("syncReason.entitlementChanged"))
        schedulePossibleRemoteInitialSyncIfNeeded()
    }

    private func scheduleICloudSyncIfAllowed(reason: String) {
        refreshICloudPresenceSummary()
        guard let service = ensureICloudSyncService() else { return }
        service.scheduleSync(reason: reason)
    }

    private func performICloudSyncIfAllowed(reason: String) async {
        guard let service = ensureICloudSyncService() else { return }
        await service.performSync(reason: reason)
    }

    private func refreshICloudPresenceSummary() {
        iCloudPresenceStore.updateLocalSummary(
            activeProjectCount: library.pages.count,
            contentChangedAt: library.iCloudPresenceContentChangedAt
        )
    }

    private func handleICloudPresenceChanged() {
        refreshHomeCloudSyncDelayState()
        schedulePossibleRemoteInitialSyncIfNeeded()
    }

    private func schedulePossibleRemoteInitialSyncIfNeeded() {
        guard iCloudSyncAccess.allowsPrivateDatabaseAccess,
              library.pages.isEmpty,
              iCloudPresenceStore.hasPossibleRemotePages(comparedToActiveProjectCount: library.pages.count) else {
            hasScheduledPossibleRemoteInitialSync = false
            return
        }

        guard !hasScheduledPossibleRemoteInitialSync else { return }
        hasScheduledPossibleRemoteInitialSync = true
        scheduleICloudSyncIfAllowed(reason: AppStrings.localized("syncReason.homeRemotePresence"))
    }

    private func refreshHomeCloudSyncDelayState() {
        guard iCloudSyncAccess.allowsPrivateDatabaseAccess,
              library.pages.isEmpty,
              (
                iCloudPresenceStore.hasPossibleRemotePages(comparedToActiveProjectCount: library.pages.count) ||
                    latestICloudSyncRecord?.kind == .inProgress
              ),
              latestICloudSyncRecord?.kind != .failed,
              latestICloudSyncRecord?.kind != .noAccount,
              latestICloudSyncRecord?.kind != .unavailable else {
            homeCloudSyncDelayTask?.cancel()
            homeCloudSyncDelayTask = nil
            isHomeCloudSyncDelayElapsed = false
            return
        }

        guard homeCloudSyncDelayTask == nil,
              !isHomeCloudSyncDelayElapsed else { return }
        homeCloudSyncDelayTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            isHomeCloudSyncDelayElapsed = true
            homeCloudSyncDelayTask = nil
        }
    }

    private func requestDebugICloudSync() {
        #if DEBUG
        Task {
            let result = await runDebugICloudSyncTest()
            debugICloudSyncResult = result
        }
        #endif
    }

    private func runDebugICloudSyncTest() async -> ICloudWebPageSyncDebugResult {
        #if DEBUG
        guard let service = ensureICloudSyncService() else {
            return ICloudWebPageSyncDebugResult(
                title: iCloudSyncAccess.blockedDebugTitle,
                message: iCloudSyncBlockedDebugMessage(
                    conclusion: [
                        "结果：跳过同步",
                        "门控：\(iCloudSyncAccess.debugStatusText)",
                        "说明：\(iCloudSyncAccess.blockedDebugMessage)",
                        "CloudKit：未访问 private database"
                    ]
                )
            )
        }
        return await service.performDebugSync()
        #else
        return ICloudWebPageSyncDebugResult(title: "", message: "")
        #endif
    }

    private func resetDebugICloudSyncEnvironment() async -> ICloudWebPageSyncDebugResult {
        #if DEBUG
        iCloudPresenceStore.clearDebugData()
        guard let service = ensureICloudSyncService() else {
            return ICloudWebPageSyncDebugResult(
                title: iCloudSyncAccess.blockedDebugTitle,
                message: iCloudSyncBlockedDebugMessage(
                    conclusion: [
                        "结果：已清空 KVS 轻量摘要；CloudKit 远端清理因门控跳过",
                        "门控：\(iCloudSyncAccess.debugStatusText)",
                        "说明：\(iCloudSyncAccess.blockedDebugMessage)"
                    ]
                )
            )
        }
        return await service.performDebugEnvironmentReset()
        #else
        return ICloudWebPageSyncDebugResult(title: "", message: "")
        #endif
    }

    private func iCloudSyncBlockedDebugMessage(conclusion: [String]) -> String {
        let hasRemotePages = iCloudPresenceStore.hasPossibleRemotePages(
            comparedToActiveProjectCount: library.pages.count
        )
        let homeLines = [
            "本机网页数：\(library.pages.count)",
            "可能存在其他设备网页：\(hasRemotePages ? "是" : "否")",
            "首页 iCloud 空态：\(homeICloudEmptyState.debugDescription)"
        ]

        var lines: [String] = ["【结论】"]
        lines.append(contentsOf: conclusion)
        lines.append("【轻量 KVS 多设备检测】")
        lines.append(contentsOf: iCloudPresenceStore.debugSummaryLines)
        lines.append("【首页判断】")
        lines.append(contentsOf: homeLines)
        return lines.joined(separator: "\n")
    }

    private func copyDebugICloudSyncResult(_ result: ICloudWebPageSyncDebugResult) {
        #if DEBUG
        UIPasteboard.general.string = "\(result.title)\n\n\(result.message)"
        #endif
    }

    private static func layoutDirectionIdentity(for layoutDirection: LayoutDirection?) -> String {
        switch layoutDirection {
        case .leftToRight:
            return "ltr"
        case .rightToLeft:
            return "rtl"
        case nil:
            return "system"
        @unknown default:
            return "system"
        }
    }

    private static var usesIPadSettingsPopover: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }
}

private struct AppRootAlertModifier: ViewModifier {
    @Binding var importError: String?
    @Binding var debugICloudSyncResult: ICloudWebPageSyncDebugResult?
    let onCopyDebugICloudSyncResult: (ICloudWebPageSyncDebugResult) -> Void

    func body(content: Content) -> some View {
        content
            .alert(AppStrings.localized("无法打开网页"), isPresented: importErrorBinding) {
                Button(AppStrings.localized("知道了"), role: .cancel) {
                    importError = nil
                }
            } message: {
                Text(importError ?? "")
            }
            .alert(item: $debugICloudSyncResult) { result in
                Alert(
                    title: Text(result.title),
                    message: Text(result.message),
                    primaryButton: .default(Text(AppStrings.localized("复制"))) {
                        onCopyDebugICloudSyncResult(result)
                    },
                    secondaryButton: .cancel(Text(AppStrings.localized("知道了")))
                )
            }
    }

    private var importErrorBinding: Binding<Bool> {
        Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )
    }
}

private struct AppRuntimePresentationModifier: ViewModifier {
    @State private var discountOfferPresentation: DiscountOfferPresentation?
    @State private var handledDiscountOfferRequestID: UUID?

    @Binding var proEntitlementDestination: ProEntitlementDestination?
    @ObservedObject var proEntitlementStore: ProEntitlementStore
    @ObservedObject var proEntitlementMarketingFunnelStore: ProEntitlementMarketingFunnelStore
    @ObservedObject var versionUpdatePromptStore: VersionUpdatePromptStore

    func body(content: Content) -> some View {
        content
            .sheet(item: $discountOfferPresentation, onDismiss: {
                proEntitlementMarketingFunnelStore.dismissDiscountSheet()
            }) { _ in
                #if HTMLKEEP_COMMUNITY
                ProEntitlementDiscountOfferSheet()
                    .environmentObject(proEntitlementStore)
                    .environmentObject(proEntitlementMarketingFunnelStore)
                    .onAppear {
                        proEntitlementMarketingFunnelStore.noteDiscountSheetPresented()
                    }
                #else
                DiscountOfferSheet()
                    .environmentObject(proEntitlementStore)
                    .environmentObject(proEntitlementMarketingFunnelStore)
                    .onAppear {
                        proEntitlementMarketingFunnelStore.noteDiscountSheetPresented()
                    }
                #endif
            }
            .fullScreenCover(item: $proEntitlementDestination) { destination in
                #if HTMLKEEP_COMMUNITY
                ProEntitlementDestinationView(
                    destination: destination
                )
                .environmentObject(proEntitlementStore)
                .environmentObject(proEntitlementMarketingFunnelStore)
                #else
                MembershipDestinationView(
                    destination: MembershipDestination(destination)
                )
                .environmentObject(proEntitlementStore)
                .environmentObject(proEntitlementMarketingFunnelStore)
                #endif
            }
            .background(
                VersionUpdatePromptRuntimeHost(store: versionUpdatePromptStore)
                    .frame(width: 0, height: 0)
            )
            .onAppear {
                syncDiscountOfferPresentation(for: proEntitlementMarketingFunnelStore.discountSheetPresentationRequestID)
            }
            .onChange(of: proEntitlementMarketingFunnelStore.discountSheetPresentationRequestID) { _, requestID in
                syncDiscountOfferPresentation(for: requestID)
            }
            .onChange(of: proEntitlementStore.proEntitlementState) { _, _ in
                syncDiscountOfferPresentation(for: proEntitlementMarketingFunnelStore.discountSheetPresentationRequestID)
            }
    }

    private func syncDiscountOfferPresentation(for requestID: UUID?) {
        guard !proEntitlementStore.hasProEntitlement else {
            clearDiscountOfferPresentation()
            return
        }
        guard let requestID else {
            clearDiscountOfferPresentation()
            return
        }
        guard handledDiscountOfferRequestID != requestID else { return }
        handledDiscountOfferRequestID = requestID
        discountOfferPresentation = DiscountOfferPresentation(id: requestID)
    }

    private func clearDiscountOfferPresentation() {
        handledDiscountOfferRequestID = nil
        discountOfferPresentation = nil
    }
}

private struct DiscountOfferPresentation: Identifiable {
    let id: UUID
}

private struct WebPageDocumentPickerPresenter: UIViewControllerRepresentable {
    let presentationRequestID: Int
    let onPick: (Result<[URL], Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        context.coordinator.presentedRequestID = presentationRequestID
        return viewController
    }

    func updateUIViewController(_ viewController: UIViewController, context: Context) {
        context.coordinator.onPick = onPick

        guard presentationRequestID != context.coordinator.presentedRequestID else {
            return
        }

        context.coordinator.presentedRequestID = presentationRequestID

        guard viewController.presentedViewController == nil else {
            return
        }

        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.html, .zip, .text, .data],
            asCopy: true
        )
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        viewController.present(picker, animated: true)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var presentedRequestID = 0
        var onPick: (Result<[URL], Error>) -> Void

        init(onPick: @escaping (Result<[URL], Error>) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            onPick(.success(urls))
        }
    }
}

private struct AppLayoutDirectionModifier: ViewModifier {
    let layoutDirection: LayoutDirection?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let layoutDirection {
            content.environment(\.layoutDirection, layoutDirection)
        } else {
            content
        }
    }
}

private struct ProjectWidgetLaunchBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    let cssBackground: String?

    var body: some View {
        let paint = ProjectWidgetPaint.resolve(from: cssBackground, colorScheme: colorScheme)
        paint.background
            .ignoresSafeArea()
    }
}

private struct AgentImportFloatingConnectionButton: View {
    @Binding var position: CGPoint?
    let action: () -> Void

    @State private var dragStartPosition: CGPoint?
    @State private var isDragging = false

    private let diameter: CGFloat = 64
    private let horizontalInset: CGFloat = 16
    private let bottomInset: CGFloat = 24
    private let titleBarReserve: CGFloat = 56

    var body: some View {
        GeometryReader { proxy in
            let resolvedPosition = clamped(position ?? defaultPosition(in: proxy), in: proxy)

            buttonBody
                .frame(width: diameter, height: diameter)
                .clipShape(Circle())
                .contentShape(Circle())
                .gesture(dragGesture(in: proxy, currentPosition: resolvedPosition))
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(AppStrings.localized("Agent 管理"))
                .accessibilityValue(AppStrings.localized("已开启"))
                .scaleEffect(isDragging ? 1.05 : 1)
                .shadow(color: Color.black.opacity(0.18), radius: 14, x: 0, y: 8)
                .position(resolvedPosition)
                .onAppear {
                    position = resolvedPosition
                }
                .onChange(of: proxy.size) { _, _ in
                    position = clamped(position ?? defaultPosition(in: proxy), in: proxy)
                }
                .animation(.snappy(duration: 0.18), value: isDragging)
        }
    }

    private var buttonBody: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [AppTheme.deepWater, Color(hex: 0x1E2633)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .stroke(Color.white.opacity(0.82), lineWidth: 1)
            VStack(spacing: 2) {
                AppColoredIcon(assetName: "IconAgentManagement", size: 28)
                    .accessibilityHidden(true)
                Text(AppStrings.localized("Agent"))
                    .font(.system(size: 11, weight: .black))
            }
            .foregroundStyle(.white)
        }
    }

    private func dragGesture(in proxy: GeometryProxy, currentPosition: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if dragStartPosition == nil {
                    dragStartPosition = currentPosition
                    isDragging = false
                }

                let distance = hypot(value.translation.width, value.translation.height)
                if distance > 4 {
                    isDragging = true
                }

                guard isDragging else { return }
                let start = dragStartPosition ?? currentPosition
                position = clamped(
                    CGPoint(
                        x: start.x + value.translation.width,
                        y: start.y + value.translation.height
                    ),
                    in: proxy
                )
            }
            .onEnded { value in
                let distance = hypot(value.translation.width, value.translation.height)
                if distance < 8 {
                    action()
                } else {
                    let start = dragStartPosition ?? currentPosition
                    position = clamped(
                        CGPoint(
                            x: start.x + value.translation.width,
                            y: start.y + value.translation.height
                        ),
                        in: proxy
                    )
                }
                dragStartPosition = nil
                isDragging = false
            }
    }

    private func defaultPosition(in proxy: GeometryProxy) -> CGPoint {
        let bounds = allowedBounds(in: proxy)
        return CGPoint(
            x: bounds.maxX,
            y: min(bounds.maxY, max(bounds.minY, proxy.size.height * 0.58))
        )
    }

    private func clamped(_ point: CGPoint, in proxy: GeometryProxy) -> CGPoint {
        let bounds = allowedBounds(in: proxy)
        return CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }

    private func allowedBounds(in proxy: GeometryProxy) -> (minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat) {
        let half = diameter / 2
        let minX = horizontalInset + half
        let maxX = max(minX, proxy.size.width - horizontalInset - half)
        let minY = max(horizontalInset + half, proxy.safeAreaInsets.top + titleBarReserve + half)
        let maxY = max(minY, proxy.size.height - max(proxy.safeAreaInsets.bottom, 0) - bottomInset - half)
        return (minX, maxX, minY, maxY)
    }
}

private enum SettingsSidebarRoute: Hashable {
    case homeLayout
    case language
    case appearance
}

private enum SettingsSheetHost {
    case settings
    case root
}

private enum SettingsPresentedSheet: Identifiable, Equatable {
    case recentlyDeleted
    case hubShares
    case projectWidgetGuide
    case iCloudSyncProEntitlementGuide
    case agentImport
    case proEntitlement(ProEntitlementDestination)
    case debugTools

    var id: String {
        switch self {
        case .recentlyDeleted:
            return "recentlyDeleted"
        case .hubShares:
            return "hubShares"
        case .projectWidgetGuide:
            return "projectWidgetGuide"
        case .iCloudSyncProEntitlementGuide:
            return "iCloudSyncProEntitlementGuide"
        case .agentImport:
            return "agentImport"
        case .proEntitlement(let destination):
            return "proEntitlement-\(destination.id)"
        case .debugTools:
            return "debugTools"
        }
    }
}

private enum SettingsRecentlyDeletedRoute: Hashable {
    case viewer(WebPage.ID, WebPageEntry.ID)
    case fileViewer(WebPage.ID)
}

private struct SettingsProjectWidgetGuideSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SettingsProjectWidgetGuideView()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        closeButton
                    }
                }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
        }
        .accessibilityLabel(AppStrings.localized("关闭"))
    }
}

private struct SettingsICloudSyncProEntitlementGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var measuredSheetHeight: CGFloat = 430

    let onOpenProEntitlement: () -> Void

    var body: some View {
        NavigationStack {
            SettingsICloudSyncProEntitlementGuideView(
                measuredSheetHeight: $measuredSheetHeight,
                onOpenProEntitlement: onOpenProEntitlement
            )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        closeButton
                    }
                }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .presentationDetents([.height(measuredSheetHeight), .large])
        .presentationDragIndicator(.visible)
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
        }
        .accessibilityLabel(AppStrings.localized("关闭"))
    }
}

private struct SettingsProEntitlementSheet: View {
    let destination: ProEntitlementDestination

    var body: some View {
        NavigationStack {
            #if HTMLKEEP_COMMUNITY
            ProEntitlementDestinationView(destination: destination)
            #else
            MembershipDestinationView(destination: MembershipDestination(destination))
            #endif
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

private struct SettingsAgentImportSheet: View {
    @Environment(\.dismiss) private var dismiss

    let session: AgentImportSessionController
    let library: WebPageLibrary
    let canStartSession: Bool
    let onImport: (WebPageImportResult) -> Void
    let onLibraryChanged: (String) -> Void
    let onOpenProEntitlement: () -> Void

    var body: some View {
        NavigationStack {
            AgentImportSessionView(
                session: session,
                library: library,
                canStartSession: canStartSession,
                onImport: onImport,
                onLibraryChanged: onLibraryChanged,
                onOpenProEntitlement: onOpenProEntitlement
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    closeButton
                }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
        }
        .accessibilityLabel(AppStrings.localized("关闭"))
    }
}

private struct SettingsRecentlyDeletedSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var path: [SettingsRecentlyDeletedRoute] = []

    let deletedPages: [DeletedWebPage]
    let canViewFullHistory: Bool
    let deletedPage: (WebPage.ID) -> DeletedWebPage?
    let projectIconURL: (DeletedWebPage) -> URL?
    let defaultEntry: (DeletedWebPage) -> WebPageEntry
    let entry: (WebPageEntry.ID, DeletedWebPage) -> WebPageEntry?
    let recoverableFolderURL: (DeletedWebPage) -> URL
    let projectFiles: (DeletedWebPage) -> [WebPageProjectFile]
    let onRestore: (DeletedWebPage) -> Bool
    let onPermanentlyDelete: (DeletedWebPage) -> Void
    let onOpenProEntitlement: () -> Void

    var body: some View {
        NavigationStack(path: $path) {
            recentlyDeletedList
                .navigationDestination(for: SettingsRecentlyDeletedRoute.self) { route in
                    destination(for: route)
                }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var recentlyDeletedList: some View {
        RecentlyDeletedWebPagesView(
            deletedPages: deletedPages,
            canViewFullHistory: canViewFullHistory,
            projectIconURL: projectIconURL,
            onOpenProject: { deletedPage in
                open(deletedPage: deletedPage, entry: defaultEntry(deletedPage))
            },
            onSelectEntry: { deletedPage, entry in
                open(deletedPage: deletedPage, entry: entry)
            },
            onRestore: onRestore,
            onPermanentlyDelete: onPermanentlyDelete,
            onOpenProEntitlement: onOpenProEntitlement
        )
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                closeButton
            }
        }
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
        }
        .accessibilityLabel(AppStrings.localized("关闭"))
    }

    @ViewBuilder
    private func destination(for route: SettingsRecentlyDeletedRoute) -> some View {
        switch route {
        case .viewer(let pageID, let entryID):
            if let deletedPage = accessibleDeletedPage(withID: pageID) {
                let selectedEntry = entry(entryID, deletedPage) ?? defaultEntry(deletedPage)
                HTMLViewerView(
                    page: deletedPage.page,
                    entry: selectedEntry,
                    deletedPage: deletedPage,
                    onRenameProject: { _, _ in },
                    onDeletePage: {},
                    onRestoreDeletedPage: {
                        if onRestore(deletedPage) {
                            path = []
                            return true
                        }
                        return false
                    },
                    onPermanentlyDeletePage: {
                        onPermanentlyDelete(deletedPage)
                        path = []
                    },
                    onRuntimeStorageChanged: {}
                )
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        closeButton
                    }
                }
            } else {
                MissingPageView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            closeButton
                        }
                    }
            }
        case .fileViewer(let pageID):
            if let deletedPage = accessibleDeletedPage(withID: pageID) {
                NativeFileViewerView(
                    page: deletedPage.page,
                    folderURL: recoverableFolderURL(deletedPage),
                    files: projectFiles(deletedPage),
                    deletedPage: deletedPage,
                    onRenameProject: { _, _ in },
                    onDeletePage: {},
                    onRestoreDeletedPage: {
                        if onRestore(deletedPage) {
                            path = []
                            return true
                        }
                        return false
                    },
                    onPermanentlyDeletePage: {
                        onPermanentlyDelete(deletedPage)
                        path = []
                    }
                )
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        closeButton
                    }
                }
            } else {
                MissingPageView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            closeButton
                        }
                    }
            }
        }
    }

    private func accessibleDeletedPage(withID pageID: WebPage.ID) -> DeletedWebPage? {
        guard let deletedPage = deletedPage(pageID),
              RecentlyDeletedVisibilityPolicy.isVisible(
                  deletedPage,
                  canViewFullHistory: canViewFullHistory
              ) else {
            return nil
        }
        return deletedPage
    }

    private func open(deletedPage: DeletedWebPage, entry: WebPageEntry) {
        if deletedPage.page.opensInNativeFileViewer || deletedPage.page.opensInSingleFilePreview {
            path.append(.fileViewer(deletedPage.id))
        } else {
            path.append(.viewer(deletedPage.id, entry.id))
        }
    }
}

private struct SettingsSidebar: View {
    let iCloudSyncService: ICloudWebPageSyncService?
    let iCloudSyncAccess: ICloudWebPageSyncAccess
    @ObservedObject var proEntitlementStore: ProEntitlementStore
    @ObservedObject var debugFloatingBallVisibilityStore: DebugFloatingBallVisibilityStore
    @Binding var path: [SettingsSidebarRoute]
    let resetID: Int
    let containerStyle: SettingsContainerStyle
    let onICloudSyncEnabled: () -> Void
    let onICloudSyncDisabled: () -> Void
    let onICloudSyncNow: () -> Void
    let onOpenHubShares: () -> Void
    let onOpenRecentlyDeleted: () -> Void
    let onOpenProjectWidgetGuide: () -> Void
    let onOpenICloudSyncProEntitlementGuide: () -> Void
    let onOpenAgentImport: () -> Void
    let onOpenDebugTools: () -> Void
    let onOpenProEntitlement: () -> Void

    var body: some View {
        NavigationStack(path: $path) {
            SettingsView(
                iCloudSyncService: iCloudSyncService,
                iCloudSyncAccess: iCloudSyncAccess,
                onICloudSyncEnabled: onICloudSyncEnabled,
                onICloudSyncDisabled: onICloudSyncDisabled,
                onICloudSyncNow: onICloudSyncNow,
                onOpenHubShares: {
                    onOpenHubShares()
                },
                onOpenRecentlyDeleted: {
                    onOpenRecentlyDeleted()
                },
                onOpenProjectWidgetGuide: {
                    onOpenProjectWidgetGuide()
                },
                onOpenICloudSyncProEntitlementGuide: {
                    onOpenICloudSyncProEntitlementGuide()
                },
                onOpenAgentImport: {
                    onOpenAgentImport()
                },
                onOpenHomeLayoutSettings: {
                    path.append(.homeLayout)
                },
                onOpenLanguageSettings: {
                    path.append(.language)
                },
                onOpenAppearanceSettings: {
                    path.append(.appearance)
                },
                onOpenDebugTools: onOpenDebugTools,
                onOpenProEntitlement: onOpenProEntitlement,
                debugFloatingBallVisibilityStore: debugFloatingBallVisibilityStore,
                containerStyle: containerStyle
            )
            .environmentObject(proEntitlementStore)
            .navigationDestination(for: SettingsSidebarRoute.self) { route in
                switch route {
                case .homeLayout:
                    SettingsHomeLayoutSelectionView(containerStyle: containerStyle)
                case .language:
                    SettingsLanguageSelectionView(containerStyle: containerStyle)
                case .appearance:
                    SettingsAppearanceSelectionView(containerStyle: containerStyle)
                }
            }
        }
        .id(resetID)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

private enum WebPageImportPreviewSource: Equatable {
    case file
    case url

    var retryTitle: String {
        switch self {
        case .file:
            return AppStrings.localized("打开文件")
        case .url:
            return AppStrings.localized("重新输入暗号")
        }
    }

    var retrySystemImage: String {
        switch self {
        case .file:
            return "doc.badge.plus"
        case .url:
            return "number"
        }
    }

    var importingDetail: String {
        switch self {
        case .file:
            return AppStrings.localized("正在整理这个文件，请稍等。")
        case .url:
            return AppStrings.localized("正在下载并整理这个暗号，请稍等。")
        }
    }
}

private enum WebPageImportPreviewPhase: Equatable {
    case importing
    case failed(String)
}

private struct WebPageImportPreview: Identifiable, Equatable {
    let id: UUID
    let sourceFileName: String
    let source: WebPageImportPreviewSource
    var phase: WebPageImportPreviewPhase
}

private struct WebPageImportPreviewView: View {
    let preview: WebPageImportPreview
    let onRetry: () -> Void
    let onReturnHome: () -> Void

    var body: some View {
        ZStack {
            AppPageBackground()

            switch preview.phase {
            case .importing:
                importingContent
            case .failed(let message):
                failedContent(message: message)
                    .padding(20)
            }
        }
    }

    private var importingContent: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
                .tint(AppTheme.deepWater)

            Text(AppStrings.localized("正在导入网页..."))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppTheme.contentPrimary)

            if !preview.sourceFileName.isEmpty {
                Text(preview.sourceFileName)
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.center)
            }

            Text(preview.source.importingDetail)
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 280)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failedContent(message: String) -> some View {
        AppSurfaceCard(isProminent: true) {
            SectionHeader(AppStrings.localized("导入失败"), systemImage: "exclamationmark.triangle")

            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if !preview.sourceFileName.isEmpty {
                AppInsetSurface {
                    Text(preview.sourceFileName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppTheme.contentPrimary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }

            AppActionButton(
                preview.source.retryTitle,
                systemImage: preview.source.retrySystemImage,
                scene: .sky,
                size: .medium,
                action: onRetry
            )

            AppActionButton(
                AppStrings.localized("返回首页"),
                systemImage: "house",
                scene: .neutralLight,
                size: .medium,
                action: onReturnHome
            )
        }
        .frame(maxWidth: 380)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MissingPageView: View {
    var body: some View {
        ZStack {
            AppPageBackground()

            AppSurfaceCard(isProminent: true) {
                SectionHeader(AppStrings.localized("网页不存在"), systemImage: "exclamationmark.triangle")
                Text(AppStrings.localized("这条网页记录已经不在本地网页库中。"))
                    .font(.system(size: 15))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(20)
        }
        .navigationTitle(AppStrings.localized("网页"))
    }
}
