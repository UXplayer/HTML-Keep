import Darwin
import Foundation
import Network
import SwiftUI
import UIKit

private let agentImportMaximumRequestByteCount = 210_000_000
private let agentImportDocumentedImportByteLimit = 200_000_000
private let agentImportDefaultPort: UInt16 = 10231

private enum AgentImportWebLanguage: String, CaseIterable {
    case zhHans = "zh-Hans"
    case en

    var htmlLang: String {
        switch self {
        case .zhHans:
            return "zh-CN"
        case .en:
            return "en"
        }
    }

    var dateLocale: String {
        switch self {
        case .zhHans:
            return "zh-CN"
        case .en:
            return "en-US"
        }
    }

    var displayName: String {
        switch self {
        case .zhHans:
            return "中文"
        case .en:
            return "English"
        }
    }

    var copy: AgentImportWebCopy {
        switch self {
        case .zhHans:
            return .zhHans
        case .en:
            return .en
        }
    }

    static func resolve(queryValue: String?, acceptLanguage: String?) -> AgentImportWebLanguage {
        if let language = match(queryValue) {
            return language
        }

        let acceptedValues = (acceptLanguage ?? "")
            .split(separator: ",")
            .map { value in
                value
                    .split(separator: ";", maxSplits: 1)
                    .first
                    .map(String.init) ?? ""
            }

        for value in acceptedValues {
            if let language = match(value) {
                return language
            }
        }

        return .zhHans
    }

    private static func match(_ rawValue: String?) -> AgentImportWebLanguage? {
        let normalized = (rawValue ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
        guard !normalized.isEmpty else { return nil }

        if normalized == "zh"
            || normalized == "zh-cn"
            || normalized == "zh-hans"
            || normalized == "zh-hans-cn"
            || normalized.hasPrefix("zh-hans-") {
            return .zhHans
        }
        if normalized == "en" || normalized.hasPrefix("en-") {
            return .en
        }
        return nil
    }
}

private struct AgentImportWebCopy {
    let pageTitle: String
    let heroTitle: String
    let heroSubtitle: String
    let loading: String
    let languageLabel: String
    let connectionTitle: String
    let copyAddress: String
    let connectionHelp: String
    let capabilitiesLabel: String
    let aiCopyTitle: String
    let recommendedBadge: String
    let aiCopyHelp: String
    let copyForAI: String
    let uploadTitle: String
    let uploadSubtitle: String
    let titleLabel: String
    let titlePlaceholder: String
    let fileLabel: String
    let selectedFileEmpty: String
    let openAfterUpload: String
    let uploadButton: String
    let refreshButton: String
    let initialNotice: String
    let statusTitle: String
    let statusMetric: String
    let expiryMetric: String
    let projectCountMetric: String
    let lastRefreshMetric: String
    let recentEventsTitle: String
    let projectsTitle: String
    let projectsInitialSummary: String
    let agentPanelTitle: String
    let agentPanelHelp: String
    let aiPromptNeeds: String
    let aiPromptInstruction: String
    let js: [String: Any]

    static let zhHans = AgentImportWebCopy(
        pageTitle: "随手网页 Agent 管理",
        heroTitle: "随手网页 Agent 管理",
        heroSubtitle: "让电脑上的 Agent 管理这台设备里的网页项目。上传、重命名和设置图标后，手机里的网页列表会立即更新。",
        loading: "读取中",
        languageLabel: "语言",
        connectionTitle: "当前连接地址",
        copyAddress: "复制地址",
        connectionHelp: "设备 IP 由当前 Wi-Fi 分配；端口和路径固定。支持本地发现的 Agent 可以通过 _htmlanywhere._tcp 自动找到这个会话。",
        capabilitiesLabel: "机器可读能力说明：",
        aiCopyTitle: "把这段话发给 AI",
        recommendedBadge: "推荐",
        aiCopyHelp: "复制下面这段话到电脑上的 AI / Agent，然后在“我的需求”后面补充你想发布、重命名、配图标或更新的内容。",
        copyForAI: "复制给 AI",
        uploadTitle: "上传到手机",
        uploadSubtitle: "适合单个 HTML、完整网页 ZIP，或者希望在手机里预览的普通文件。",
        titleLabel: "项目名称（可选）",
        titlePlaceholder: "例如：预算看板",
        fileLabel: "网页文件或 ZIP",
        selectedFileEmpty: "尚未选择文件。支持 .html、.htm、.zip 和普通文件，单次上传建议不超过 200 MB。",
        openAfterUpload: "上传后在手机上打开预览",
        uploadButton: "上传到随手网页",
        refreshButton: "刷新状态",
        initialNotice: "等待选择文件。",
        statusTitle: "会话状态",
        statusMetric: "状态",
        expiryMetric: "连接保持",
        projectCountMetric: "项目数量",
        lastRefreshMetric: "最后刷新",
        recentEventsTitle: "最近操作",
        projectsTitle: "手机里的网页项目",
        projectsInitialSummary: "正在读取当前随手网页的网页库摘要。",
        agentPanelTitle: "给 Agent 的操作说明",
        agentPanelHelp: "这段文本是给自动化 Agent 读取的。优先调用 HTTP 接口，不要依赖视觉点击。",
        aiPromptNeeds: "我的需求：",
        aiPromptInstruction: "访问这个链接查看说明",
        js: [
            "locale": "zh-CN",
            "missing": "未提供",
            "kindLabels": ["html": "网页项目", "nativeFileArchive": "原生文件包"],
            "statusLabels": ["stopped": "未开启", "starting": "开启中", "running": "已连接", "failed": "无法开启"],
            "unknown": "未知",
            "sessionRule": "保持到你停止，或 App 离开前台",
            "notJSON": "响应不是 JSON。",
            "requestFailedPrefix": "请求失败：HTTP ",
            "noEvents": "暂无操作记录。",
            "projectCountTemplate": "{count} 个",
            "projectsSummaryTemplate": "当前设备中有 {count} 个活跃项目。新上传的项目会出现在这里。",
            "projectsEmptySummary": "当前还没有网页项目。上传成功后会自动显示在这里。",
            "justUploaded": "刚上传",
            "defaultEntry": "默认入口",
            "notRecorded": "未记录",
            "entryCountTemplate": "{count} 个入口",
            "technicalDetails": "查看技术信息",
            "sourceFile": "来源文件",
            "projectType": "项目类型",
            "projectsEmpty": "当前还没有网页项目。",
            "readFailed": "读取失败",
            "copied": "已复制",
            "copyFailed": "复制失败",
            "initialNotice": "等待选择文件。",
            "fileEmpty": "尚未选择文件。支持 .html、.htm、.zip 和普通文件，单次上传建议不超过 200 MB。",
            "selectedFileTemplate": "已选择 {name}（{size}）。",
            "readyUploadTitle": "准备上传",
            "noFileTitle": "还没有选择文件",
            "noFileDetail": "请先选择一个 HTML、ZIP 或普通文件。",
            "uploadingButton": "上传中...",
            "uploadingTitle": "正在上传",
            "uploadSuccessTitle": "上传完成",
            "uploadSuccessTemplate": "{title} 已进入手机里的随手网页。",
            "uploadFailedTitle": "上传失败",
            "uploadButton": "上传到随手网页"
        ]
    )

    static let en = AgentImportWebCopy(
        pageTitle: "HTML Keep Agent Management",
        heroTitle: "HTML Keep Agent Management",
        heroSubtitle: "Let an Agent on your computer manage web projects on this device. Uploads, renames, and icon updates appear on the phone immediately.",
        loading: "Loading",
        languageLabel: "Language",
        connectionTitle: "Current Connection URL",
        copyAddress: "Copy URL",
        connectionHelp: "The device IP is assigned by the current Wi-Fi network; the port and path stay fixed. Agents that support local discovery can find this session through _htmlanywhere._tcp.",
        capabilitiesLabel: "Machine-readable capabilities:",
        aiCopyTitle: "Send This to AI",
        recommendedBadge: "Recommended",
        aiCopyHelp: "Copy this text to the AI / Agent on your computer, then add what you want to publish, rename, add an icon to, or update after “My request”.",
        copyForAI: "Copy for AI",
        uploadTitle: "Upload to Phone",
        uploadSubtitle: "Use this for a single HTML file, a complete web ZIP, or any regular file you want to preview on the phone.",
        titleLabel: "Project name (optional)",
        titlePlaceholder: "Example: Budget Dashboard",
        fileLabel: "Web File or ZIP",
        selectedFileEmpty: "No file selected. Supports .html, .htm, .zip, and regular files. Keep each upload under 200 MB.",
        openAfterUpload: "Open preview on the phone after upload",
        uploadButton: "Upload to HTML Keep",
        refreshButton: "Refresh Status",
        initialNotice: "Waiting for a file.",
        statusTitle: "Session Status",
        statusMetric: "Status",
        expiryMetric: "Connection",
        projectCountMetric: "Projects",
        lastRefreshMetric: "Last Refresh",
        recentEventsTitle: "Recent Events",
        projectsTitle: "Projects on the Phone",
        projectsInitialSummary: "Reading the current HTML Keep project summary.",
        agentPanelTitle: "Instructions for Agent",
        agentPanelHelp: "This text is for automation agents. Prefer the HTTP API instead of visual clicking.",
        aiPromptNeeds: "My request:",
        aiPromptInstruction: "Open this link and read the instructions",
        js: [
            "locale": "en-US",
            "missing": "Not provided",
            "kindLabels": ["html": "Web project", "nativeFileArchive": "Native file package"],
            "statusLabels": ["stopped": "Stopped", "starting": "Starting", "running": "Connected", "failed": "Failed"],
            "unknown": "Unknown",
            "sessionRule": "Until you stop it or the app leaves foreground",
            "notJSON": "Response is not JSON.",
            "requestFailedPrefix": "Request failed: HTTP ",
            "noEvents": "No recent events.",
            "projectCountTemplate": "{count}",
            "projectsSummaryTemplate": "This device has {count} active projects. New uploads appear here.",
            "projectsEmptySummary": "There are no web projects yet. Successful uploads will appear here automatically.",
            "justUploaded": "Just uploaded",
            "defaultEntry": "Default entry",
            "notRecorded": "Not recorded",
            "entryCountTemplate": "{count} entries",
            "technicalDetails": "Show technical details",
            "sourceFile": "Source file",
            "projectType": "Project type",
            "projectsEmpty": "There are no web projects yet.",
            "readFailed": "Read failed",
            "copied": "Copied",
            "copyFailed": "Copy failed",
            "initialNotice": "Waiting for a file.",
            "fileEmpty": "No file selected. Supports .html, .htm, .zip, and regular files. Keep each upload under 200 MB.",
            "selectedFileTemplate": "Selected {name} ({size}).",
            "readyUploadTitle": "Ready to upload",
            "noFileTitle": "No file selected",
            "noFileDetail": "Choose an HTML, ZIP, or regular file first.",
            "uploadingButton": "Uploading...",
            "uploadingTitle": "Uploading",
            "uploadSuccessTitle": "Upload complete",
            "uploadSuccessTemplate": "{title} has been added to HTML Keep on the phone.",
            "uploadFailedTitle": "Upload failed",
            "uploadButton": "Upload to HTML Keep"
        ]
    )
}

enum AgentImportSessionStatus: String {
    case stopped
    case starting
    case running
    case failed

    var title: String {
        switch self {
        case .stopped:
            return AppStrings.localized("未开启")
        case .starting:
            return AppStrings.localized("开启中")
        case .running:
            return AppStrings.localized("已开启")
        case .failed:
            return AppStrings.localized("无法开启")
        }
    }
}

enum AgentImportSessionStopReason: Equatable {
    case userInitiated
    case appLifecycle
    case remoteShutdown
    case serverUnavailable
    case restart
}

struct AgentImportSessionEvent: Identifiable, Hashable {
    let id = UUID()
    let createdAt: Date
    let title: String
    let detail: String
}

@MainActor
@Observable
final class AgentImportSessionController {
    private(set) var status: AgentImportSessionStatus = .stopped
    private(set) var urlString: String?
    private(set) var latestErrorMessage: String?
    private(set) var events: [AgentImportSessionEvent] = []
    private(set) var requiresManualRestart = false

    private var server: AgentImportHTTPServer?
    private var idleTimerDisabledForSession = false

    var isRunning: Bool {
        status == .running
    }

    func start(
        library: WebPageLibrary,
        onImport: @escaping @MainActor (WebPageImportResult) -> Void,
        onLibraryChanged: @escaping @MainActor (String) -> Void
    ) {
        stop(reason: .restart)
        requiresManualRestart = false
        status = .starting
        latestErrorMessage = nil

        let host = Self.localIPv4Address() ?? "127.0.0.1"
        var startError: Error?

        let candidate = AgentImportHTTPServer(port: agentImportDefaultPort) { [weak self, weak library] request in
            await MainActor.run {
                guard let self, let library else {
                    return AgentImportHTTPResponse.jsonError(
                        status: 503,
                        code: "session_unavailable",
                        message: "Session is no longer available."
                    )
                }
                return self.handle(
                    request,
                    library: library,
                    onImport: onImport,
                    onLibraryChanged: onLibraryChanged
                )
            }
        }
        candidate.onStop = { [weak self, weak candidate] in
            guard let candidate else { return }
            Task { @MainActor [weak self, weak candidate] in
                guard let candidate else { return }
                self?.handleServerDidStop(candidate)
            }
        }

        do {
            try candidate.start()
            server = candidate
            let url = "http://\(host):\(agentImportDefaultPort)/ai"
            status = .running
            urlString = url
            setIdleTimerDisabledForSession(true)
            appendEvent(
                title: AppStrings.localized("Agent 管理已开启"),
                detail: url
            )
            return
        } catch {
            startError = error
        }

        status = .failed
        latestErrorMessage = startError?.localizedDescription ?? AppStrings.localized("无法开启 Agent 管理。")
        setIdleTimerDisabledForSession(false)
        appendEvent(
            title: AppStrings.localized("无法开启 Agent 管理"),
            detail: latestErrorMessage ?? ""
        )
    }

    func stop(reason: AgentImportSessionStopReason = .userInitiated) {
        let previousStatus = status
        let activeServer = server
        server = nil
        activeServer?.stop()
        setIdleTimerDisabledForSession(false)
        urlString = nil

        if reason != .restart {
            requiresManualRestart = true
        }

        if previousStatus == .running || previousStatus == .starting {
            status = .stopped
            appendEvent(
                title: AppStrings.localized("Agent 管理已关闭"),
                detail: AppStrings.localized("局域网会话已经停止。")
            )
        }
    }

    private func handleServerDidStop(_ stoppedServer: AgentImportHTTPServer) {
        guard server === stoppedServer else { return }
        stop(reason: .serverUnavailable)
    }

    private func appendEvent(title: String, detail: String) {
        events.insert(
            AgentImportSessionEvent(createdAt: Date(), title: title, detail: detail),
            at: 0
        )
        if events.count > 8 {
            events.removeLast(events.count - 8)
        }
    }

    private func setIdleTimerDisabledForSession(_ isDisabled: Bool) {
        if isDisabled {
            guard !idleTimerDisabledForSession else { return }
            UIApplication.shared.isIdleTimerDisabled = true
            idleTimerDisabledForSession = true
        } else if idleTimerDisabledForSession {
            UIApplication.shared.isIdleTimerDisabled = false
            idleTimerDisabledForSession = false
        }
    }

    private func handle(
        _ request: AgentImportHTTPRequest,
        library: WebPageLibrary,
        onImport: @escaping @MainActor (WebPageImportResult) -> Void,
        onLibraryChanged: @escaping @MainActor (String) -> Void
    ) -> AgentImportHTTPResponse {
        guard status == .running else {
            return .jsonError(
                status: 410,
                code: "session_inactive",
                message: "The Agent import session is not active."
            )
        }

        guard let route = AgentImportRoute(request: request) else {
            return .jsonError(
                status: 404,
                code: "not_found",
                message: "Endpoint not found."
            )
        }

        switch (request.method, route.kind) {
        case ("GET", .home):
            return .html(sessionHTML(language: Self.webLanguage(for: request)))
        case ("GET", .capabilities):
            return .json(capabilitiesObject())
        case ("GET", .state):
            return .json(stateObject())
        case ("GET", .webpages):
            return .json([
                "webpages": library.pages.map(pageSummary)
            ])
        case ("POST", .importFile):
            return importFile(
                request,
                library: library,
                onImport: onImport,
                onLibraryChanged: onLibraryChanged
            )
        case ("POST", .renameProject(let projectID)):
            return renameProject(projectID, request: request, library: library, onLibraryChanged: onLibraryChanged)
        case ("POST", .setProjectIcon(let projectID)):
            return setProjectIcon(projectID, request: request, library: library, onLibraryChanged: onLibraryChanged)
        case ("POST", .shutdown):
            stop(reason: .remoteShutdown)
            return .json(["ok": true, "status": "stopped"])
        default:
            return .jsonError(
                status: 404,
                code: "not_found",
                message: "Endpoint not found."
            )
        }
    }

    private func importFile(
        _ request: AgentImportHTTPRequest,
        library: WebPageLibrary,
        onImport: @escaping @MainActor (WebPageImportResult) -> Void,
        onLibraryChanged: @escaping @MainActor (String) -> Void
    ) -> AgentImportHTTPResponse {
        guard !request.body.isEmpty else {
            return .jsonError(status: 400, code: "empty_body", message: "Upload body is empty.")
        }

        let fileName = Self.safeUploadFileName(
            request.queryValue("fileName") ?? request.header("x-htmlanywhere-filename")
        )
        let temporaryFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("HTMLKeep-AgentImport-\(UUID().uuidString)", isDirectory: true)
        let temporaryURL = temporaryFolderURL.appendingPathComponent(fileName, isDirectory: false)
        defer {
            try? FileManager.default.removeItem(at: temporaryFolderURL)
        }

        do {
            try FileManager.default.createDirectory(at: temporaryFolderURL, withIntermediateDirectories: true)
            try request.body.write(to: temporaryURL, options: [.atomic])
            let result = try library.importWebPage(from: temporaryURL)
            if let title = request.queryValue("title"),
               !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                _ = library.rename(result.page, to: title)
            }
            let importedPage = library.page(withID: result.page.id) ?? result.page
            let importedEntry = library.entry(withID: result.entry.id, in: importedPage)
                ?? library.defaultEntry(for: importedPage)
            let latestResult = WebPageImportResult(page: importedPage, entry: importedEntry)
            onLibraryChanged("syncReason.import")
            appendEvent(
                title: AppStrings.localized("收到网页"),
                detail: importedPage.title
            )
            if request.queryValue("open") == "1" || request.queryValue("open") == "true" {
                onImport(latestResult)
            }
            return .json([
                "ok": true,
                "project": pageSummary(importedPage),
                "entry": entrySummary(importedEntry),
                "next": [
                    "rename": "/ai/projects/\(importedPage.id.uuidString)/rename",
                    "icon": "/ai/projects/\(importedPage.id.uuidString)/icon"
                ]
            ])
        } catch {
            appendEvent(
                title: AppStrings.localized("导入失败"),
                detail: error.localizedDescription
            )
            return .jsonError(status: 400, code: "import_failed", message: error.localizedDescription)
        }
    }

    private func renameProject(
        _ projectID: WebPage.ID,
        request: AgentImportHTTPRequest,
        library: WebPageLibrary,
        onLibraryChanged: @escaping @MainActor (String) -> Void
    ) -> AgentImportHTTPResponse {
        guard let page = library.page(withID: projectID) else {
            return .jsonError(status: 404, code: "project_not_found", message: "Project not found.")
        }

        let title: String?
        if let queryTitle = request.queryValue("title") {
            title = queryTitle
        } else {
            title = try? JSONDecoder().decode(AgentImportRenameRequest.self, from: request.body).title
        }

        guard let title,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .jsonError(status: 400, code: "missing_title", message: "Missing title.")
        }

        guard library.rename(page, to: title),
              let renamedPage = library.page(withID: projectID) else {
            return .jsonError(status: 400, code: "rename_failed", message: "Project could not be renamed.")
        }

        onLibraryChanged("syncReason.rename")
        appendEvent(
            title: AppStrings.localized("已重命名项目"),
            detail: renamedPage.title
        )
        return .json(["ok": true, "project": pageSummary(renamedPage)])
    }

    private func setProjectIcon(
        _ projectID: WebPage.ID,
        request: AgentImportHTTPRequest,
        library: WebPageLibrary,
        onLibraryChanged: @escaping @MainActor (String) -> Void
    ) -> AgentImportHTTPResponse {
        guard let page = library.page(withID: projectID) else {
            return .jsonError(status: 404, code: "project_not_found", message: "Project not found.")
        }
        guard !request.body.isEmpty else {
            return .jsonError(status: 400, code: "empty_body", message: "Icon body is empty.")
        }
        guard library.setCustomProjectIcon(for: page, imageData: request.body),
              let updatedPage = library.page(withID: projectID) else {
            return .jsonError(status: 400, code: "icon_failed", message: AppStrings.localized("无法设置图标"))
        }

        onLibraryChanged("syncReason.projectIcon")
        appendEvent(
            title: AppStrings.localized("已设置图标"),
            detail: updatedPage.title
        )
        return .json(["ok": true, "project": pageSummary(updatedPage)])
    }

    private func stateObject() -> [String: Any] {
        [
            "status": status.rawValue,
            "url": urlString ?? NSNull(),
            "expiresAt": NSNull(),
            "lifetime": "foreground",
            "events": events.map { event in
                [
                    "createdAt": Self.iso8601String(event.createdAt),
                    "title": event.title,
                    "detail": event.detail
                ]
            }
        ]
    }

    private func capabilitiesObject() -> [String: Any] {
        [
            "name": "HTML Keep Agent Management",
            "version": 1,
            "basePath": "/ai",
            "maxUploadBytes": agentImportDocumentedImportByteLimit,
            "supportedUploads": ["html", "htm", "zip", "file"],
            "discovery": [
                "serviceType": "_htmlanywhere._tcp",
                "path": "/ai",
                "port": agentImportDefaultPort,
                "description": "Agents on the same local network may discover the active session with Bonjour/mDNS, then call the fixed /ai path on the resolved host and port."
            ],
            "auth": [
                "type": "manual-local-session",
                "description": "The user must manually start this foreground local network session in HTML Keep."
            ],
            "sessionLifetime": [
                "mode": "foreground",
                "expires": false,
                "description": "The session stays open while HTML Keep remains in the foreground and the user has not stopped it."
            ],
            "endpoints": [
                ["method": "GET", "path": "/ai/state"],
                ["method": "GET", "path": "/ai/webpages"],
                ["method": "POST", "path": "/ai/import?fileName=<name>&title=<optional>&open=1"],
                ["method": "POST", "path": "/ai/projects/<projectID>/rename"],
                ["method": "POST", "path": "/ai/projects/<projectID>/icon?fileName=<name>"],
                ["method": "POST", "path": "/ai/shutdown"]
            ]
        ]
    }

    private func pageSummary(_ page: WebPage) -> [String: Any] {
        [
            "id": page.id.uuidString,
            "title": page.title,
            "sourceFileName": page.sourceFileName ?? NSNull(),
            "kind": page.resolvedProjectKind.rawValue,
            "entryRelativePath": page.entryRelativePath,
            "entries": page.resolvedEntries.map(entrySummary)
        ]
    }

    private func entrySummary(_ entry: WebPageEntry) -> [String: Any] {
        [
            "id": entry.id.uuidString,
            "title": entry.title,
            "entryRelativePath": entry.entryRelativePath
        ]
    }

    private func sessionHTML(language: AgentImportWebLanguage) -> String {
        let url = urlString ?? ""
        let copy = language.copy
        let escapedURL = Self.htmlEscape(url)
        let escapedPageTitle = Self.htmlEscape(copy.pageTitle)
        let escapedAIPromptText = Self.htmlEscape(Self.aiPromptText(url: url, language: language))
        let escapedAgentInstructions = Self.htmlEscape(Self.agentInstructionsText(url: url, language: language))
        let languageLinks = Self.languageSwitchHTML(currentLanguage: language)
        let jsCopy = Self.jsonScriptObject(copy.js)
        return """
        <!doctype html>
        <html lang="\(language.htmlLang)">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(escapedPageTitle)</title>
          <style>
            :root {
              color-scheme: light;
              --bg: #f4f7fb;
              --surface: #ffffff;
              --surface-soft: #f8fbff;
              --text: #182230;
              --muted: #667085;
              --line: #d8e2ee;
              --accent: #1677ff;
              --accent-strong: #0759c7;
              --green: #148c6a;
              --green-soft: #e8f8f2;
              --red: #c2410c;
              --red-soft: #fff3ed;
            }
            * { box-sizing: border-box; }
            body { font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", "Hiragino Sans GB", sans-serif; margin: 0; line-height: 1.5; color: var(--text); background: var(--bg); }
            main { max-width: 1120px; margin: 0 auto; padding: 28px; }
            h1 { margin: 0 0 8px; font-size: 32px; line-height: 1.16; letter-spacing: 0; }
            h2 { margin: 0 0 12px; font-size: 18px; letter-spacing: 0; }
            h3 { margin: 0; font-size: 15px; }
            p { margin: 0 0 12px; }
            code, pre { background: #eef3fa; border-radius: 8px; padding: 2px 6px; }
            pre { padding: 12px; overflow: auto; }
            input, button { font: inherit; }
            label { display: block; margin: 12px 0 6px; font-size: 13px; font-weight: 700; color: #475467; }
            input { display: block; width: 100%; padding: 11px 12px; border: 1px solid #cfd8e3; border-radius: 8px; background: white; }
            input:focus { border-color: var(--accent); box-shadow: 0 0 0 3px rgba(22, 119, 255, 0.14); outline: none; }
            input[type="file"] { border-style: dashed; background: var(--surface-soft); }
            button { border: 0; border-radius: 8px; background: var(--accent); color: white; font-weight: 800; padding: 10px 14px; cursor: pointer; }
            button.secondary { background: #eef4fb; color: #24445f; }
            button:disabled { cursor: progress; opacity: 0.62; }
            .topbar { display: flex; justify-content: flex-end; margin-bottom: 14px; }
            .language-switch { display: inline-flex; align-items: center; gap: 4px; padding: 4px; border: 1px solid var(--line); border-radius: 999px; background: var(--surface); }
            .language-switch a { color: #344054; text-decoration: none; border-radius: 999px; padding: 6px 10px; font-size: 13px; font-weight: 800; }
            .language-switch a.active { color: white; background: var(--accent); }
            .hero { display: flex; align-items: flex-start; justify-content: space-between; gap: 18px; margin-bottom: 18px; }
            .hero p { max-width: 720px; }
            .card { background: var(--surface); border: 1px solid rgba(199, 211, 225, 0.86); border-radius: 8px; padding: 18px; box-shadow: 0 12px 34px rgba(39, 64, 107, 0.12); margin-bottom: 18px; }
            .grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 18px; }
            .summary-grid { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 10px; margin: 14px 0; }
            .metric { border: 1px solid var(--line); border-radius: 8px; padding: 12px; background: var(--surface-soft); min-height: 76px; }
            .metric-label { color: #667085; font-size: 12px; font-weight: 700; }
            .metric-value { margin-top: 6px; color: #1f2937; font-size: 16px; font-weight: 800; overflow-wrap: anywhere; }
            .toolbar { display: flex; align-items: center; justify-content: space-between; gap: 12px; margin-bottom: 12px; }
            .list { display: grid; gap: 10px; }
            .project, .event { border: 1px solid var(--line); border-radius: 8px; padding: 12px; background: var(--surface-soft); }
            .project-title { display: flex; align-items: center; justify-content: space-between; gap: 12px; margin-bottom: 8px; }
            .pill { display: inline-flex; align-items: center; border-radius: 999px; padding: 3px 8px; background: #e8f7ff; color: #00639b; font-size: 12px; font-weight: 800; white-space: nowrap; }
            .pill.success { background: var(--green-soft); color: var(--green); }
            .pill.error { background: var(--red-soft); color: var(--red); }
            .kv { display: grid; grid-template-columns: 110px minmax(0, 1fr); gap: 6px 10px; color: #475467; font-size: 13px; }
            .value { color: #1f2937; overflow-wrap: anywhere; }
            .muted { color: #667085; }
            .connection-row { display: flex; align-items: center; gap: 10px; margin: 10px 0; }
            .url-box { min-width: 0; flex: 1; display: block; padding: 12px; border: 1px solid var(--line); border-radius: 8px; background: var(--surface-soft); font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; overflow-wrap: anywhere; }
            .ai-copy-card { display: grid; grid-template-columns: minmax(0, 1fr) auto; gap: 18px; align-items: start; background: #f7fbff; border-color: #b9d4f5; }
            .ai-copy-title { display: flex; align-items: center; gap: 10px; margin-bottom: 8px; }
            .ai-copy-title .pill { background: var(--green-soft); color: var(--green); }
            .prompt-box { margin: 12px 0 0; padding: 14px; border: 1px solid #c7d8ec; border-radius: 8px; background: white; color: var(--text); font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; font-size: 14px; line-height: 1.55; white-space: pre-wrap; overflow-wrap: anywhere; }
            .upload-actions { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; margin: 12px 0; }
            .open-row { display: flex; align-items: center; gap: 8px; margin: 12px 0 0; color: #344054; font-size: 14px; }
            .open-row input { width: 16px; height: 16px; }
            .notice { min-height: 54px; border: 1px solid var(--line); border-radius: 8px; padding: 12px; color: #344054; background: var(--surface-soft); font-size: 13px; overflow-wrap: anywhere; }
            .notice strong { display: block; color: var(--text); margin-bottom: 4px; }
            .notice.success { border-color: rgba(20, 140, 106, 0.32); background: var(--green-soft); color: #1f513f; }
            .notice.error { border-color: rgba(194, 65, 12, 0.3); background: var(--red-soft); color: var(--red); }
            .notice.loading { border-color: rgba(22, 119, 255, 0.28); background: #eaf3ff; color: var(--accent-strong); }
            .empty { padding: 14px; border: 1px dashed #cfd8e3; border-radius: 8px; color: #667085; background: #fbfdff; }
            .project-meta { color: var(--muted); font-size: 13px; margin-bottom: 8px; overflow-wrap: anywhere; }
            details summary { cursor: pointer; }
            .agent-panel summary { font-size: 16px; font-weight: 900; color: var(--text); }
            .agent-instructions { white-space: pre-wrap; font-size: 13px; line-height: 1.55; }
            @media (max-width: 780px) {
              main { padding: 18px; }
              .hero, .connection-row, .ai-copy-card { display: block; }
              .url-box { margin: 8px 0 10px; }
              .ai-copy-card button { margin-top: 12px; width: 100%; }
              .grid, .summary-grid { grid-template-columns: 1fr; }
            }
          </style>
        </head>
        <body>
        <main>
          <div class="topbar" aria-label="\(Self.htmlEscape(copy.languageLabel))">
            <nav class="language-switch">
              \(languageLinks)
            </nav>
          </div>
          <section class="hero">
            <div>
              <h1>\(Self.htmlEscape(copy.heroTitle))</h1>
              <p class="muted">\(Self.htmlEscape(copy.heroSubtitle))</p>
            </div>
            <span id="session-status-pill" class="pill">\(Self.htmlEscape(copy.loading))</span>
          </section>

          <section class="card">
            <h2>\(Self.htmlEscape(copy.connectionTitle))</h2>
            <div class="connection-row">
              <code id="session-url" class="url-box">\(escapedURL)</code>
              <button id="copy-address" type="button">\(Self.htmlEscape(copy.copyAddress))</button>
            </div>
            <p class="muted">\(Self.htmlEscape(copy.connectionHelp)) \(Self.htmlEscape(copy.capabilitiesLabel)) <a href="/ai/capabilities.json">capabilities.json</a></p>
          </section>

          <section class="card ai-copy-card">
            <div>
              <div class="ai-copy-title">
                <h2>\(Self.htmlEscape(copy.aiCopyTitle))</h2>
                <span class="pill">\(Self.htmlEscape(copy.recommendedBadge))</span>
              </div>
              <p class="muted">\(Self.htmlEscape(copy.aiCopyHelp))</p>
              <pre id="ai-prompt" class="prompt-box">\(escapedAIPromptText)</pre>
            </div>
            <button id="copy-ai-prompt" type="button">\(Self.htmlEscape(copy.copyForAI))</button>
          </section>

          <section class="grid">
            <div class="card">
              <h2>\(Self.htmlEscape(copy.uploadTitle))</h2>
              <p class="muted">\(Self.htmlEscape(copy.uploadSubtitle))</p>
              <label for="title">\(Self.htmlEscape(copy.titleLabel))</label>
              <input id="title" type="text" placeholder="\(Self.htmlEscape(copy.titlePlaceholder))">
              <label for="file">\(Self.htmlEscape(copy.fileLabel))</label>
              <input id="file" type="file">
              <p id="selected-file" class="muted">\(Self.htmlEscape(copy.selectedFileEmpty))</p>
              <label class="open-row">
                <input id="open-after-upload" type="checkbox" checked>
                <span>\(Self.htmlEscape(copy.openAfterUpload))</span>
              </label>
              <div class="upload-actions">
                <button id="upload" type="button">\(Self.htmlEscape(copy.uploadButton))</button>
                <button id="refresh" type="button" class="secondary">\(Self.htmlEscape(copy.refreshButton))</button>
              </div>
              <div id="result" class="notice">\(Self.htmlEscape(copy.initialNotice))</div>
            </div>

            <div class="card">
              <div class="toolbar">
                <h2>\(Self.htmlEscape(copy.statusTitle))</h2>
              </div>
              <div class="summary-grid">
                <div class="metric">
                  <div class="metric-label">\(Self.htmlEscape(copy.statusMetric))</div>
                  <div id="session-status" class="metric-value">\(Self.htmlEscape(copy.loading))</div>
                </div>
                <div class="metric">
                  <div class="metric-label">\(Self.htmlEscape(copy.expiryMetric))</div>
                  <div id="session-expiry" class="metric-value">\(Self.htmlEscape(copy.loading))</div>
                </div>
                <div class="metric">
                  <div class="metric-label">\(Self.htmlEscape(copy.projectCountMetric))</div>
                  <div id="project-count" class="metric-value">\(Self.htmlEscape(copy.loading))</div>
                </div>
                <div class="metric">
                  <div class="metric-label">\(Self.htmlEscape(copy.lastRefreshMetric))</div>
                  <div id="last-refresh" class="metric-value">\(Self.htmlEscape(copy.loading))</div>
                </div>
              </div>
              <h3>\(Self.htmlEscape(copy.recentEventsTitle))</h3>
              <div id="events" class="list"></div>
            </div>
          </section>

          <section class="card">
            <div class="toolbar">
              <div>
                <h2>\(Self.htmlEscape(copy.projectsTitle))</h2>
                <p id="project-summary" class="muted">\(Self.htmlEscape(copy.projectsInitialSummary))</p>
              </div>
            </div>
            <div id="projects" class="list"></div>
          </section>

          <details class="card agent-panel">
            <summary>\(Self.htmlEscape(copy.agentPanelTitle))</summary>
            <p class="muted">\(Self.htmlEscape(copy.agentPanelHelp))</p>
            <pre id="agent-instructions" class="agent-instructions">\(escapedAgentInstructions)</pre>
          </details>
        </main>
        <script>
        const basePath = "/ai";
        const sessionURL = "\(escapedURL)";
        const copy = \(jsCopy);
        const $ = (id) => document.getElementById(id);
        const aiPromptText = $("ai-prompt").textContent;
        let highlightedProjectID = null;

        function escapeHTML(value) {
          return String(value ?? "")
            .replaceAll("&", "&amp;")
            .replaceAll("<", "&lt;")
            .replaceAll(">", "&gt;")
            .replaceAll('"', "&quot;");
        }

        function formatBytes(value) {
          if (!Number.isFinite(value)) return "";
          if (value < 1024 * 1024) return `${Math.max(1, Math.round(value / 1024))} KB`;
          return `${(value / 1024 / 1024).toFixed(1)} MB`;
        }

        function formatDate(value) {
          if (!value) return copy.missing;
          const date = new Date(value);
          if (Number.isNaN(date.getTime())) return value;
          return new Intl.DateTimeFormat(copy.locale, {
            month: "numeric",
            day: "numeric",
            hour: "2-digit",
            minute: "2-digit"
          }).format(date);
        }

        function kindLabel(kind) {
          return copy.kindLabels[kind] || kind || copy.unknown;
        }

        function statusLabel(status) {
          return copy.statusLabels[status] || status || copy.unknown;
        }

        function template(value, replacements) {
          return Object.entries(replacements).reduce(
            (result, [key, replacement]) => result.replaceAll(`{${key}}`, String(replacement)),
            value
          );
        }

        function setNotice(kind, html) {
          const result = $("result");
          result.className = `notice ${kind || ""}`.trim();
          result.innerHTML = html;
        }

        function updateStatusPill(status) {
          const pill = $("session-status-pill");
          pill.textContent = statusLabel(status);
          pill.className = "pill";
          if (status === "running") pill.classList.add("success");
          if (status === "failed" || status === "stopped") pill.classList.add("error");
        }

        async function requestJSON(path, options = {}) {
          const response = await fetch(`${basePath}${path}`, options);
          const text = await response.text();
          let payload = {};
          try {
            payload = text ? JSON.parse(text) : {};
          } catch {
            payload = { ok: false, error: { message: text || copy.notJSON } };
          }
          if (!response.ok) {
            throw new Error(payload.error?.message || `${copy.requestFailedPrefix}${response.status}`);
          }
          return payload;
        }

        function renderState(state) {
          $("session-status").textContent = statusLabel(state.status);
          $("session-expiry").textContent = copy.sessionRule;
          $("last-refresh").textContent = new Intl.DateTimeFormat(copy.locale, {
            hour: "2-digit",
            minute: "2-digit",
            second: "2-digit"
          }).format(new Date());
          updateStatusPill(state.status);
          const events = Array.isArray(state.events) ? state.events : [];
          $("events").innerHTML = events.length
            ? events.map((event) => `
                <div class="event">
                  <div class="project-title">
                    <h3>${escapeHTML(event.title)}</h3>
                    <span class="pill">${escapeHTML(formatDate(event.createdAt))}</span>
                  </div>
                  <div class="muted">${escapeHTML(event.detail || "")}</div>
                </div>
              `).join("")
            : `<div class="empty">${escapeHTML(copy.noEvents)}</div>`;
        }

        function renderProjects(webpages) {
          $("project-count").textContent = template(copy.projectCountTemplate, { count: webpages.length });
          $("project-summary").textContent = webpages.length
            ? template(copy.projectsSummaryTemplate, { count: webpages.length })
            : copy.projectsEmptySummary;
          $("projects").innerHTML = webpages.length
            ? webpages.map((project) => {
                const isNew = project.id === highlightedProjectID;
                const entryCount = Array.isArray(project.entries) ? project.entries.length : 0;
                return `
                  <article class="project">
                    <div class="project-title">
                      <h3>${escapeHTML(project.title)}</h3>
                      <span class="pill ${isNew ? "success" : ""}">${isNew ? escapeHTML(copy.justUploaded) : escapeHTML(kindLabel(project.kind))}</span>
                    </div>
                    <div class="project-meta">
                      ${escapeHTML(copy.defaultEntry)}: ${escapeHTML(project.entryRelativePath || copy.notRecorded)} · ${escapeHTML(template(copy.entryCountTemplate, { count: entryCount }))}
                    </div>
                    <details>
                      <summary class="muted">${escapeHTML(copy.technicalDetails)}</summary>
                      <div class="kv">
                        <div>Project ID</div><div class="value"><code>${escapeHTML(project.id)}</code></div>
                        <div>${escapeHTML(copy.sourceFile)}</div><div class="value">${escapeHTML(project.sourceFileName || copy.notRecorded)}</div>
                        <div>${escapeHTML(copy.projectType)}</div><div class="value">${escapeHTML(kindLabel(project.kind))}</div>
                      </div>
                    </details>
                  </article>
                `;
              }).join("")
            : `<div class="empty">${escapeHTML(copy.projectsEmpty)}</div>`;
        }

        async function refreshData() {
          $("refresh").disabled = true;
          try {
            const [state, webpages] = await Promise.all([
              requestJSON("/state"),
              requestJSON("/webpages")
            ]);
            renderState(state);
            renderProjects(Array.isArray(webpages.webpages) ? webpages.webpages : []);
          } catch (error) {
            $("session-status").textContent = copy.readFailed;
            updateStatusPill("failed");
            $("events").innerHTML = `<div class="empty">${escapeHTML(error.message)}</div>`;
          } finally {
            $("refresh").disabled = false;
          }
        }

        async function copyText(value) {
          if (navigator.clipboard?.writeText) {
            await navigator.clipboard.writeText(value);
            return;
          }
          const textarea = document.createElement("textarea");
          textarea.value = value;
          textarea.setAttribute("readonly", "");
          textarea.style.position = "fixed";
          textarea.style.opacity = "0";
          document.body.appendChild(textarea);
          textarea.select();
          document.execCommand("copy");
          textarea.remove();
        }

        $("copy-address").onclick = async () => {
          const button = $("copy-address");
          const original = button.textContent;
          try {
            await copyText(sessionURL);
            button.textContent = copy.copied;
          } catch {
            button.textContent = copy.copyFailed;
          }
          setTimeout(() => { button.textContent = original; }, 1400);
        };

        $("copy-ai-prompt").onclick = async () => {
          const button = $("copy-ai-prompt");
          const original = button.textContent;
          try {
            await copyText(aiPromptText);
            button.textContent = copy.copied;
          } catch {
            button.textContent = copy.copyFailed;
          }
          setTimeout(() => { button.textContent = original; }, 1400);
        };

        $("file").onchange = () => {
          const file = $("file").files[0];
          if (!file) {
            $("selected-file").textContent = copy.fileEmpty;
            setNotice("", escapeHTML(copy.initialNotice));
            return;
          }
          $("selected-file").textContent = template(copy.selectedFileTemplate, { name: file.name, size: formatBytes(file.size) });
          setNotice("", `<strong>${escapeHTML(copy.readyUploadTitle)}</strong>${escapeHTML(file.name)} · ${escapeHTML(formatBytes(file.size))}`);
        };

        $("upload").onclick = async () => {
          const file = $("file").files[0];
          if (!file) {
            setNotice("error", `<strong>${escapeHTML(copy.noFileTitle)}</strong>${escapeHTML(copy.noFileDetail)}`);
            return;
          }
          const title = $("title").value.trim();
          const query = new URLSearchParams({ fileName: file.name });
          if ($("open-after-upload").checked) query.set("open", "1");
          if (title) query.set("title", title);
          $("upload").disabled = true;
          $("upload").textContent = copy.uploadingButton;
          setNotice("loading", `<strong>${escapeHTML(copy.uploadingTitle)}</strong>${escapeHTML(file.name)} · ${escapeHTML(formatBytes(file.size))}`);
          try {
            const payload = await requestJSON(`/import?${query}`, {
              method: "POST",
              headers: { "Content-Type": "application/octet-stream" },
              body: file
            });
            highlightedProjectID = payload.project?.id || null;
            setNotice(
              "success",
              `<strong>${escapeHTML(copy.uploadSuccessTitle)}</strong>${escapeHTML(template(copy.uploadSuccessTemplate, { title: payload.project?.title || file.name }))}`
            );
            await refreshData();
          } catch (error) {
            setNotice("error", `<strong>${escapeHTML(copy.uploadFailedTitle)}</strong>${escapeHTML(error.message)}`);
          } finally {
            $("upload").disabled = false;
            $("upload").textContent = copy.uploadButton;
          }
        };

        $("refresh").onclick = refreshData;
        refreshData();
        setInterval(refreshData, 30000);
        </script>
        </body>
        </html>
        """
    }

    private static func webLanguage(for request: AgentImportHTTPRequest) -> AgentImportWebLanguage {
        AgentImportWebLanguage.resolve(
            queryValue: request.queryValue("lang"),
            acceptLanguage: request.header("accept-language")
        )
    }

    private static func languageSwitchHTML(currentLanguage: AgentImportWebLanguage) -> String {
        AgentImportWebLanguage.allCases.map { language in
            let activeClass = language == currentLanguage ? " active" : ""
            let currentAttribute = language == currentLanguage ? #" aria-current="page""# : ""
            return #"<a class="language-option\#(activeClass)" href="/ai?lang=\#(htmlEscape(language.rawValue))"\#(currentAttribute)>\#(htmlEscape(language.displayName))</a>"#
        }
        .joined(separator: "\n              ")
    }

    private static func jsonScriptObject(_ object: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    private static func aiPromptText(url: String, language: AgentImportWebLanguage) -> String {
        let copy = language.copy
        return "\(copy.aiPromptNeeds)\n\n\(copy.aiPromptInstruction)\n\(url)"
    }

    private static func agentInstructionsText(url: String, language: AgentImportWebLanguage) -> String {
        let baseURL = url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        switch language {
        case .zhHans:
        return """
        # 随手网页 Agent 管理协议 v1

        你是一个自动化 Agent，正在操作用户已经授权开启的随手网页本地局域网管理会话。
        不要把这个页面当作普通网页 UI 来点击。优先直接调用下面的 HTTP 接口。

        会话
        - Base URL: \(baseURL)
        - 鉴权模型：用户在 App 内手动开启当前前台局域网会话后，电脑 Agent 才能访问这个本地地址。
        - 稳定入口：固定端口 10231 和固定路径 /ai。手机数字 IP 由当前 Wi-Fi 路由器分配，可能变化；如果你具备本机命令执行能力，可优先用 Bonjour/mDNS 发现 _htmlanywhere._tcp 服务，解析到当前 host 与 port 后再访问 /ai。
        - 生命周期：这是前台临时会话，不设置固定倒计时。只要 App 还在前台、用户没有停止，它就会继续可用；用户手动锁屏、切到其他 App 或 App 进入后台后会话会关闭。
        - 重要：导入后不要立刻调用 shutdown。用户可能正在手机上预览，而你还需要继续重命名、设置图标或发布下一版。

        推荐工作流
        1. GET \(baseURL)/capabilities.json，读取 maxUploadBytes 和可用端点。
        2. 准备本地产物：.html、.htm、.zip 或其他普通文件。多文件网页优先打包成包含 HTML 入口和资源的 .zip。
        3. POST 原始文件字节到 /import。v1 不使用 multipart/form-data。
        4. 解析 JSON 响应。后续调用必须使用响应里的 project.id，不要猜项目 ID。
        5. 如果你知道更好的展示名称，POST /projects/<projectID>/rename。
        6. 如果你有或能生成合适的 bitmap 图标，POST /projects/<projectID>/icon。
        7. 用 GET /state 验证最近操作。需要当前项目列表时用 GET /webpages。
        8. 只有当用户明确要求结束会话，或整个工作流确实完成时，才调用 /shutdown。

        导入端点
        - 方法：POST
        - URL：\(baseURL)/import?fileName=<url-encoded-name>&title=<optional-url-encoded-title>&open=1
        - Body：原始文件字节
        - Content-Type: application/octet-stream
        - fileName：建议必填。它影响扩展名识别和默认来源名称。使用简单 basename，例如 index.html 或 demo.zip。
        - title：可选。它设置随手网页里的项目展示名，不会修改 HTML <title> 或源文件名。
        - open：可选。用户可能希望在手机上立刻预览时使用 open=1。
        - 大小限制：上传文件保持在 200 MB 以内。

        curl 导入示例
        curl -X POST "\(baseURL)/import?fileName=index.html&title=My%20Page&open=1" \\
          -H "Content-Type: application/octet-stream" \\
          --data-binary @index.html

        成功导入响应结构
        {
          "ok": true,
          "project": {
            "id": "<uuid>",
            "title": "<display title>",
            "kind": "html | nativeFileArchive",
            "entryRelativePath": "<relative entry path>",
            "entries": [...]
          },
          "entry": {
            "id": "<uuid>",
            "title": "<entry title>",
            "entryRelativePath": "<relative entry path>"
          },
          "next": {
            "rename": "/ai/projects/<uuid>/rename",
            "icon": "/ai/projects/<uuid>/icon"
          }
        }

        重命名端点
        - 方法：POST
        - URL：\(baseURL)/projects/<projectID>/rename
        - Content-Type: application/json
        - Body: { "title": "New Display Name" }

        curl 重命名示例
        curl -X POST "\(baseURL)/projects/<projectID>/rename" \\
          -H "Content-Type: application/json" \\
          --data '{"title":"New Display Name"}'

        图标端点
        - 方法：POST
        - URL：\(baseURL)/projects/<projectID>/icon?fileName=<icon-file-name>
        - Body：原始图片字节
        - Content-Type: image/png or image/jpeg
        - 尽量使用正方形 bitmap。随手网页会归一化项目图标。

        curl 图标上传示例
        curl -X POST "\(baseURL)/projects/<projectID>/icon?fileName=icon.png" \\
          -H "Content-Type: image/png" \\
          --data-binary @icon.png

        状态和发现
        - GET \(baseURL)/state 返回状态、URL、会话生命周期模式和最近事件。expiresAt 在当前版本固定为 null，表示没有倒计时过期。
        - GET \(baseURL)/webpages 返回当前活跃项目摘要。
        - GET \(baseURL)/capabilities.json 返回机器可读协议元数据。
        - 发现服务：当前会话会发布 Bonjour/mDNS service type _htmlanywhere._tcp，服务名为 HTML Keep。电脑 Agent 可以用系统 Bonjour、dns-sd、zeroconf 或 mDNS 库找到当前设备，再组合 http://<resolved-host>:<resolved-port>/ai。

        错误处理
        - 非 2xx 响应会尽量返回 JSON。
        - 错误结构：{ "ok": false, "error": { "code": "...", "message": "..." } }
        - 把 error.message 报告给用户，再判断是否重试。
        - 404 表示路径错误。请从当前会话 URL 重新读取 base URL。
        - 410 表示会话未开启或已关闭。请让用户重新开启 Agent 管理。
        - 413 表示上传过大。压缩、拆分或减少文件后再试。

        边界
        - 这是本地导入和项目元数据 API，不是 shell、文件浏览器、DOM inspector 或完整 MCP server。
        - 不要向手机请求任意文件系统路径。
        - 不要尝试通过这个会话删除项目或修改 App 设置。
        - 不要让手机抓取远程 URL。请在电脑侧准备产物字节并上传。
        """
        case .en:
        return """
        # HTML Keep Agent Management Protocol v1

        You are an automation Agent operating a local HTML Keep LAN import session that the user has already started and authorized.
        Do not treat this page as a normal web UI to click through. Prefer calling the HTTP API below directly.

        Session
        - Base URL: \(baseURL)
        - Authorization model: the user must manually start this foreground local-network session in HTML Keep before the computer Agent can access this local address.
        - Stable entry: fixed port 10231 and fixed path /ai. The phone's numeric IP is assigned by the current Wi-Fi router and may change. If you can run local commands, prefer Bonjour/mDNS discovery for the _htmlanywhere._tcp service, then access /ai on the resolved host and port.
        - Lifecycle: this is a temporary foreground session with no fixed countdown. It remains available while the App stays in the foreground and the user has not stopped it. The session closes if the user manually locks the device, switches to another app, or the App enters the background.
        - Important: do not call shutdown immediately after import. The user may be previewing on the phone while you still need to rename, set an icon, or publish another version.

        Recommended workflow
        1. GET \(baseURL)/capabilities.json and read maxUploadBytes plus available endpoints.
        2. Prepare the local artifact: .html, .htm, .zip, or another regular file. For multi-file websites, prefer a .zip that contains the HTML entry and assets.
        3. POST raw file bytes to /import. v1 does not use multipart/form-data.
        4. Parse the JSON response. Follow-up calls must use project.id from the response; do not guess the project ID.
        5. If you know a better display name, POST /projects/<projectID>/rename.
        6. If you have or can generate a suitable bitmap icon, POST /projects/<projectID>/icon.
        7. Use GET /state to verify recent operations. Use GET /webpages when you need the current project list.
        8. Call /shutdown only when the user explicitly asks to end the session, or when the whole workflow is truly complete.

        Import endpoint
        - Method: POST
        - URL: \(baseURL)/import?fileName=<url-encoded-name>&title=<optional-url-encoded-title>&open=1
        - Body: raw file bytes
        - Content-Type: application/octet-stream
        - fileName: recommended. It affects extension recognition and the default source name. Use a simple basename such as index.html or demo.zip.
        - title: optional. It sets the display name in HTML Keep, and does not modify the HTML <title> or source filename.
        - open: optional. Use open=1 when the user may want to preview on the phone immediately.
        - Size limit: keep each upload under 200 MB.

        curl import example
        curl -X POST "\(baseURL)/import?fileName=index.html&title=My%20Page&open=1" \\
          -H "Content-Type: application/octet-stream" \\
          --data-binary @index.html

        Successful import response shape
        {
          "ok": true,
          "project": {
            "id": "<uuid>",
            "title": "<display title>",
            "kind": "html | nativeFileArchive",
            "entryRelativePath": "<relative entry path>",
            "entries": [...]
          },
          "entry": {
            "id": "<uuid>",
            "title": "<entry title>",
            "entryRelativePath": "<relative entry path>"
          },
          "next": {
            "rename": "/ai/projects/<uuid>/rename",
            "icon": "/ai/projects/<uuid>/icon"
          }
        }

        Rename endpoint
        - Method: POST
        - URL: \(baseURL)/projects/<projectID>/rename
        - Content-Type: application/json
        - Body: { "title": "New Display Name" }

        curl rename example
        curl -X POST "\(baseURL)/projects/<projectID>/rename" \\
          -H "Content-Type: application/json" \\
          --data '{"title":"New Display Name"}'

        Icon endpoint
        - Method: POST
        - URL: \(baseURL)/projects/<projectID>/icon?fileName=<icon-file-name>
        - Body: raw image bytes
        - Content-Type: image/png or image/jpeg
        - Prefer a square bitmap. HTML Keep will normalize the project icon.

        curl icon upload example
        curl -X POST "\(baseURL)/projects/<projectID>/icon?fileName=icon.png" \\
          -H "Content-Type: image/png" \\
          --data-binary @icon.png

        State and discovery
        - GET \(baseURL)/state returns status, URL, lifetime mode, and recent events. In this version, expiresAt is always null because there is no countdown expiration.
        - GET \(baseURL)/webpages returns active project summaries.
        - GET \(baseURL)/capabilities.json returns machine-readable protocol metadata.
        - Discovery service: the active session publishes Bonjour/mDNS service type _htmlanywhere._tcp with service name HTML Keep. A computer Agent can use system Bonjour, dns-sd, zeroconf, or an mDNS library to find the device, then compose http://<resolved-host>:<resolved-port>/ai.

        Error handling
        - Non-2xx responses try to return JSON.
        - Error shape: { "ok": false, "error": { "code": "...", "message": "..." } }
        - Report error.message to the user, then decide whether to retry.
        - 404 means the path is wrong. Re-read the base URL from the current session URL.
        - 410 means the session is inactive or closed. Ask the user to start Agent Management again.
        - 413 means the upload is too large. Compress, split, or reduce the file before retrying.

        Boundaries
        - This is a local import and project metadata API, not a shell, file browser, DOM inspector, or full MCP server.
        - Do not request arbitrary filesystem paths from the phone.
        - Do not try to delete projects or change App settings through this session.
        - Do not ask the phone to fetch remote URLs. Prepare artifact bytes on the computer side and upload them.
        """
        }
    }

    private static func safeUploadFileName(_ rawValue: String?) -> String {
        let fallback = "agent-upload.html"
        guard let rawValue, !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fallback
        }
        let fileName = URL(fileURLWithPath: rawValue).lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fileName.isEmpty else {
            return fallback
        }
        return fileName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\0", with: "-")
    }

    private static func localIPv4Address() -> String? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0,
              let firstInterface = interfaces else {
            return nil
        }
        defer {
            freeifaddrs(interfaces)
        }

        var candidates: [(name: String, address: String)] = []
        var pointer: UnsafeMutablePointer<ifaddrs>? = firstInterface
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            guard let address = current.pointee.ifa_addr,
                  address.pointee.sa_family == sa_family_t(AF_INET) else {
                continue
            }
            let flags = Int32(current.pointee.ifa_flags)
            guard flags & IFF_UP == IFF_UP,
                  flags & IFF_RUNNING == IFF_RUNNING,
                  flags & IFF_LOOPBACK == 0 else {
                continue
            }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else { continue }
            let interfaceName = String(cString: current.pointee.ifa_name)
            candidates.append((name: interfaceName, address: String(cString: hostname)))
        }

        return candidates.first(where: { $0.name.hasPrefix("en") })?.address
            ?? candidates.first?.address
    }

    private static func iso8601String(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func htmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

struct AgentImportSessionView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppPreferenceKeys.agentImportGuideCompleted) private var hasCompletedAgentImportGuide = false

    let session: AgentImportSessionController
    let library: WebPageLibrary
    let canStartSession: Bool
    let onImport: (WebPageImportResult) -> Void
    let onLibraryChanged: (String) -> Void
    let onOpenProEntitlement: () -> Void

    var body: some View {
        ZStack {
            AppPageBackground()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if session.isRunning {
                            activeConnectionContent
                        } else if shouldShowAgentGuide {
                            agentShowcaseContent
                        } else {
                            agentStartingContent
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                }
                .scrollContentBackground(.hidden)

                if !session.isRunning && shouldShowAgentGuide {
                    startDock
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background else { return }
            session.stop(reason: .appLifecycle)
        }
        .task(id: automaticStartIdentity) {
            startAutomaticallyIfNeeded()
        }
    }

    private var shouldShowAgentGuide: Bool {
        !session.isRunning &&
            (!canStartSession ||
                !hasCompletedAgentImportGuide ||
                session.status == .failed ||
                session.requiresManualRestart)
    }

    private var automaticStartIdentity: String {
        [
            canStartSession ? "can-start" : "locked",
            hasCompletedAgentImportGuide ? "guide-completed" : "guide-needed",
            session.requiresManualRestart ? "manual-restart" : "auto-allowed",
            session.status.rawValue
        ].joined(separator: ":")
    }

    private var agentShowcaseContent: some View {
        AgentManagementPoster()
    }

    private var agentStartingContent: some View {
        AppSurfaceCard(isProminent: true) {
            HStack(spacing: 12) {
                ProgressView()
                    .tint(AppTheme.deepWater)

                Text(AppStrings.localized("开启中"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppTheme.contentPrimary)

                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private var activeConnectionContent: some View {
        AppSurfaceCard(isProminent: true) {
            SectionHeader(AppStrings.localized("同一 Wi-Fi 网络"), systemImage: "wifi")

            Text(sameNetworkMessage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.contentPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        if let urlString = session.urlString {
            AppSurfaceCard(isProminent: true) {
                SectionHeader(AppStrings.localized("复制本机地址给 Agent"), systemImage: "doc.on.doc")

                AgentLocalAddressField(urlString: urlString)

                AgentAddressInstructionList()

                AgentCopyURLButton(urlString: urlString)
            }
        }

        AppSurfaceCard(isProminent: true) {
            SectionHeader(keepDeviceForegroundTitle, systemImage: "iphone")

            VStack(spacing: 10) {
                AgentForegroundReminderRow(textKey: "不要锁屏")
                AgentForegroundReminderRow(textKey: "不要切换到其他 App")
                AgentForegroundReminderRow(textKey: "不要关闭这个 App")
            }

            if let latestErrorMessage = session.latestErrorMessage {
                Text(latestErrorMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }

        Button(role: .destructive) {
            session.stop(reason: .userInitiated)
        } label: {
            Text(AppStrings.localized("关闭 Agent 连接"))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(AppTheme.coral)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
    }

    private var sameNetworkMessage: String {
        String(
            format: AppStrings.localized("确保%@和电脑在同一个 Wi-Fi 网络下"),
            localDeviceName
        )
    }

    private var keepDeviceForegroundTitle: String {
        String(
            format: AppStrings.localized("保持%@在前台"),
            localDeviceName
        )
    }

    private var localDeviceName: String {
        UIDevice.current.userInterfaceIdiom == .pad
            ? AppStrings.localized("iPad")
            : AppStrings.localized("手机")
    }

    private var startDock: some View {
        BottomActionDock {
            VStack(spacing: 10) {
                if let latestErrorMessage = session.latestErrorMessage {
                    Text(latestErrorMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }

                AppActionButton(
                    startButtonTitle,
                    coloredIconAssetName: startButtonIconAssetName,
                    scene: startButtonScene,
                    size: .large
                ) {
                    handleStartButtonTap()
                }
                .disabled(session.status == .starting)
            }
        }
    }

    private var startButtonIconAssetName: String? {
        canStartSession ? "IconAgentManagement" : nil
    }

    private var startButtonScene: AppActionButtonScene {
        canStartSession ? .neutralDark : .premiumGold
    }

    private var startButtonTitle: String {
        if session.status == .starting {
            return AppStrings.localized("开启中")
        }
        if !canStartSession {
            return AppStrings.localized("开通 Pro 权益可开启 Agent")
        }
        if !hasCompletedAgentImportGuide {
            return AppStrings.localized("立即开启 Agent")
        }
        return AppStrings.localized("开启 Agent 连接")
    }

    private func handleStartButtonTap() {
        guard session.status != .starting else { return }
        guard canStartSession else {
            onOpenProEntitlement()
            return
        }
        hasCompletedAgentImportGuide = true
        startSession()
    }

    private func startAutomaticallyIfNeeded() {
        guard canStartSession,
              hasCompletedAgentImportGuide,
              !session.requiresManualRestart,
              session.status == .stopped else {
            return
        }
        startSession()
    }

    private func startSession() {
        session.start(
            library: library,
            onImport: onImport,
            onLibraryChanged: onLibraryChanged
        )
    }
}

private struct AgentCopyURLButton: View {
    let urlString: String

    @State private var isCopied = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        AppActionButton(
            isCopied ? AppStrings.localized("已复制") : AppStrings.localized("复制"),
            coloredIconAssetName: isCopied ? "IconDocument" : nil,
            scene: .sky,
            size: .large
        ) {
            UIPasteboard.general.string = urlString
            showCopiedFeedback()
        }
        .onDisappear {
            resetTask?.cancel()
        }
    }

    private func showCopiedFeedback() {
        resetTask?.cancel()
        withAnimation(.snappy(duration: 0.16)) {
            isCopied = true
        }

        resetTask = Task {
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.snappy(duration: 0.16)) {
                    isCopied = false
                }
            }
        }
    }
}

private struct AgentLocalAddressField: View {
    let urlString: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(urlString)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppTheme.textSecondary)
                .textSelection(.enabled)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surfaceInset.opacity(0.9), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.surfaceBorder, lineWidth: 1)
        }
    }
}

private struct AgentAddressInstructionList: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AgentAddressInstructionRow(textKey: "把地址直接发给 Agent", icon: .coloredAsset("IconAgentManagement"))
            AgentAddressInstructionRow(textKey: "或自己在电脑中打开查看", icon: .system("desktopcomputer"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AgentAddressInstructionRow: View {
    enum Icon {
        case coloredAsset(String)
        case system(String)
    }

    let textKey: String
    let icon: Icon

    var body: some View {
        HStack(spacing: 8) {
            switch icon {
            case .coloredAsset(let assetName):
                AppColoredIcon(assetName: assetName, size: 20)
            case .system(let systemName):
                Image(systemName: systemName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary.opacity(0.72))
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
            }

            Text(AppStrings.localized(textKey))
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct AgentManagementPoster: View {
    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 14) {
                VStack(spacing: 2) {
                    Text(AppStrings.localized("让 Agents 管理"))
                    Text(AppStrings.localized("你的网页库"))
                }
                .font(.system(size: 34, weight: .black))
                .foregroundStyle(AppTheme.contentPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: 420)

                AgentPosterCapabilityGrid()
            }

            AgentPosterCanvas()
                .frame(height: 390)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity)
    }
}

private struct AgentForegroundReminderRow: View {
    let textKey: String

    var body: some View {
        HStack(spacing: 10) {
            AppColoredIcon(assetName: "IconFlag0Red", size: 22)

            Text(AppStrings.localized(textKey))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AppTheme.contentPrimary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(AppTheme.surfaceInset.opacity(0.78), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct AgentPosterCanvas: View {
    private let agents: [AgentShowcaseItem] = [
        AgentShowcaseItem(nameKey: "Codex", icon: .asset("AgentCodex")),
        AgentShowcaseItem(nameKey: "Claude Code", icon: .asset("AgentClaudeCode")),
        AgentShowcaseItem(nameKey: "OpenClaw", icon: .asset("AgentOpenClaw")),
        AgentShowcaseItem(nameKey: "Hermes", icon: .asset("AgentHermes")),
        AgentShowcaseItem(nameKey: "各种 Agent", icon: .asset("IconAgentManagement"))
    ]

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let phoneWidth = min(max(size.width * 0.36, 136), 190)
            let phoneHeight = phoneWidth * 1.42
            let nodeWidth = min(max(size.width * 0.23, 78), 92)
            let nodeHeight = nodeWidth + 26
            let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
            let positions = [
                CGPoint(x: size.width * 0.1, y: size.height * 0.18),
                CGPoint(x: size.width * 0.9, y: size.height * 0.18),
                CGPoint(x: size.width * 0.1, y: size.height * 0.48),
                CGPoint(x: size.width * 0.9, y: size.height * 0.48),
                CGPoint(x: size.width * 0.5, y: size.height * 0.82)
            ]

            ZStack {
                AgentPosterConnections(points: positions, center: center)

                AgentPosterPhone()
                    .frame(width: phoneWidth, height: phoneHeight)
                    .position(center)

                ForEach(Array(agents.enumerated()), id: \.element.id) { index, agent in
                    AgentPosterNode(agent: agent)
                        .frame(width: nodeWidth, height: nodeHeight)
                        .position(positions[index])
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(AppStrings.localized("Agent 可以从电脑连接到 HTML Keep，并管理手机里的网页库。"))
    }
}

private struct AgentPosterConnections: View {
    let points: [CGPoint]
    let center: CGPoint

    var body: some View {
        Canvas { context, _ in
            for point in points {
                var path = Path()
                path.move(to: point)
                let controlA = CGPoint(
                    x: point.x + (center.x - point.x) * 0.36,
                    y: point.y
                )
                let controlB = CGPoint(
                    x: point.x + (center.x - point.x) * 0.7,
                    y: center.y
                )
                path.addCurve(to: center, control1: controlA, control2: controlB)
                context.stroke(
                    path,
                    with: .linearGradient(
                        Gradient(colors: [
                            AppTheme.aiPurple.opacity(0.62),
                            AppTheme.mint.opacity(0.72)
                        ]),
                        startPoint: point,
                        endPoint: center
                    ),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [7, 7])
                )
            }
        }
        .accessibilityHidden(true)
    }
}

private struct AgentPosterPhone: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(AppTheme.deepWater)
                .shadow(color: AppTheme.deepWater.opacity(0.24), radius: 18, x: 0, y: 12)

            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .fill(AppTheme.surfaceStrong)
                .padding(8)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(AppStrings.localized("app.displayName"))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AppTheme.contentAccent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(AppStrings.localized("网页库"))
                            .font(.system(size: 18, weight: .black))
                            .foregroundStyle(AppTheme.contentPrimary)
                    }
                    Spacer()
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppTheme.aiPurple)
                }

                VStack(spacing: 7) {
                    AgentPosterProjectRow(color: AppTheme.sky, titleKey: "网页", detailKey: "完成")
                    AgentPosterProjectRow(color: AppTheme.leaf, titleKey: "名称", detailKey: "完成")
                    AgentPosterProjectRow(color: AppTheme.gold, titleKey: "图标", detailKey: "完成")
                }

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    Circle()
                        .fill(AppTheme.leaf)
                        .frame(width: 8, height: 8)
                    Text(AppStrings.localized("管理中"))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppTheme.contentPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(AppTheme.surfaceInset, in: Capsule())
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
    }
}

private struct AgentPosterProjectRow: View {
    let color: Color
    let titleKey: String
    let detailKey: String

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(color.opacity(0.88))
                .frame(width: 26, height: 26)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(AppStrings.localized(titleKey))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppTheme.contentPrimary)
                Text(AppStrings.localized(detailKey))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(8)
        .background(AppTheme.surfaceInset.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct AgentPosterNode: View {
    let agent: AgentShowcaseItem

    var body: some View {
        VStack(spacing: 6) {
            AgentPosterIcon(icon: agent.icon)
                .padding(10)
                .frame(width: 62, height: 62)
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(hex: 0xF8FAFF))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.62), lineWidth: 1)
                        }
                        .shadow(color: Color.black.opacity(0.22), radius: 15, x: 0, y: 9)
                        .shadow(color: AppTheme.aiPurple.opacity(0.2), radius: 16, x: 0, y: 0)
                }

            Text(AppStrings.localized(agent.nameKey))
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(AppTheme.contentPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .shadow(color: Color.black.opacity(0.18), radius: 4, x: 0, y: 2)
        }
    }
}

private struct AgentPosterIcon: View {
    let icon: AgentShowcaseItem.Icon

    var body: some View {
        switch icon {
        case .asset(let assetName):
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct AgentPosterCapabilityGrid: View {
    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            AgentPosterCapability(titleKey: "批量发布", detailKey: "HTML / ZIP")
            AgentPosterCapability(titleKey: "智能命名", detailKey: "项目标题")
            AgentPosterCapability(titleKey: "图标维护", detailKey: "自动更新")
        }
    }
}

private struct AgentPosterCapability: View {
    let titleKey: String
    let detailKey: String

    var body: some View {
        VStack(spacing: 3) {
            Text(AppStrings.localized(titleKey))
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(AppTheme.contentPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
            Text(AppStrings.localized(detailKey))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(AppTheme.surfaceInset.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct AgentShowcaseItem: Identifiable {
    enum Icon {
        case asset(String)
    }

    let nameKey: String
    let icon: Icon

    var id: String { nameKey }
}

private struct AgentImportRenameRequest: Decodable {
    let title: String
}

private enum AgentImportRouteKind {
    case home
    case capabilities
    case state
    case webpages
    case importFile
    case renameProject(WebPage.ID)
    case setProjectIcon(WebPage.ID)
    case shutdown
}

private struct AgentImportRoute {
    let kind: AgentImportRouteKind

    init?(request: AgentImportHTTPRequest) {
        let components = request.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        guard components.first == "ai" else {
            return nil
        }

        let tail = Array(components.dropFirst())
        if tail.isEmpty {
            kind = .home
            return
        }
        if tail == ["capabilities.json"] {
            kind = .capabilities
            return
        }
        if tail == ["state"] {
            kind = .state
            return
        }
        if tail == ["webpages"] {
            kind = .webpages
            return
        }
        if tail == ["import"] {
            kind = .importFile
            return
        }
        if tail == ["shutdown"] {
            kind = .shutdown
            return
        }
        if tail.count == 3,
           tail[0] == "projects",
           let projectID = UUID(uuidString: tail[1]) {
            switch tail[2] {
            case "rename":
                kind = .renameProject(projectID)
                return
            case "icon":
                kind = .setProjectIcon(projectID)
                return
            default:
                return nil
            }
        }
        return nil
    }
}

private struct AgentImportHTTPRequest {
    let method: String
    let path: String
    let query: [String: String]
    let headers: [String: String]
    let body: Data

    func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }

    func queryValue(_ name: String) -> String? {
        query[name]
    }
}

private struct AgentImportHTTPResponse {
    let status: Int
    let contentType: String
    let body: Data

    static func json(_ object: [String: Any], status: Int = 200) -> AgentImportHTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]))
            ?? Data(#"{"ok":false}"#.utf8)
        return AgentImportHTTPResponse(status: status, contentType: "application/json; charset=utf-8", body: data)
    }

    static func jsonError(status: Int, code: String, message: String) -> AgentImportHTTPResponse {
        json([
            "ok": false,
            "error": [
                "code": code,
                "message": message
            ]
        ], status: status)
    }

    static func html(_ html: String) -> AgentImportHTTPResponse {
        AgentImportHTTPResponse(
            status: 200,
            contentType: "text/html; charset=utf-8",
            body: Data(html.utf8)
        )
    }

    func httpData() -> Data {
        let header = [
            "HTTP/1.1 \(status) \(Self.reasonPhrase(for: status))",
            "Content-Type: \(contentType)",
            "Content-Length: \(body.count)",
            "Cache-Control: no-store",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")
        var data = Data(header.utf8)
        data.append(body)
        return data
    }

    private static func reasonPhrase(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 202: return "Accepted"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 410: return "Gone"
        case 413: return "Payload Too Large"
        case 503: return "Service Unavailable"
        default: return "OK"
        }
    }
}

private final class AgentImportHTTPServer {
    typealias Handler = (AgentImportHTTPRequest) async -> AgentImportHTTPResponse

    private let port: UInt16
    private let handler: Handler
    private let queue = DispatchQueue(
        label: "\(Bundle.main.bundleIdentifier ?? "com.htmlkeep.community").agent-import-http"
    )
    private var listener: NWListener?
    private var hasReportedStop = false

    var onStop: (() -> Void)?

    init(port: UInt16, handler: @escaping Handler) {
        self.port = port
        self.handler = handler
    }

    func start() throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw AgentImportHTTPServerError.invalidPort
        }
        let listener = try NWListener(using: parameters, on: endpointPort)
        listener.service = NWListener.Service(
            name: "HTML Keep",
            type: "_htmlanywhere._tcp"
        )
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed(_), .cancelled:
                self?.reportStopIfNeeded()
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func reportStopIfNeeded() {
        guard !hasReportedStop else { return }
        hasReportedStop = true
        onStop?()
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            var nextBuffer = buffer
            if let data {
                nextBuffer.append(data)
            }

            if nextBuffer.count > agentImportMaximumRequestByteCount {
                send(
                    .jsonError(
                        status: 413,
                        code: "payload_too_large",
                        message: "Request is too large."
                    ),
                    on: connection
                )
                return
            }

            do {
                if let request = try Self.parseRequest(from: nextBuffer) {
                    Task {
                        let response = await self.handler(request)
                        self.send(response, on: connection)
                    }
                    return
                }
            } catch {
                send(
                    .jsonError(status: 400, code: "bad_request", message: error.localizedDescription),
                    on: connection
                )
                return
            }

            if isComplete || error != nil {
                connection.cancel()
                return
            }

            receive(on: connection, buffer: nextBuffer)
        }
    }

    private func send(_ response: AgentImportHTTPResponse, on connection: NWConnection) {
        connection.send(content: response.httpData(), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func parseRequest(from data: Data) throws -> AgentImportHTTPRequest? {
        let delimiter = Data([13, 10, 13, 10])
        guard let headerRange = data.range(of: delimiter) else {
            return nil
        }

        let headerData = data.subdata(in: data.startIndex..<headerRange.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            throw AgentImportHTTPServerError.invalidHeader
        }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            throw AgentImportHTTPServerError.invalidHeader
        }
        let requestParts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard requestParts.count >= 2 else {
            throw AgentImportHTTPServerError.invalidHeader
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            headers[name] = value
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        guard contentLength <= agentImportMaximumRequestByteCount else {
            throw AgentImportHTTPServerError.payloadTooLarge
        }
        let bodyStart = headerRange.upperBound
        guard data.count >= bodyStart + contentLength else {
            return nil
        }

        let target = requestParts[1]
        let pathAndQuery = Self.splitPathAndQuery(target)
        let body = data.subdata(in: bodyStart..<(bodyStart + contentLength))
        return AgentImportHTTPRequest(
            method: requestParts[0].uppercased(),
            path: pathAndQuery.path,
            query: Self.parseQuery(pathAndQuery.query),
            headers: headers,
            body: body
        )
    }

    private static func splitPathAndQuery(_ value: String) -> (path: String, query: String?) {
        let pathAndQuery: String
        if let url = URL(string: value), let host = url.host, !host.isEmpty {
            pathAndQuery = url.path + (url.query.map { "?\($0)" } ?? "")
        } else {
            pathAndQuery = value
        }

        guard let separator = pathAndQuery.firstIndex(of: "?") else {
            return (pathAndQuery.removingPercentEncoding ?? pathAndQuery, nil)
        }
        let path = String(pathAndQuery[..<separator])
        let query = String(pathAndQuery[pathAndQuery.index(after: separator)...])
        return (path.removingPercentEncoding ?? path, query)
    }

    private static func parseQuery(_ query: String?) -> [String: String] {
        guard let query, !query.isEmpty else { return [:] }
        var result: [String: String] = [:]
        for pair in query.split(separator: "&", omittingEmptySubsequences: false) {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = decodeQueryComponent(String(parts.first ?? ""))
            let value = parts.count > 1 ? decodeQueryComponent(String(parts[1])) : ""
            result[key] = value
        }
        return result
    }

    private static func decodeQueryComponent(_ value: String) -> String {
        value.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? value
    }
}

private enum AgentImportHTTPServerError: LocalizedError {
    case invalidPort
    case invalidHeader
    case payloadTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidPort:
            return "Invalid port."
        case .invalidHeader:
            return "Invalid HTTP header."
        case .payloadTooLarge:
            return "Request is too large."
        }
    }
}
