import CryptoKit
import Foundation
import UIKit
import UniformTypeIdentifiers
import WidgetKit

private let webPageMaximumImportedFileByteCount: Int64 = 200_000_000
private let webPageMaximumSnapshotFolderByteCount: Int64 = 200_000_000
private let opportunisticFullSearchIndexBuildDelayNanoseconds: UInt64 = 3_000_000_000

private func formattedWebPageByteCount(_ byteCount: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
}

struct WebPage: Identifiable, Codable, Hashable {
    typealias ID = UUID

    let id: ID
    var title: String
    var sourceDescription: String
    var sourceFileName: String?
    var folderName: String
    var entryRelativePath: String
    var contentSHA256: String?
    var createdAt: Date
    var lastOpenedAt: Date
    var updatedAt: Date? = nil
    var lastLoadStatus: WebPageLoadStatus
    var safeAreaTopColor: String?
    var safeAreaBottomColor: String?
    var entries: [WebPageEntry]? = nil
    var defaultEntryID: WebPageEntry.ID? = nil
    var projectIcon: WebPageProjectIcon? = nil
    var projectKind: WebPageProjectKind? = nil
    var singleFileFormat: WebPageSingleFileFormat? = nil

    var entryFileName: String {
        URL(fileURLWithPath: entryRelativePath).lastPathComponent
    }

    var resolvedProjectKind: WebPageProjectKind {
        if let projectKind {
            return projectKind
        }
        if singleFileFormat != nil {
            return .singleFile
        }
        if resolvedEntries.contains(where: { $0.source == .nativeFileIndex || $0.source == .bundledArchiveIndex }) {
            return .nativeFileArchive
        }
        return .html
    }

    var opensInNativeFileViewer: Bool {
        resolvedProjectKind == .nativeFileArchive
    }

    var opensInSingleFilePreview: Bool {
        resolvedProjectKind == .singleFile && singleFileFormat != .html
    }

    var resolvedEntries: [WebPageEntry] {
        if let entries, !entries.isEmpty {
            return entries
        }

        return [
            WebPageEntry(
                id: id,
                title: title,
                entryRelativePath: entryRelativePath,
                lastOpenedAt: lastOpenedAt,
                lastLoadStatus: lastLoadStatus,
                safeAreaTopColor: safeAreaTopColor,
                safeAreaBottomColor: safeAreaBottomColor
            )
        ]
    }
}

enum WebPageProjectIconSource: String, Codable, Hashable {
    case favicon
    case image
    case custom
}

enum WebPageProjectKind: String, Codable, Hashable {
    case html
    case singleFile
    case nativeFileArchive
}

enum WebPageSingleFileFormat: String, Codable, Hashable {
    case html
    case markdown
    case image
    case video
    case audio
    case pdf
    case text
    case document
    case file

    static func format(for url: URL, typeIdentifier: String? = nil) -> WebPageSingleFileFormat {
        if isHTMLExtension(url.pathExtension) {
            return .html
        }
        if isMarkdownExtension(url.pathExtension) {
            return .markdown
        }

        let type = typeIdentifier.flatMap(UTType.init) ?? UTType(filenameExtension: url.pathExtension)
        guard let type else { return .file }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) { return .video }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .text) || type.conforms(to: .json) || type.conforms(to: .xml) || isKnownTextExtension(url.pathExtension) {
            return .text
        }
        if type.conforms(to: .content) {
            return .document
        }
        return .file
    }

    static func isHTMLExtension(_ fileExtension: String) -> Bool {
        let ext = fileExtension.lowercased()
        return ext == "html" || ext == "htm"
    }

    static func isMarkdownExtension(_ fileExtension: String) -> Bool {
        let ext = fileExtension.lowercased()
        return ext == "md" || ext == "markdown"
    }

    private static func isKnownTextExtension(_ fileExtension: String) -> Bool {
        [
            "txt", "text", "lrc", "csv", "tsv", "log",
            "json", "xml", "yaml", "yml", "ini", "conf", "cfg",
            "srt", "ass", "ssa", "vtt", "css", "js", "mjs", "ts"
        ].contains(fileExtension.lowercased())
    }
}

struct WebPageProjectIcon: Codable, Hashable {
    var source: WebPageProjectIconSource
    var fileName: String
    var updatedAt: Date
}

struct WebPageEntry: Identifiable, Codable, Hashable {
    typealias ID = UUID

    var id: ID
    var title: String
    var entryRelativePath: String
    var source: WebPageEntrySource? = nil
    var lastOpenedAt: Date
    var lastLoadStatus: WebPageLoadStatus
    var safeAreaTopColor: String?
    var safeAreaBottomColor: String?

    var entryFileName: String {
        URL(fileURLWithPath: entryRelativePath).lastPathComponent
    }
}

enum WebPageEntrySource: String, Codable, Hashable {
    case bundledArchiveIndex
    case nativeFileIndex
}

struct WebPageProjectFile: Codable, Hashable, Identifiable {
    var relativePath: String
    var byteCount: Int64
    var typeIdentifier: String? = nil

    var id: String {
        relativePath
    }

    var fileName: String {
        URL(fileURLWithPath: relativePath).lastPathComponent
    }
}

struct WebPageImportResult {
    let page: WebPage
    let entry: WebPageEntry
}

struct WebPageDeletionTombstone: Codable, Hashable {
    let pageID: WebPage.ID
    var deletedAt: Date
    var kind: WebPageDeletionKind?

    var resolvedKind: WebPageDeletionKind {
        kind ?? .soft
    }
}

enum WebPageDeletionKind: String, Codable, Hashable {
    case soft
    case permanent
}

struct WebPageRestoreRevision: Codable, Hashable {
    let pageID: WebPage.ID
    var restoredAt: Date
    var activeRevisionAt: Date
}

struct DeletedWebPage: Identifiable, Codable, Hashable {
    var page: WebPage
    var deletedAt: Date
    var recoverableFolderName: String

    var id: WebPage.ID {
        page.id
    }
}

struct WebPageLibraryCloudSnapshot: Codable {
    var schemaVersion: Int
    var exportedAt: Date
    var pages: [WebPageCloudSnapshotPage]
    var deletions: [WebPageDeletionTombstone]
    var restoreRevisions: [WebPageRestoreRevision]

    init(
        schemaVersion: Int = 1,
        exportedAt: Date,
        pages: [WebPageCloudSnapshotPage],
        deletions: [WebPageDeletionTombstone],
        restoreRevisions: [WebPageRestoreRevision] = []
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.pages = pages
        self.deletions = deletions
        self.restoreRevisions = restoreRevisions
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case exportedAt
        case pages
        case deletions
        case restoreRevisions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        pages = try container.decode([WebPageCloudSnapshotPage].self, forKey: .pages)
        deletions = try container.decodeIfPresent([WebPageDeletionTombstone].self, forKey: .deletions) ?? []
        restoreRevisions = try container.decodeIfPresent([WebPageRestoreRevision].self, forKey: .restoreRevisions) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(exportedAt, forKey: .exportedAt)
        try container.encode(pages, forKey: .pages)
        try container.encode(deletions, forKey: .deletions)
        try container.encode(restoreRevisions, forKey: .restoreRevisions)
    }
}

struct WebPageResourcePackageManifest: Codable, Hashable {
    var schemaVersion: Int
    var projectID: WebPage.ID
    var packageHash: String
    var defaultEntryRelativePath: String
    var fileCount: Int
    var totalByteCount: Int64
    var files: [WebPageResourcePackageManifestFile]
}

struct WebPageResourcePackageManifestFile: Codable, Hashable {
    var relativePath: String
    var byteCount: Int64
    var sha256: String
}

struct WebPageResourceMetadataRecord: Hashable {
    var projectID: WebPage.ID
    var page: WebPage?
    var packageAssetID: String?
    var packageHash: String?
    var deletedAt: Date?
    var deleteKind: WebPageDeletionKind?
    var restoredAt: Date?
    var activeRevisionAt: Date?
    var iconData: Data?

    var isDeleted: Bool {
        deletedAt != nil
    }

    var isEffectivelyDeleted: Bool {
        guard let deletedAt else { return false }
        guard let restoredAt else { return true }
        return restoredAt <= deletedAt
    }
}

struct WebPageCloudSnapshotPage: Codable {
    var page: WebPage
    var htmlData: Data
    var folderFiles: [WebPageCloudSnapshotFile]?
}

struct WebPageCloudSnapshotFile: Codable, Hashable {
    var relativePath: String
    var data: Data
}

struct WebPageLibraryLocalDiagnostics {
    var pageCount: Int
    var recentlyDeletedPageCount: Int
    var recoverableFolderCount: Int
    var deletionTombstoneCount: Int
    var restoreRevisionCount: Int
    var permanentDeletionTombstoneCount: Int
    var entryCount: Int
    var fileCount: Int
    var fileByteCount: Int
    var runtimeStoragePageCount: Int
    var runtimeStorageDetails: [String]
    var missingEntryPageCount: Int
    var missingEntryDetails: [String]
    var packageStatusCounts: [String: Int]
    var cloudUnavailableDetails: [String]
    var recentlyDeletedDetails: [String]
    var tombstoneDetails: [String]
    var restoreRevisionDetails: [String]
    var anomalyDetails: [String]
}

struct WebPageLibraryMergeDiagnostics {
    var changed: Bool
    var before: WebPageLibraryLocalDiagnostics
    var after: WebPageLibraryLocalDiagnostics
    var mergeVerdicts: [String] = []
    var fileMovementDetails: [String] = []
    var sameContentDifferentIdentityDetails: [String] = []
}

enum WebPageLoadStatus: String, Codable, Hashable {
    case ready
    case missing
    case failed
    case metadataOnly
    case downloading
    case downloadFailed
    case invalidPackage

    var title: String {
        switch self {
        case .ready: return AppStrings.localized("可浏览")
        case .missing: return AppStrings.localized("文件缺失")
        case .failed: return AppStrings.localized("加载失败")
        case .metadataOnly: return AppStrings.localized("等待下载")
        case .downloading: return AppStrings.localized("下载中")
        case .downloadFailed: return AppStrings.localized("下载失败")
        case .invalidPackage: return AppStrings.localized("资源包损坏")
        }
    }

    var isCloudPackageUnavailable: Bool {
        switch self {
        case .metadataOnly, .downloading, .downloadFailed, .invalidPackage:
            return true
        case .ready, .missing, .failed:
            return false
        }
    }
}

enum WebPageLibraryError: LocalizedError {
    case unsupportedFileType
    case unreadableFile
    case unreadableArchive
    case importFileTooLarge
    case archiveMissingHTML
    case unableToExtractArchive
    case missingEntryFile
    case unableToPrepareStorage
    case missingRecoverableFolder

    var errorDescription: String? {
        switch self {
        case .unsupportedFileType:
            return AppStrings.localized("请选择一个可打开的本地文件。")
        case .unreadableFile:
            return AppStrings.localized("无法读取这个 HTML 文件。")
        case .unreadableArchive:
            return AppStrings.localized("无法读取这个 ZIP 压缩包。")
        case .importFileTooLarge:
            return String(
                format: AppStrings.localized("这个文件太大，无法导入。请选择不超过 %@ 的文件。"),
                formattedWebPageByteCount(webPageMaximumImportedFileByteCount)
            )
        case .archiveMissingHTML:
            return AppStrings.localized("这个 ZIP 压缩包里没有可打开的 HTML 文件。")
        case .unableToExtractArchive:
            return AppStrings.localized("无法解压这个 ZIP 压缩包。")
        case .missingEntryFile:
            return AppStrings.localized("网页入口文件不存在。")
        case .unableToPrepareStorage:
            return AppStrings.localized("无法准备本地网页文件夹。")
        case .missingRecoverableFolder:
            return AppStrings.localized("网页文件缺失")
        }
    }
}

@MainActor
@Observable
final class WebPageLibrary {
    private(set) var pages: [WebPage] = []
    private(set) var recentlyDeletedPages: [DeletedWebPage] = []
    private(set) var deletionTombstones: [WebPageDeletionTombstone] = []
    private(set) var restoreRevisions: [WebPageRestoreRevision] = []

    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var searchIndex = WebPageSearchIndex()
    private(set) var isBuildingFullSearchIndex = false
    private var searchIndexRefreshSequence = 0
    private var opportunisticFullSearchIndexBuildTask: Task<Void, Never>?

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        load()
        loadRecentlyDeletedPages()
        loadDeletionTombstones()
        loadRestoreRevisions()
        promoteStoredSingleFileProjectsIfNeeded()
        normalizeEntryOrdering()
        normalizeRecentlyDeleted()
        refreshAvailability()
        refreshDeletedAvailability()
        backfillContentHashes()
        refreshSafeAreaBackgrounds()
        loadSearchIndexOrRebuild()
        refreshProjectWidgetSnapshot(reloadsTimelines: false)
    }

    func page(withID id: WebPage.ID) -> WebPage? {
        pages.first { $0.id == id }
    }

    func entry(withID entryID: WebPageEntry.ID, in page: WebPage) -> WebPageEntry? {
        page.resolvedEntries.first { $0.id == entryID }
    }

    func defaultEntry(for page: WebPage) -> WebPageEntry {
        if let defaultEntryID = page.defaultEntryID,
           let entry = entry(withID: defaultEntryID, in: page) {
            return entry
        }
        return page.resolvedEntries[0]
    }

    func folderURL(for page: WebPage) -> URL {
        webPagesDirectory.appendingPathComponent(page.folderName, isDirectory: true)
    }

    func recoverableFolderURL(for deletedPage: DeletedWebPage) -> URL {
        recentlyDeletedDirectory.appendingPathComponent(deletedPage.recoverableFolderName, isDirectory: true)
    }

    func recentlyDeletedPage(withID id: WebPage.ID) -> DeletedWebPage? {
        recentlyDeletedPages.first { $0.id == id }
    }

    func entry(withID entryID: WebPageEntry.ID, in deletedPage: DeletedWebPage) -> WebPageEntry? {
        entry(withID: entryID, in: deletedPage.page)
    }

    func defaultEntry(for deletedPage: DeletedWebPage) -> WebPageEntry {
        defaultEntry(for: deletedPage.page)
    }

    func entryURL(for deletedPage: DeletedWebPage) -> URL {
        entryURL(for: deletedPage, entry: defaultEntry(for: deletedPage))
    }

    func entryURL(for deletedPage: DeletedWebPage, entry: WebPageEntry) -> URL {
        recoverableFolderURL(for: deletedPage).appendingPathComponent(entry.entryRelativePath, isDirectory: false)
    }

    func entryExists(for deletedPage: DeletedWebPage, entry: WebPageEntry) -> Bool {
        if entry.source == .bundledArchiveIndex || entry.source == .nativeFileIndex {
            return Self.hasFixedResourceFiles(
                in: recoverableFolderURL(for: deletedPage),
                fileManager: fileManager
            )
        }
        return fileManager.fileExists(atPath: entryURL(for: deletedPage, entry: entry).path)
    }

    func projectIconURL(for deletedPage: DeletedWebPage) -> URL? {
        guard let projectIcon = deletedPage.page.projectIcon else { return nil }
        let url = recoverableFolderURL(for: deletedPage).appendingPathComponent(projectIcon.fileName, isDirectory: false)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return url
    }

    func entryURL(for page: WebPage) -> URL {
        entryURL(for: page, entry: defaultEntry(for: page))
    }

    func entryURL(for page: WebPage, entry: WebPageEntry) -> URL {
        folderURL(for: page).appendingPathComponent(entry.entryRelativePath, isDirectory: false)
    }

    func entryExists(for page: WebPage, entry: WebPageEntry) -> Bool {
        if entry.source == .bundledArchiveIndex || entry.source == .nativeFileIndex {
            return Self.hasFixedResourceFiles(in: folderURL(for: page), fileManager: fileManager)
        }
        return fileManager.fileExists(atPath: entryURL(for: page, entry: entry).path)
    }

    func projectFiles(for page: WebPage) -> [WebPageProjectFile] {
        Self.archiveProjectFiles(in: folderURL(for: page), fileManager: fileManager)
    }

    func projectFiles(for deletedPage: DeletedWebPage) -> [WebPageProjectFile] {
        Self.archiveProjectFiles(in: recoverableFolderURL(for: deletedPage), fileManager: fileManager)
    }

    func projectIconURL(for page: WebPage) -> URL? {
        guard let projectIcon = page.projectIcon else { return nil }
        let url = folderURL(for: page).appendingPathComponent(projectIcon.fileName, isDirectory: false)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return url
    }

    var hasFullContentSearchIndex: Bool {
        searchIndex.hasHTMLContent
    }

    var iCloudPresenceContentChangedAt: Date {
        let pageDates = pages.map { page in
            [
                page.createdAt,
                page.updatedAt ?? .distantPast,
                page.projectIcon?.updatedAt ?? .distantPast
            ].max() ?? .distantPast
        }
        let deletedDates = deletionTombstones.map(\.deletedAt)
        let restoredDates = restoreRevisions.map { revision in
            max(revision.restoredAt, revision.activeRevisionAt)
        }
        return (pageDates + deletedDates + restoredDates).max() ?? .distantPast
    }

    func searchResults(matching query: String, scope: WebPageSearchScope = .full) -> [WebPageSearchResult] {
        switch scope {
        case .basic:
            return WebPageSearchIndex.searchMetadata(query, pages: pages)
        case .full:
            guard hasFullContentSearchIndex else {
                return WebPageSearchIndex.searchMetadata(query, pages: pages)
            }
            return searchIndex.search(query, pages: pages)
        }
    }

    func scheduleOpportunisticFullContentSearchIndexBuildIfNeeded() {
        guard !hasFullContentSearchIndex, !pages.isEmpty else {
            opportunisticFullSearchIndexBuildTask?.cancel()
            opportunisticFullSearchIndexBuildTask = nil
            return
        }

        opportunisticFullSearchIndexBuildTask?.cancel()
        opportunisticFullSearchIndexBuildTask = Task(priority: .utility) { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: opportunisticFullSearchIndexBuildDelayNanoseconds)
            guard !Task.isCancelled,
                  let self else {
                return
            }

            await self.buildFullContentSearchIndexIfNeeded(priority: .utility)
            guard !Task.isCancelled else { return }
            self.opportunisticFullSearchIndexBuildTask = nil
        }
    }

    func buildFullContentSearchIndexIfNeeded(priority: TaskPriority = .userInitiated) async {
        while isBuildingFullSearchIndex, !hasFullContentSearchIndex {
            guard !Task.isCancelled else { return }
            try? await Task.sleep(nanoseconds: 120_000_000)
        }

        guard !Task.isCancelled,
              !hasFullContentSearchIndex else {
            return
        }

        isBuildingFullSearchIndex = true
        searchIndexRefreshSequence += 1
        let refreshSequence = searchIndexRefreshSequence
        defer {
            isBuildingFullSearchIndex = false
        }

        let pagesSnapshot = pages
        let pageFolders = pagesSnapshot.map { page in
            (page: page, folderURL: folderURL(for: page))
        }
        let fileManager = fileManager
        let searchIndexURL = searchIndexURL
        let nextIndex = await Task.detached(priority: priority) {
            WebPageSearchIndex.build(
                pageFolders: pageFolders,
                fileManager: fileManager,
                includeHTMLContent: true
            )
        }.value

        guard refreshSequence == searchIndexRefreshSequence else { return }
        searchIndex = nextIndex
        let indexToSave = nextIndex
        Task.detached(priority: .utility) {
            indexToSave.save(to: searchIndexURL)
        }
    }

    @discardableResult
    func importWebPage(from sourceURL: URL) throws -> WebPageImportResult {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        guard Self.isSupportedSource(sourceURL) else {
            throw WebPageLibraryError.unsupportedFileType
        }

        guard fileManager.isReadableFile(atPath: sourceURL.path) else {
            throw Self.isSupportedArchive(sourceURL) ? WebPageLibraryError.unreadableArchive : .unreadableFile
        }

        try Self.validateImportSize(of: sourceURL)

        if Self.isSupportedArchive(sourceURL) {
            return try importArchive(from: sourceURL)
        }
        if Self.isSupportedHTML(sourceURL) {
            return try importHTMLFile(from: sourceURL)
        }

        return try importNativeFile(from: sourceURL)
    }

    @discardableResult
    func importHTML(from sourceURL: URL) throws -> WebPage {
        try importWebPage(from: sourceURL).page
    }

    private func importHTMLFile(from sourceURL: URL) throws -> WebPageImportResult {
        let contentSHA256: String
        let htmlContent: String
        do {
            contentSHA256 = try Self.sha256HexDigest(for: sourceURL)
            htmlContent = try String(contentsOf: sourceURL, encoding: .utf8)
        } catch {
            throw WebPageLibraryError.unreadableFile
        }

        try ensureStorage()

        if let existingIndex = pages.firstIndex(where: { $0.contentSHA256 == contentSHA256 }) {
            let id = pages[existingIndex].id
            try restoreEntryIfNeeded(for: pages[existingIndex], from: sourceURL)
            pages[existingIndex].contentSHA256 = contentSHA256
            pages[existingIndex].lastOpenedAt = Date()
            pages[existingIndex].lastLoadStatus = .ready
            pages[existingIndex].projectKind = .singleFile
            pages[existingIndex].singleFileFormat = .html
            if pages[existingIndex].sourceFileName == nil {
                pages[existingIndex].sourceFileName = Self.sourceFileName(from: sourceURL)
            }
            let existingEntryURL = entryURL(for: pages[existingIndex])
            let (topColor, bottomColor) = BackgroundColorExtractor.extractColors(
                from: htmlContent,
                htmlFileURL: existingEntryURL,
                projectFolderURL: folderURL(for: pages[existingIndex]),
                fileManager: fileManager
            )
            pages[existingIndex].safeAreaTopColor = topColor
            pages[existingIndex].safeAreaBottomColor = bottomColor
            upsertEntries([Self.htmlEntry(
                id: pages[existingIndex].defaultEntryID ?? pages[existingIndex].id,
                title: Self.title(from: htmlContent, fallbackURL: sourceURL),
                relativePath: pages[existingIndex].entryRelativePath,
                htmlContent: htmlContent,
                openedAt: pages[existingIndex].lastOpenedAt,
                htmlFileURL: existingEntryURL,
                projectFolderURL: folderURL(for: pages[existingIndex]),
                fileManager: fileManager
            )], forPageAt: existingIndex)
            refreshAutomaticProjectIcon(forPageAt: existingIndex, htmlContent: htmlContent)
            sortPages()
            save()
            guard let reusedPage = pages.first(where: { $0.id == id }) else {
                throw WebPageLibraryError.missingEntryFile
            }
            return WebPageImportResult(page: reusedPage, entry: self.defaultEntry(for: reusedPage))
        }

        let id = UUID()
        let folderName = id.uuidString
        let destinationFolderURL = webPagesDirectory.appendingPathComponent(folderName, isDirectory: true)
        try fileManager.createDirectory(at: destinationFolderURL, withIntermediateDirectories: true)

        let entryURL = destinationFolderURL.appendingPathComponent("index.html", isDirectory: false)
        if fileManager.fileExists(atPath: entryURL.path) {
            try fileManager.removeItem(at: entryURL)
        }
        try fileManager.copyItem(at: sourceURL, to: entryURL)

        let (topColor, bottomColor) = BackgroundColorExtractor.extractColors(
            from: htmlContent,
            htmlFileURL: entryURL,
            projectFolderURL: destinationFolderURL,
            fileManager: fileManager
        )
        let now = Date()
        let baseTitle = Self.title(from: htmlContent, fallbackURL: sourceURL)
        let entry = Self.htmlEntry(
            id: id,
            title: baseTitle,
            relativePath: "index.html",
            htmlContent: htmlContent,
            openedAt: now,
            htmlFileURL: entryURL,
            projectFolderURL: destinationFolderURL,
            fileManager: fileManager
        )
        var page = WebPage(
            id: id,
            title: uniqueTitle(for: baseTitle),
            sourceDescription: sourceURL.deletingLastPathComponent().lastPathComponent,
            sourceFileName: Self.sourceFileName(from: sourceURL),
            folderName: folderName,
            entryRelativePath: "index.html",
            contentSHA256: contentSHA256,
            createdAt: now,
            lastOpenedAt: now,
            updatedAt: now,
            lastLoadStatus: .ready,
            safeAreaTopColor: topColor,
            safeAreaBottomColor: bottomColor,
            entries: [entry],
            defaultEntryID: entry.id,
            projectKind: .singleFile,
            singleFileFormat: .html
        )
        page.projectIcon = Self.generatedProjectIcon(
            from: htmlContent,
            entryRelativePath: entry.entryRelativePath,
            folderURL: destinationFolderURL,
            fileManager: fileManager
        )

        pages.insert(page, at: 0)
        sortPages()
        save()
        return WebPageImportResult(page: page, entry: entry)
    }

    private func importNativeFile(from sourceURL: URL) throws -> WebPageImportResult {
        let contentSHA256: String
        do {
            contentSHA256 = try Self.sha256HexDigest(for: sourceURL)
        } catch {
            throw WebPageLibraryError.unreadableFile
        }
        let format = WebPageSingleFileFormat.format(for: sourceURL)

        try ensureStorage()

        if let existingIndex = pages.firstIndex(where: { $0.contentSHA256 == contentSHA256 }) {
            let id = pages[existingIndex].id
            try restoreSingleFileProjectIfNeeded(forPageAt: existingIndex, from: sourceURL, format: format)
            pages[existingIndex].contentSHA256 = contentSHA256
            pages[existingIndex].lastOpenedAt = Date()
            pages[existingIndex].lastLoadStatus = .ready
            pages[existingIndex].projectKind = .singleFile
            pages[existingIndex].singleFileFormat = format
            if pages[existingIndex].sourceFileName == nil {
                pages[existingIndex].sourceFileName = Self.sourceFileName(from: sourceURL)
            }
            refreshAutomaticProjectIcon(forPageAt: existingIndex)
            sortPages()
            save()
            guard let reusedPage = pages.first(where: { $0.id == id }) else {
                throw WebPageLibraryError.missingEntryFile
            }
            return WebPageImportResult(page: reusedPage, entry: self.defaultEntry(for: reusedPage))
        }

        let id = UUID()
        let folderName = id.uuidString
        let destinationFolderURL = webPagesDirectory.appendingPathComponent(folderName, isDirectory: true)
        try fileManager.createDirectory(at: destinationFolderURL, withIntermediateDirectories: true)

        let fileName = Self.safeImportedFileName(from: sourceURL)
        let destinationURL = destinationFolderURL.appendingPathComponent(fileName, isDirectory: false)
        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            try? fileManager.removeItem(at: destinationFolderURL)
            throw WebPageLibraryError.unreadableFile
        }

        let now = Date()
        let baseTitle = Self.fileProjectTitle(from: sourceURL)
        let entry = Self.singleFileEntry(
            id: id,
            title: baseTitle,
            relativePath: fileName,
            openedAt: now
        )
        var page = WebPage(
            id: id,
            title: uniqueTitle(for: baseTitle),
            sourceDescription: sourceURL.deletingLastPathComponent().lastPathComponent,
            sourceFileName: Self.sourceFileName(from: sourceURL),
            folderName: folderName,
            entryRelativePath: fileName,
            contentSHA256: contentSHA256,
            createdAt: now,
            lastOpenedAt: now,
            updatedAt: now,
            lastLoadStatus: .ready,
            safeAreaTopColor: entry.safeAreaTopColor,
            safeAreaBottomColor: entry.safeAreaBottomColor,
            entries: [entry],
            defaultEntryID: entry.id,
            projectKind: .singleFile,
            singleFileFormat: format
        )
        page.projectIcon = Self.generatedSingleFileProjectIcon(
            format: format,
            in: destinationFolderURL,
            fileManager: fileManager
        )

        pages.insert(page, at: 0)
        sortPages()
        save()
        return WebPageImportResult(page: page, entry: entry)
    }

    private func importArchive(from sourceURL: URL) throws -> WebPageImportResult {
        let contentSHA256: String
        do {
            contentSHA256 = try Self.sha256HexDigest(for: sourceURL)
        } catch {
            throw WebPageLibraryError.unreadableArchive
        }

        try ensureStorage()

        if let existingIndex = pages.firstIndex(where: { $0.contentSHA256 == contentSHA256 }) {
            let id = pages[existingIndex].id
            try restoreArchiveFolder(for: pages[existingIndex], from: sourceURL)
            pages[existingIndex].contentSHA256 = contentSHA256
            pages[existingIndex].lastOpenedAt = Date()
            pages[existingIndex].lastLoadStatus = .ready
            if pages[existingIndex].sourceFileName == nil {
                pages[existingIndex].sourceFileName = Self.sourceFileName(from: sourceURL)
            }
            let folderURL = folderURL(for: pages[existingIndex])
            if let singleFileProject = Self.preparedSingleFileProject(
                in: folderURL,
                openedAt: pages[existingIndex].lastOpenedAt,
                entryID: pages[existingIndex].defaultEntryID ?? pages[existingIndex].id,
                fileManager: fileManager
            ) {
                upsertEntries([singleFileProject.entry], forPageAt: existingIndex)
                pages[existingIndex].projectKind = .singleFile
                pages[existingIndex].singleFileFormat = singleFileProject.format
                pages[existingIndex].entryRelativePath = singleFileProject.entry.entryRelativePath
                pages[existingIndex].defaultEntryID = singleFileProject.entry.id
                pages[existingIndex].safeAreaTopColor = singleFileProject.entry.safeAreaTopColor
                pages[existingIndex].safeAreaBottomColor = singleFileProject.entry.safeAreaBottomColor
            } else {
                if let entries = try? Self.htmlEntries(
                    in: folderURL,
                    openedAt: pages[existingIndex].lastOpenedAt,
                    fallbackArchiveName: pages[existingIndex].sourceFileName,
                    fileManager: fileManager
                ),
                   !entries.isEmpty {
                    upsertEntries(entries, forPageAt: existingIndex)
                }
                pages[existingIndex].projectKind = pages[existingIndex].resolvedEntries.contains {
                    $0.source == .nativeFileIndex || $0.source == .bundledArchiveIndex
                } ? .nativeFileArchive : .html
                pages[existingIndex].singleFileFormat = nil
                let defaultEntry = defaultEntry(for: pages[existingIndex])
                if let htmlContent = Self.htmlContent(
                    for: defaultEntry,
                    in: folderURL,
                    fileManager: fileManager
                ) {
                    let (topColor, bottomColor) = BackgroundColorExtractor.extractColors(
                        from: htmlContent,
                        htmlFileURL: entryURL(for: pages[existingIndex], entry: defaultEntry),
                        projectFolderURL: folderURL,
                        fileManager: fileManager
                    )
                    pages[existingIndex].safeAreaTopColor = topColor
                    pages[existingIndex].safeAreaBottomColor = bottomColor
                }
            }
            refreshAutomaticProjectIcon(forPageAt: existingIndex)
            sortPages()
            save()
            guard let reusedPage = pages.first(where: { $0.id == id }) else {
                throw WebPageLibraryError.missingEntryFile
            }
            return WebPageImportResult(page: reusedPage, entry: self.defaultEntry(for: reusedPage))
        }

        let id = UUID()
        let folderName = id.uuidString
        let destinationFolderURL = webPagesDirectory.appendingPathComponent(folderName, isDirectory: true)

        do {
            try ZipArchiveExtractor(
                fileManager: fileManager,
                maximumExpandedByteCount: webPageMaximumImportedFileByteCount
            ).extractArchive(at: sourceURL, to: destinationFolderURL)
        } catch ZipArchiveExtractorError.archiveTooLarge {
            try? fileManager.removeItem(at: destinationFolderURL)
            throw WebPageLibraryError.importFileTooLarge
        } catch {
            try? fileManager.removeItem(at: destinationFolderURL)
            throw WebPageLibraryError.unableToExtractArchive
        }

        let now = Date()
        if let singleFileProject = Self.preparedSingleFileProject(
            in: destinationFolderURL,
            openedAt: now,
            entryID: id,
            fileManager: fileManager
        ) {
            var page = WebPage(
                id: id,
                title: uniqueTitle(for: singleFileProject.entry.title),
                sourceDescription: sourceURL.deletingLastPathComponent().lastPathComponent,
                sourceFileName: Self.sourceFileName(from: sourceURL),
                folderName: folderName,
                entryRelativePath: singleFileProject.entry.entryRelativePath,
                contentSHA256: contentSHA256,
                createdAt: now,
                lastOpenedAt: now,
                updatedAt: now,
                lastLoadStatus: .ready,
                safeAreaTopColor: singleFileProject.entry.safeAreaTopColor,
                safeAreaBottomColor: singleFileProject.entry.safeAreaBottomColor,
                entries: [singleFileProject.entry],
                defaultEntryID: singleFileProject.entry.id,
                projectKind: .singleFile,
                singleFileFormat: singleFileProject.format
            )
            page.projectIcon = Self.generatedSingleFileProjectIcon(
                format: singleFileProject.format,
                htmlContent: singleFileProject.htmlContent,
                entryRelativePath: singleFileProject.entry.entryRelativePath,
                in: destinationFolderURL,
                fileManager: fileManager
            )
            pages.insert(page, at: 0)
            sortPages()
            save()
            return WebPageImportResult(page: page, entry: singleFileProject.entry)
        }

        let entries: [WebPageEntry]
        do {
            entries = try Self.htmlEntries(
                in: destinationFolderURL,
                openedAt: now,
                fallbackArchiveName: Self.sourceFileName(from: sourceURL),
                fileManager: fileManager
            )
        } catch {
            try? fileManager.removeItem(at: destinationFolderURL)
            throw WebPageLibraryError.archiveMissingHTML
        }

        guard let defaultEntry = Self.preferredEntry(in: entries) else {
            try? fileManager.removeItem(at: destinationFolderURL)
            throw WebPageLibraryError.archiveMissingHTML
        }

        guard let htmlContent = Self.htmlContent(
            for: defaultEntry,
            in: destinationFolderURL,
            fileManager: fileManager
        ) else {
            try? fileManager.removeItem(at: destinationFolderURL)
            throw WebPageLibraryError.unreadableFile
        }

        let entryURL = destinationFolderURL.appendingPathComponent(defaultEntry.entryRelativePath, isDirectory: false)
        let (topColor, bottomColor) = BackgroundColorExtractor.extractColors(
            from: htmlContent,
            htmlFileURL: entryURL,
            projectFolderURL: destinationFolderURL,
            fileManager: fileManager
        )
        let projectBaseTitle = Self.archiveTitle(
            from: sourceURL,
            defaultEntry: defaultEntry,
            htmlContent: htmlContent
        )
        var page = WebPage(
            id: id,
            title: uniqueTitle(for: projectBaseTitle),
            sourceDescription: sourceURL.deletingLastPathComponent().lastPathComponent,
            sourceFileName: Self.sourceFileName(from: sourceURL),
            folderName: folderName,
            entryRelativePath: defaultEntry.entryRelativePath,
            contentSHA256: contentSHA256,
            createdAt: now,
            lastOpenedAt: now,
            updatedAt: now,
            lastLoadStatus: .ready,
            safeAreaTopColor: topColor,
            safeAreaBottomColor: bottomColor,
            entries: Self.uniquedEntryTitles(entries),
            defaultEntryID: defaultEntry.id,
            projectKind: defaultEntry.source == .nativeFileIndex || defaultEntry.source == .bundledArchiveIndex ? .nativeFileArchive : .html
        )
        if page.resolvedProjectKind == .html {
            page.projectIcon = Self.generatedProjectIcon(
                from: htmlContent,
                entryRelativePath: defaultEntry.entryRelativePath,
                folderURL: destinationFolderURL,
                fileManager: fileManager
            )
        } else {
            page.projectIcon = Self.generatedProjectImageIcon(
                in: destinationFolderURL,
                fileManager: fileManager
            )
        }

        pages.insert(page, at: 0)
        sortPages()
        save()
        return WebPageImportResult(page: page, entry: defaultEntry)
    }

    func markOpened(_ page: WebPage, entry: WebPageEntry) {
        let now = Date()
        update(page.id, shouldRebuildSearchIndex: false) { item in
            item.lastOpenedAt = now
            item.lastLoadStatus = .ready
            Self.updateEntry(entry.id, in: &item) { entry in
                entry.lastOpenedAt = now
                entry.lastLoadStatus = .ready
            }
        }
    }

    func markFailed(_ page: WebPage, entry: WebPageEntry) {
        update(page.id, shouldRebuildSearchIndex: false) { item in
            item.lastLoadStatus = .failed
            Self.updateEntry(entry.id, in: &item) { entry in
                entry.lastLoadStatus = .failed
            }
        }
    }

    @discardableResult
    func rename(_ page: WebPage, to proposedTitle: String) -> Bool {
        let trimmedTitle = Self.normalizedDisplayTitle(proposedTitle)
        guard !trimmedTitle.isEmpty,
              let currentPage = pages.first(where: { $0.id == page.id }) else {
            return false
        }
        let renamedTitle = uniqueTitle(for: trimmedTitle, excluding: page.id)
        guard currentPage.title != renamedTitle else { return false }

        update(page.id) { item in
            item.title = renamedTitle
            item.updatedAt = Date()
        }
        return true
    }

    @discardableResult
    func setCustomProjectIcon(for page: WebPage, from sourceURL: URL) -> Bool {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        guard let imageData = try? Data(contentsOf: sourceURL),
              let image = UIImage(data: imageData) else {
            return false
        }

        return setCustomProjectIcon(for: page, image: image)
    }

    @discardableResult
    func setCustomProjectIcon(for page: WebPage, imageData: Data) -> Bool {
        guard let image = UIImage(data: imageData) else {
            return false
        }

        return setCustomProjectIcon(for: page, image: image)
    }

    func delete(_ page: WebPage) {
        guard let index = pages.firstIndex(where: { $0.id == page.id }) else { return }
        let deletedAt = Date()
        var deletedPage = pages.remove(at: index)
        deletedPage.updatedAt = deletedAt
        let recoverableFolderName = uniqueRecoverableFolderName(for: deletedPage.folderName)
        let sourceFolderURL = folderURL(for: page)
        let destinationFolderURL = recentlyDeletedDirectory.appendingPathComponent(
            recoverableFolderName,
            isDirectory: true
        )

        do {
            try ensureStorage()
            try fileManager.createDirectory(at: recentlyDeletedDirectory, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: sourceFolderURL.path) {
                try fileManager.moveItem(at: sourceFolderURL, to: destinationFolderURL)
            }
        } catch {
            pages.insert(deletedPage, at: index)
            sortPages()
            return
        }

        recentlyDeletedPages.append(
            DeletedWebPage(
                page: deletedPage,
                deletedAt: deletedAt,
                recoverableFolderName: recoverableFolderName
            )
        )
        sortRecentlyDeletedPages()
        recordDeletion(for: deletedPage, at: deletedAt, kind: .soft)
        save()
    }

    @discardableResult
    func restore(_ deletedPage: DeletedWebPage) throws -> WebPage {
        guard let index = recentlyDeletedPages.firstIndex(where: { $0.id == deletedPage.id }) else {
            throw WebPageLibraryError.missingRecoverableFolder
        }

        var restoredPage = recentlyDeletedPages[index].page
        let recoverableFolderURL = recoverableFolderURL(for: recentlyDeletedPages[index])
        guard fileManager.fileExists(atPath: recoverableFolderURL.path) else {
            throw WebPageLibraryError.missingRecoverableFolder
        }

        let now = Date()
        let restoredFolderName = uniqueActiveFolderName(for: restoredPage.folderName)
        let destinationFolderURL = webPagesDirectory.appendingPathComponent(restoredFolderName, isDirectory: true)
        try ensureStorage()
        try fileManager.moveItem(at: recoverableFolderURL, to: destinationFolderURL)

        recentlyDeletedPages.remove(at: index)
        restoredPage.folderName = restoredFolderName
        restoredPage.title = uniqueTitle(for: restoredPage.title, excluding: restoredPage.id)
        restoredPage.createdAt = now
        restoredPage.lastOpenedAt = now
        restoredPage.updatedAt = now
        restoredPage.entries = restoredPage.resolvedEntries.map { entry in
            var restoredEntry = entry
            restoredEntry.lastOpenedAt = now
            return restoredEntry
        }
        pages.insert(restoredPage, at: 0)
        upsertRestoreRevision(
            WebPageRestoreRevision(
                pageID: restoredPage.id,
                restoredAt: now,
                activeRevisionAt: now
            )
        )
        sortPages()
        save()
        return restoredPage
    }

    func permanentlyDelete(_ deletedPage: DeletedWebPage) {
        guard let index = recentlyDeletedPages.firstIndex(where: { $0.id == deletedPage.id }) else { return }
        let item = recentlyDeletedPages.remove(at: index)
        let deletedAt = Date()
        try? fileManager.removeItem(at: recoverableFolderURL(for: item))
        recordDeletion(for: item.page, at: deletedAt, kind: .permanent)
        Task {
            await WebPageRuntimeStorage.removeWebsiteDataStore(
                identifier: WebPageRuntimeStorage.dataStoreIdentifier(for: item.page)
            )
        }
        save()
    }

    @discardableResult
    func buildRecentlyDeletedDebugFixtures(now: Date = .now) throws -> Int {
        guard AppBuildFlavor.current.isTestingBuild else { return 0 }

        struct Fixture {
            let id: WebPage.ID
            let entryID: WebPageEntry.ID
            let titleKey: String
            let fileName: String
            let folderName: String
            let recoverableFolderName: String
            let deletedDayOffset: Int
            let accentHex: String
        }

        let fixtures = [
            Fixture(
                id: WebPage.ID(uuidString: "00000000-0000-0000-0000-00000000D001")!,
                entryID: WebPageEntry.ID(uuidString: "00000000-0000-0000-0000-00000000E001")!,
                titleKey: "debug.recentlyDeleted.fixture.today.title",
                fileName: "debug-recently-deleted-today.html",
                folderName: "DebugRecentlyDeletedFixtureToday",
                recoverableFolderName: "DebugRecentlyDeletedFixtureToday.deleted",
                deletedDayOffset: 0,
                accentHex: "#5E8CFF"
            ),
            Fixture(
                id: WebPage.ID(uuidString: "00000000-0000-0000-0000-00000000D004")!,
                entryID: WebPageEntry.ID(uuidString: "00000000-0000-0000-0000-00000000E004")!,
                titleKey: "debug.recentlyDeleted.fixture.fourDays.title",
                fileName: "debug-recently-deleted-4-days.html",
                folderName: "DebugRecentlyDeletedFixtureFourDays",
                recoverableFolderName: "DebugRecentlyDeletedFixtureFourDays.deleted",
                deletedDayOffset: 4,
                accentHex: "#29A383"
            ),
            Fixture(
                id: WebPage.ID(uuidString: "00000000-0000-0000-0000-00000000D008")!,
                entryID: WebPageEntry.ID(uuidString: "00000000-0000-0000-0000-00000000E008")!,
                titleKey: "debug.recentlyDeleted.fixture.eightDays.title",
                fileName: "debug-recently-deleted-8-days.html",
                folderName: "DebugRecentlyDeletedFixtureEightDays",
                recoverableFolderName: "DebugRecentlyDeletedFixtureEightDays.deleted",
                deletedDayOffset: 8,
                accentHex: "#E09B2D"
            ),
            Fixture(
                id: WebPage.ID(uuidString: "00000000-0000-0000-0000-00000000D035")!,
                entryID: WebPageEntry.ID(uuidString: "00000000-0000-0000-0000-00000000E035")!,
                titleKey: "debug.recentlyDeleted.fixture.thirtyFiveDays.title",
                fileName: "debug-recently-deleted-35-days.html",
                folderName: "DebugRecentlyDeletedFixtureThirtyFiveDays",
                recoverableFolderName: "DebugRecentlyDeletedFixtureThirtyFiveDays.deleted",
                deletedDayOffset: 35,
                accentHex: "#B060E8"
            )
        ]
        let fixtureIDs = Set(fixtures.map(\.id))

        try ensureStorage()
        try fileManager.createDirectory(at: recentlyDeletedDirectory, withIntermediateDirectories: true)

        for page in pages where fixtureIDs.contains(page.id) {
            try? fileManager.removeItem(at: folderURL(for: page))
        }
        pages.removeAll { fixtureIDs.contains($0.id) }

        for deletedPage in recentlyDeletedPages where fixtureIDs.contains(deletedPage.id) {
            try? fileManager.removeItem(at: recoverableFolderURL(for: deletedPage))
        }
        recentlyDeletedPages.removeAll { fixtureIDs.contains($0.id) }
        deletionTombstones.removeAll { fixtureIDs.contains($0.pageID) }
        restoreRevisions.removeAll { fixtureIDs.contains($0.pageID) }

        let calendar = Calendar.current
        for fixture in fixtures {
            let deletedAt = calendar.date(byAdding: .day, value: -fixture.deletedDayOffset, to: now)
                ?? now.addingTimeInterval(-Double(fixture.deletedDayOffset) * 24 * 60 * 60)
            let title = AppStrings.localized(fixture.titleKey)
            let entry = WebPageEntry(
                id: fixture.entryID,
                title: title,
                entryRelativePath: "index.html",
                lastOpenedAt: deletedAt.addingTimeInterval(-30 * 60),
                lastLoadStatus: .ready,
                safeAreaTopColor: fixture.accentHex,
                safeAreaBottomColor: "#FFF7ED"
            )
            let page = WebPage(
                id: fixture.id,
                title: title,
                sourceDescription: AppStrings.localized("debug.recentlyDeleted.fixture.sourceDescription"),
                sourceFileName: fixture.fileName,
                folderName: fixture.folderName,
                entryRelativePath: entry.entryRelativePath,
                contentSHA256: nil,
                createdAt: deletedAt.addingTimeInterval(-24 * 60 * 60),
                lastOpenedAt: entry.lastOpenedAt,
                updatedAt: deletedAt,
                lastLoadStatus: .ready,
                safeAreaTopColor: fixture.accentHex,
                safeAreaBottomColor: "#FFF7ED",
                entries: [entry],
                defaultEntryID: entry.id,
                projectIcon: nil,
                projectKind: .html
            )
            let deletedPage = DeletedWebPage(
                page: page,
                deletedAt: deletedAt,
                recoverableFolderName: fixture.recoverableFolderName
            )
            let recoverableFolderURL = recoverableFolderURL(for: deletedPage)
            try? fileManager.removeItem(at: recoverableFolderURL)
            try fileManager.createDirectory(at: recoverableFolderURL, withIntermediateDirectories: true)
            let html = Self.debugRecentlyDeletedFixtureHTML(
                title: title,
                deletedAt: deletedAt,
                accentHex: fixture.accentHex
            )
            try html.write(
                to: recoverableFolderURL.appendingPathComponent(entry.entryRelativePath, isDirectory: false),
                atomically: true,
                encoding: .utf8
            )

            recentlyDeletedPages.append(deletedPage)
            recordDeletion(for: page, at: deletedAt, kind: .soft)
        }

        sortPages()
        sortRecentlyDeletedPages()
        save()
        return fixtures.count
    }

    private static func debugRecentlyDeletedFixtureHTML(
        title: String,
        deletedAt: Date,
        accentHex: String
    ) -> String {
        let escapedTitle = htmlEscaped(title)
        let deletedAtText = ISO8601DateFormatter().string(from: deletedAt)
        let kicker = htmlEscaped(AppStrings.localized("debug.recentlyDeleted.fixture.html.kicker"))
        let detail = htmlEscaped(AppStrings.localized("debug.recentlyDeleted.fixture.html.detail"))

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(escapedTitle)</title>
          <style>
            :root { color-scheme: light dark; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
            body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: #fff7ed; color: #1f2937; }
            main { width: min(680px, calc(100vw - 40px)); border-radius: 24px; padding: 32px; background: white; box-shadow: 0 18px 48px rgba(31, 41, 55, 0.14); }
            .badge { display: inline-flex; align-items: center; border-radius: 999px; padding: 8px 12px; background: \(accentHex); color: white; font-size: 13px; font-weight: 700; }
            h1 { margin: 18px 0 10px; font-size: clamp(28px, 6vw, 44px); line-height: 1.04; }
            p { margin: 0; color: #4b5563; font-size: 16px; line-height: 1.7; }
            code { display: inline-block; margin-top: 18px; padding: 8px 10px; border-radius: 10px; background: #f3f4f6; color: #374151; }
          </style>
        </head>
        <body>
          <main>
            <span class="badge">\(kicker)</span>
            <h1>\(escapedTitle)</h1>
            <p>\(detail)</p>
            <code>\(deletedAtText)</code>
          </main>
        </body>
        </html>
        """
    }

    private static func htmlEscaped(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    func resourcePackageManifest(for page: WebPage) throws -> WebPageResourcePackageManifest {
        try Self.resourcePackageManifest(
            projectID: page.id,
            defaultEntryRelativePath: defaultEntry(for: page).entryRelativePath,
            folderURL: folderURL(for: page),
            fileManager: fileManager
        )
    }

    func writeResourcePackageArchive(for page: WebPage, to archiveURL: URL) throws -> WebPageResourcePackageManifest {
        let manifest = try resourcePackageManifest(for: page)
        try ZipArchiveWriter(fileManager: fileManager).archiveFolder(
            at: folderURL(for: page),
            to: archiveURL,
            excluding: Self.isResourcePackageExcludedPath
        )
        return manifest
    }

    func resourcePackagePreparationDiagnostic(for page: WebPage) -> String {
        let folderURL = folderURL(for: page)
        let folderExists = fileManager.fileExists(atPath: folderURL.path)
        let defaultEntry = defaultEntry(for: page)
        let defaultEntryURL = folderURL.appendingPathComponent(defaultEntry.entryRelativePath, isDirectory: false)
        let defaultEntryExists = fileManager.fileExists(atPath: defaultEntryURL.path)

        do {
            let writer = ZipArchiveWriter(fileManager: fileManager)
            let allPaths = try writer.regularFileRelativePaths(in: folderURL)
            let includedPaths = try writer.regularFileRelativePaths(
                in: folderURL,
                excluding: Self.isResourcePackageExcludedPath
            )
            let includedSet = Set(includedPaths)
            let excludedPaths = allPaths.filter { !includedSet.contains($0) }
            let includedByteCount = includedPaths.reduce(Int64(0)) { partialResult, path in
                let fileURL = folderURL.appendingPathComponent(path, isDirectory: false)
                let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
                return partialResult + Int64(values?.fileSize ?? 0)
            }

            return [
                "folder=\(page.folderName)",
                "folderExists=\(folderExists)",
                "defaultEntry=\(defaultEntry.entryRelativePath)",
                "defaultEntryExists=\(defaultEntryExists)",
                "regularFiles=\(allPaths.count)",
                "packageFiles=\(includedPaths.count)",
                "excludedFiles=\(excludedPaths.count)",
                "packageBytes=\(includedByteCount)",
                "samplePackageFiles=\(includedPaths.prefix(5).joined(separator: ","))",
                "sampleExcludedFiles=\(excludedPaths.prefix(5).joined(separator: ","))"
            ].joined(separator: ", ")
        } catch {
            return [
                "folder=\(page.folderName)",
                "folderExists=\(folderExists)",
                "defaultEntry=\(defaultEntry.entryRelativePath)",
                "defaultEntryExists=\(defaultEntryExists)",
                "fileEnumerationError=\(error.localizedDescription)"
            ].joined(separator: ", ")
        }
    }

    func needsResourcePackageDownload(for metadata: WebPageResourceMetadataRecord) -> Bool {
        guard !metadata.isEffectivelyDeleted,
              metadata.page != nil,
              let page = page(withID: metadata.projectID) else {
            return false
        }

        if page.lastLoadStatus.isCloudPackageUnavailable ||
            page.lastLoadStatus == .missing ||
            page.resolvedEntries.contains(where: {
                $0.lastLoadStatus.isCloudPackageUnavailable || $0.lastLoadStatus == .missing
            }) {
            return true
        }

        guard let remotePage = metadata.page,
              let packageHash = metadata.packageHash else {
            return false
        }

        guard let localManifest = try? resourcePackageManifest(for: page) else {
            return true
        }

        guard localManifest.packageHash != packageHash else {
            return false
        }

        return Self.metadataRevisionDate(for: remotePage) >= Self.metadataRevisionDate(for: page)
    }

    func markResourcePackageState(_ status: WebPageLoadStatus, for pageID: WebPage.ID) {
        guard status.isCloudPackageUnavailable || status == .ready,
              let index = pages.firstIndex(where: { $0.id == pageID }) else {
            return
        }

        pages[index].lastLoadStatus = status
        pages[index].entries = pages[index].resolvedEntries.map { entry in
            var nextEntry = entry
            nextEntry.lastLoadStatus = status
            return nextEntry
        }
        save()
    }

    func installResourcePackageArchive(
        at archiveURL: URL,
        manifest expectedManifest: WebPageResourcePackageManifest,
        for projectID: WebPage.ID
    ) throws {
        guard let pageIndex = pages.firstIndex(where: { $0.id == projectID }) else {
            throw WebPageLibraryError.unableToPrepareStorage
        }

        let page = pages[pageIndex]
        let destinationFolderURL = folderURL(for: page)
        let temporaryFolderURL = webPagesDirectory.appendingPathComponent(
            "\(page.folderName)-icloud-package-\(UUID().uuidString)",
            isDirectory: true
        )
        let backupFolderURL = webPagesDirectory.appendingPathComponent(
            "\(page.folderName)-icloud-backup-\(UUID().uuidString)",
            isDirectory: true
        )
        defer {
            try? fileManager.removeItem(at: temporaryFolderURL)
            try? fileManager.removeItem(at: backupFolderURL)
        }

        try ZipArchiveExtractor(
            fileManager: fileManager,
            maximumExpandedByteCount: webPageMaximumImportedFileByteCount
        ).extractArchive(at: archiveURL, to: temporaryFolderURL)

        let actualManifest = try Self.resourcePackageManifest(
            projectID: expectedManifest.projectID,
            defaultEntryRelativePath: expectedManifest.defaultEntryRelativePath,
            folderURL: temporaryFolderURL,
            fileManager: fileManager
        )

        guard actualManifest.packageHash == expectedManifest.packageHash,
              actualManifest.files == expectedManifest.files,
              actualManifest.fileCount == expectedManifest.fileCount,
              actualManifest.totalByteCount == expectedManifest.totalByteCount else {
            throw WebPageLibraryError.unableToPrepareStorage
        }
        let extractedPaths = Set(actualManifest.files.map(\.relativePath))
        guard page.resolvedEntries.allSatisfy({ entry in
            entry.source == .bundledArchiveIndex ||
                entry.source == .nativeFileIndex ||
                extractedPaths.contains(entry.entryRelativePath)
        }) else {
            throw WebPageLibraryError.missingEntryFile
        }

        if fileManager.fileExists(atPath: destinationFolderURL.path) {
            try? WebPageRuntimeStorage.copyRuntimeDirectoryIfPresent(
                from: destinationFolderURL,
                to: temporaryFolderURL,
                fileManager: fileManager
            )
            try fileManager.moveItem(at: destinationFolderURL, to: backupFolderURL)
        }

        do {
            try fileManager.moveItem(at: temporaryFolderURL, to: destinationFolderURL)
        } catch {
            if fileManager.fileExists(atPath: backupFolderURL.path),
               !fileManager.fileExists(atPath: destinationFolderURL.path) {
                try? fileManager.moveItem(at: backupFolderURL, to: destinationFolderURL)
            }
            throw error
        }

        refreshAvailability()
        markResourcePackageState(.ready, for: projectID)
    }

    func mergeResourceMetadataRecords(_ records: [WebPageResourceMetadataRecord]) -> WebPageLibraryMergeDiagnostics {
        let beforeDiagnostics = localDiagnostics()
        var changed = false
        var mergeVerdicts: [String] = []
        var fileMovementDetails: [String] = []

        let tombstones = records.compactMap { record -> WebPageDeletionTombstone? in
            guard let deletedAt = record.deletedAt else { return nil }
            return WebPageDeletionTombstone(
                pageID: record.projectID,
                deletedAt: deletedAt,
                kind: record.deleteKind
            )
        }
        if mergeDeletionTombstones(tombstones) {
            changed = true
        }

        let revisions = records.compactMap { record -> WebPageRestoreRevision? in
            guard let restoredAt = record.restoredAt else { return nil }
            return WebPageRestoreRevision(
                pageID: record.projectID,
                restoredAt: restoredAt,
                activeRevisionAt: record.activeRevisionAt ?? restoredAt
            )
        }
        if mergeRestoreRevisions(revisions) {
            changed = true
        }

        let activePagesBeforeTombstones = pages
        for page in activePagesBeforeTombstones {
            guard let tombstone = effectiveBlockingTombstone(for: page.id) else { continue }
            let moveResult = applyTombstone(tombstone, toActivePage: page)
            if moveResult.changed {
                changed = true
                fileMovementDetails.append(moveResult.detail)
                mergeVerdicts.append(
                    "\(page.id.uuidString): local active -> remote tombstone -> \(tombstone.resolvedKind == .permanent ? "permanently deleted" : "recently deleted"), reason=remote tombstone newer than local active"
                )
            }
        }

        for record in records {
            guard let incomingPage = record.page,
                  shouldAcceptCloudPage(incomingPage) else {
                continue
            }
            if mergeResourceMetadata(record) {
                changed = true
            }
        }

        refreshAvailability()
        refreshDeletedAvailability()
        refreshSafeAreaBackgrounds()
        if changed {
            sortPages()
            save()
        }

        return WebPageLibraryMergeDiagnostics(
            changed: changed,
            before: beforeDiagnostics,
            after: localDiagnostics(),
            mergeVerdicts: mergeVerdicts,
            fileMovementDetails: fileMovementDetails,
            sameContentDifferentIdentityDetails: sameContentDifferentIdentityDetails()
        )
    }

    func localStoragePayload(for page: WebPage) -> (data: Data, snapshot: WebPageLocalStorageSnapshot)? {
        let url = folderURL(for: page).appendingPathComponent(
            WebPageRuntimeStorage.localStorageRelativePath,
            isDirectory: false
        )
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder.webPageRuntimeStorageDecoder.decode(
                WebPageLocalStorageSnapshot.self,
                from: data
              ),
              snapshot.schemaVersion == 1 else {
            return nil
        }
        return (data, snapshot)
    }

    @discardableResult
    func applyLocalStoragePayload(_ data: Data, to projectID: WebPage.ID) -> Bool {
        guard let page = page(withID: projectID),
              let incomingSnapshot = try? JSONDecoder.webPageRuntimeStorageDecoder.decode(
                WebPageLocalStorageSnapshot.self,
                from: data
              ),
              incomingSnapshot.schemaVersion == 1 else {
            return false
        }

        if let localSnapshot = localStoragePayload(for: page)?.snapshot,
           localSnapshot.savedAt >= incomingSnapshot.savedAt {
            return false
        }

        do {
            let url = folderURL(for: page).appendingPathComponent(
                WebPageRuntimeStorage.localStorageRelativePath,
                isDirectory: false
            )
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func applyActivityLastOpenedAt(_ lastOpenedAt: Date, to projectID: WebPage.ID) -> Bool {
        guard let index = pages.firstIndex(where: { $0.id == projectID }),
              pages[index].lastOpenedAt < lastOpenedAt else {
            return false
        }

        pages[index].lastOpenedAt = lastOpenedAt
        pages[index].entries = pages[index].resolvedEntries.map { entry in
            var nextEntry = entry
            nextEntry.lastOpenedAt = max(nextEntry.lastOpenedAt, lastOpenedAt)
            return nextEntry
        }
        save()
        return true
    }

    func makeCloudSnapshot(
        exportedAt: Date = .now,
        preservingRemote remoteSnapshot: WebPageLibraryCloudSnapshot? = nil
    ) -> WebPageLibraryCloudSnapshot {
        let snapshotPages = pages.compactMap { page -> WebPageCloudSnapshotPage? in
            let url = entryURL(for: page)
            let defaultEntry = defaultEntry(for: page)
            let htmlData: Data
            if defaultEntry.source == .bundledArchiveIndex || defaultEntry.source == .nativeFileIndex {
                htmlData = Data(Self.bundledArchiveFallbackTemplateHTML().utf8)
            } else if let data = try? Data(contentsOf: url) {
                htmlData = data
            } else {
                return nil
            }
            let localFolderFiles = cloudFolderFiles(for: page)
            let remotePage = remoteSnapshot.flatMap {
                Self.remoteSnapshotPage(matching: page, in: $0)
            }
            let selectedFolderFiles = Self.preferredFolderFiles(
                localFolderFiles,
                for: page,
                preservingRemote: remotePage?.folderFiles
            )
            let selectedHTMLData = selectedFolderFiles == remotePage?.folderFiles ?
                remotePage?.htmlData ?? htmlData :
                htmlData
            return WebPageCloudSnapshotPage(
                page: page,
                htmlData: selectedHTMLData,
                folderFiles: selectedFolderFiles
            )
        }

        return WebPageLibraryCloudSnapshot(
            exportedAt: exportedAt,
            pages: snapshotPages,
            deletions: deletionTombstones,
            restoreRevisions: restoreRevisions
        )
    }

    private static func remoteSnapshotPage(
        matching page: WebPage,
        in snapshot: WebPageLibraryCloudSnapshot
    ) -> WebPageCloudSnapshotPage? {
        snapshot.pages.first(where: { $0.page.id == page.id })
    }

    private static func preferredFolderFiles(
        _ localFolderFiles: [WebPageCloudSnapshotFile]?,
        for page: WebPage,
        preservingRemote remoteFolderFiles: [WebPageCloudSnapshotFile]?
    ) -> [WebPageCloudSnapshotFile]? {
        guard let remoteFolderFiles, !remoteFolderFiles.isEmpty else {
            return localFolderFiles
        }
        guard let localFolderFiles, !localFolderFiles.isEmpty else {
            return remoteFolderFiles
        }

        let localComplete = folderFilesContainAllEntries(localFolderFiles, for: page)
        let remoteComplete = folderFilesContainAllEntries(remoteFolderFiles, for: page)
        let localRuntimeSavedAt = WebPageRuntimeStorage.localStorageSavedAt(in: localFolderFiles)
        let remoteRuntimeSavedAt = WebPageRuntimeStorage.localStorageSavedAt(in: remoteFolderFiles)

        if let localRuntimeSavedAt,
           let remoteRuntimeSavedAt,
           localRuntimeSavedAt != remoteRuntimeSavedAt {
            return localRuntimeSavedAt > remoteRuntimeSavedAt ? localFolderFiles : remoteFolderFiles
        }
        if localRuntimeSavedAt != nil, remoteRuntimeSavedAt == nil {
            return localFolderFiles
        }
        if localRuntimeSavedAt == nil, remoteRuntimeSavedAt != nil {
            return remoteFolderFiles
        }

        if remoteComplete && !localComplete {
            return remoteFolderFiles
        }
        if remoteComplete && localComplete && remoteFolderFiles.count > localFolderFiles.count {
            return remoteFolderFiles
        }
        if remoteFolderFiles.count > localFolderFiles.count &&
            totalByteCount(in: remoteFolderFiles) > totalByteCount(in: localFolderFiles) {
            return remoteFolderFiles
        }

        return localFolderFiles
    }

    @discardableResult
    func mergeCloudSnapshot(_ snapshot: WebPageLibraryCloudSnapshot) -> Bool {
        mergeCloudSnapshotWithDiagnostics(snapshot).changed
    }

    func mergeCloudSnapshotWithDiagnostics(_ snapshot: WebPageLibraryCloudSnapshot) -> WebPageLibraryMergeDiagnostics {
        let beforeDiagnostics = localDiagnostics()
        guard snapshot.schemaVersion == 1 else {
            return WebPageLibraryMergeDiagnostics(
                changed: false,
                before: beforeDiagnostics,
                after: localDiagnostics()
            )
        }

        var changed = false
        var mergeVerdicts: [String] = []
        var fileMovementDetails: [String] = []
        if mergeDeletionTombstones(snapshot.deletions) {
            changed = true
        }
        if mergeRestoreRevisions(snapshot.restoreRevisions) {
            changed = true
        }

        let activePagesBeforeTombstones = pages
        for page in activePagesBeforeTombstones {
            guard let tombstone = effectiveBlockingTombstone(for: page.id) else { continue }
            let moveResult = applyTombstone(tombstone, toActivePage: page)
            if moveResult.changed {
                changed = true
                fileMovementDetails.append(moveResult.detail)
                mergeVerdicts.append(
                    "\(page.id.uuidString): active -> tombstone -> \(tombstone.resolvedKind == .permanent ? "permanently deleted" : "recently deleted"), reason=tombstone newer than active/restore"
                )
            }
        }

        for snapshotPage in snapshot.pages where shouldAcceptCloudPage(snapshotPage.page) {
            if upsertCloudPage(snapshotPage) {
                changed = true
            }
        }

        refreshAvailability()
        refreshDeletedAvailability()
        refreshSafeAreaBackgrounds()
        if changed {
            sortPages()
            save()
        }
        return WebPageLibraryMergeDiagnostics(
            changed: changed,
            before: beforeDiagnostics,
            after: localDiagnostics(),
            mergeVerdicts: mergeVerdicts,
            fileMovementDetails: fileMovementDetails,
            sameContentDifferentIdentityDetails: sameContentDifferentIdentityDetails()
        )
    }

    func localDiagnostics() -> WebPageLibraryLocalDiagnostics {
        var entryCount = 0
        var fileCount = 0
        var fileByteCount = 0
        var runtimeStoragePageCount = 0
        var runtimeStorageDetails: [String] = []
        var missingEntryPageCount = 0
        var missingEntryDetails: [String] = []
        var packageStatusCounts: [String: Int] = [:]
        var cloudUnavailableDetails: [String] = []

        for page in pages {
            let entries = page.resolvedEntries
            entryCount += entries.count
            packageStatusCounts[page.lastLoadStatus.rawValue, default: 0] += 1
            if page.lastLoadStatus.isCloudPackageUnavailable || page.lastLoadStatus == .missing {
                cloudUnavailableDetails.append(
                    "\(page.title), page id=\(page.id.uuidString), status=\(page.lastLoadStatus.rawValue), \(resourcePackagePreparationDiagnostic(for: page))"
                )
            }
            let folderFiles = cloudFolderFiles(for: page) ?? []
            fileCount += folderFiles.count
            fileByteCount += Self.totalByteCount(in: folderFiles)
            if let runtimeSnapshot = WebPageRuntimeStorage.localStorageSnapshot(in: folderFiles),
               let runtimeFile = folderFiles.first(where: { $0.relativePath == WebPageRuntimeStorage.localStorageRelativePath }) {
                runtimeStoragePageCount += 1
                runtimeStorageDetails.append(
                    "\(page.title): savedAt=\(Self.iso8601String(runtimeSnapshot.savedAt)), keys=\(runtimeSnapshot.items.count), bytes=\(runtimeFile.data.count)"
                )
            }

            let filePaths = Set(folderFiles.map(\.relativePath))
            let missingEntryPaths = entries
                .filter { $0.source != .bundledArchiveIndex && $0.source != .nativeFileIndex }
                .map(\.entryRelativePath)
                .filter { !filePaths.contains($0) }
            if !missingEntryPaths.isEmpty {
                missingEntryPageCount += 1
                missingEntryDetails.append(
                    "\(page.title): \(missingEntryPaths.prefix(5).joined(separator: ", "))"
                )
            }
        }

        let recoverableFolderCount = recentlyDeletedPages.filter {
            fileManager.fileExists(atPath: recoverableFolderURL(for: $0).path)
        }.count
        let recentlyDeletedDetails = recentlyDeletedPages.prefix(10).map(deletedDiagnosticLine)
        let tombstoneDetails = deletionTombstones
            .sorted { $0.deletedAt > $1.deletedAt }
            .prefix(10)
            .map(tombstoneDiagnosticLine)
        let restoreRevisionDetails = restoreRevisions
            .sorted { $0.restoredAt > $1.restoredAt }
            .prefix(10)
            .map(restoreRevisionDiagnosticLine)
        let anomalyDetails = deletionAnomalyDetails()

        return WebPageLibraryLocalDiagnostics(
            pageCount: pages.count,
            recentlyDeletedPageCount: recentlyDeletedPages.count,
            recoverableFolderCount: recoverableFolderCount,
            deletionTombstoneCount: deletionTombstones.count,
            restoreRevisionCount: restoreRevisions.count,
            permanentDeletionTombstoneCount: deletionTombstones.filter { $0.resolvedKind == .permanent }.count,
            entryCount: entryCount,
            fileCount: fileCount,
            fileByteCount: fileByteCount,
            runtimeStoragePageCount: runtimeStoragePageCount,
            runtimeStorageDetails: runtimeStorageDetails,
            missingEntryPageCount: missingEntryPageCount,
            missingEntryDetails: missingEntryDetails,
            packageStatusCounts: packageStatusCounts,
            cloudUnavailableDetails: cloudUnavailableDetails,
            recentlyDeletedDetails: recentlyDeletedDetails,
            tombstoneDetails: tombstoneDetails,
            restoreRevisionDetails: restoreRevisionDetails,
            anomalyDetails: anomalyDetails
        )
    }

    private func update(
        _ id: WebPage.ID,
        shouldRebuildSearchIndex: Bool = true,
        mutate: (inout WebPage) -> Void
    ) {
        guard let index = pages.firstIndex(where: { $0.id == id }) else { return }
        mutate(&pages[index])
        sortPages()
        save(shouldRebuildSearchIndex: shouldRebuildSearchIndex)
    }

    private func mergeResourceMetadata(_ record: WebPageResourceMetadataRecord) -> Bool {
        guard var incomingPage = record.page else { return false }
        incomingPage.folderName = incomingPage.folderName.isEmpty ? incomingPage.id.uuidString : incomingPage.folderName
        incomingPage.entryRelativePath = incomingPage.entryRelativePath.isEmpty ? "index.html" : incomingPage.entryRelativePath

        if let index = pages.firstIndex(where: { $0.id == incomingPage.id }) {
            var changed = false
            let localPage = pages[index]
            let incomingIcon = incomingPage.projectIcon
            let localIconBeforeMerge = localPage.projectIcon
            var didAcceptIncomingIcon = false
            let shouldUseIncomingMetadata = Self.metadataRevisionDate(for: incomingPage) >
                Self.metadataRevisionDate(for: localPage)

            if shouldUseIncomingMetadata {
                let mergedIcon = Self.mergedProjectIcon(
                    local: localPage.projectIcon,
                    incoming: incomingPage.projectIcon
                )
                incomingPage.folderName = localPage.folderName
                incomingPage.lastOpenedAt = max(localPage.lastOpenedAt, incomingPage.lastOpenedAt)
                incomingPage.lastLoadStatus = localPage.lastLoadStatus
                incomingPage.projectIcon = mergedIcon
                didAcceptIncomingIcon = incomingIcon != nil &&
                    incomingIcon == mergedIcon &&
                    incomingIcon != localIconBeforeMerge
                incomingPage.entries = incomingPage.resolvedEntries.map { incomingEntry in
                    var entry = incomingEntry
                    if let localEntry = localPage.resolvedEntries.first(where: {
                        $0.entryRelativePath == incomingEntry.entryRelativePath
                    }) {
                        entry.id = localEntry.id
                        entry.lastOpenedAt = max(localEntry.lastOpenedAt, incomingEntry.lastOpenedAt)
                        entry.lastLoadStatus = localEntry.lastLoadStatus
                    } else if !entryExists(for: localPage, entry: incomingEntry) {
                        entry.lastLoadStatus = .metadataOnly
                    }
                    return entry
                }
                pages[index] = incomingPage
                changed = true
            } else {
                let iconBeforeMerge = pages[index].projectIcon
                if mergeCloudEntryMetadata(from: incomingPage, intoPageAt: index) {
                    changed = true
                }
                didAcceptIncomingIcon = incomingIcon != nil &&
                    pages[index].projectIcon == incomingIcon &&
                    iconBeforeMerge != incomingIcon
            }

            if let iconData = record.iconData,
               Self.canWriteIncomingProjectIconData(
                    from: record.page?.projectIcon,
                    into: pages[index].projectIcon
               ),
               (didAcceptIncomingIcon || !projectIconFileExists(forPageAt: index)),
               writeResourceProjectIconData(iconData, forPageAt: index) {
                Self.cleanupProjectIconFiles(
                    in: folderURL(for: pages[index]),
                    keeping: pages[index].projectIcon?.fileName,
                    fileManager: fileManager
                )
                changed = true
            }

            return changed
        }

        if pages.contains(where: { $0.title == incomingPage.title }) {
            incomingPage.title = uniqueTitle(for: incomingPage.title)
        }
        incomingPage.folderName = uniqueActiveFolderName(for: incomingPage.folderName)
        incomingPage.lastLoadStatus = .metadataOnly
        incomingPage.entries = incomingPage.resolvedEntries.map { entry in
            var nextEntry = entry
            nextEntry.lastLoadStatus = .metadataOnly
            return nextEntry
        }
        pages.append(incomingPage)
        if let iconData = record.iconData,
           let index = pages.firstIndex(where: { $0.id == incomingPage.id }) {
            _ = writeResourceProjectIconData(iconData, forPageAt: index)
        }
        return true
    }

    private func writeResourceProjectIconData(_ data: Data, forPageAt index: Int) -> Bool {
        guard pages.indices.contains(index),
              let projectIcon = pages[index].projectIcon else {
            return false
        }

        do {
            let iconURL = folderURL(for: pages[index]).appendingPathComponent(
                projectIcon.fileName,
                isDirectory: false
            )
            try fileManager.createDirectory(
                at: iconURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if let existingData = try? Data(contentsOf: iconURL), existingData == data {
                return false
            }
            try data.write(to: iconURL, options: [.atomic])
            Self.cleanupProjectIconFiles(
                in: folderURL(for: pages[index]),
                keeping: projectIcon.fileName,
                fileManager: fileManager
            )
            return true
        } catch {
            return false
        }
    }

    private func projectIconFileExists(forPageAt index: Int) -> Bool {
        guard pages.indices.contains(index),
              let projectIcon = pages[index].projectIcon else {
            return false
        }

        let iconURL = folderURL(for: pages[index]).appendingPathComponent(
            projectIcon.fileName,
            isDirectory: false
        )
        return fileManager.fileExists(atPath: iconURL.path)
    }

    private func setCustomProjectIcon(for page: WebPage, image: UIImage) -> Bool {
        guard let index = pages.firstIndex(where: { $0.id == page.id }) else {
            return false
        }

        do {
            let folderURL = folderURL(for: pages[index])
            let updatedAt = Date()
            let fileName = try Self.writeNormalizedProjectIcon(
                image,
                in: folderURL,
                fileManager: fileManager,
                updatedAt: updatedAt
            )
            update(page.id, shouldRebuildSearchIndex: false) { item in
                item.projectIcon = WebPageProjectIcon(
                    source: .custom,
                    fileName: fileName,
                    updatedAt: updatedAt
                )
                item.updatedAt = updatedAt
            }
            Self.cleanupProjectIconFiles(
                in: folderURL,
                keeping: fileName,
                fileManager: fileManager
            )
            return true
        } catch {
            return false
        }
    }

    func refreshAvailability() {
        var changed = false
        for index in pages.indices {
            var entries = pages[index].resolvedEntries
            var hasReadyEntry = false
            var packageUnavailableStatus: WebPageLoadStatus?

            for entryIndex in entries.indices {
                let currentStatus = entries[entryIndex].lastLoadStatus
                let exists = currentStatus.isCloudPackageUnavailable ? false : entryExists(
                    for: pages[index],
                    entry: entries[entryIndex]
                )
                let nextStatus: WebPageLoadStatus
                if exists {
                    nextStatus = .ready
                } else if currentStatus.isCloudPackageUnavailable {
                    nextStatus = currentStatus
                    packageUnavailableStatus = packageUnavailableStatus ?? currentStatus
                } else {
                    nextStatus = .missing
                }
                hasReadyEntry = hasReadyEntry || exists
                if entries[entryIndex].lastLoadStatus != nextStatus {
                    entries[entryIndex].lastLoadStatus = nextStatus
                    changed = true
                }
            }

            if pages[index].entries ?? [] != entries {
                pages[index].entries = entries
                changed = true
            }

            let nextProjectStatus: WebPageLoadStatus = hasReadyEntry ? .ready : (packageUnavailableStatus ?? .missing)
            if pages[index].lastLoadStatus != nextProjectStatus {
                pages[index].lastLoadStatus = nextProjectStatus
                changed = true
            }
        }
        if changed {
            save(shouldRebuildSearchIndex: false)
        }
    }

    private func refreshDeletedAvailability() {
        var changed = false
        for index in recentlyDeletedPages.indices {
            var page = recentlyDeletedPages[index].page
            var entries = page.resolvedEntries
            var hasReadyEntry = false

            for entryIndex in entries.indices {
                let exists = entryExists(for: recentlyDeletedPages[index], entry: entries[entryIndex])
                let nextStatus: WebPageLoadStatus = exists ? .ready : .missing
                hasReadyEntry = hasReadyEntry || exists
                if entries[entryIndex].lastLoadStatus != nextStatus {
                    entries[entryIndex].lastLoadStatus = nextStatus
                    changed = true
                }
            }

            if page.entries ?? [] != entries {
                page.entries = entries
                changed = true
            }

            let nextProjectStatus: WebPageLoadStatus = hasReadyEntry ? .ready : .missing
            if page.lastLoadStatus != nextProjectStatus {
                page.lastLoadStatus = nextProjectStatus
                changed = true
            }

            if recentlyDeletedPages[index].page != page {
                recentlyDeletedPages[index].page = page
                changed = true
            }
        }
        if changed {
            save(shouldRebuildSearchIndex: false)
        }
    }

    private func normalizeEntryOrdering() {
        var changed = false
        for index in pages.indices {
            guard let entries = pages[index].entries, !entries.isEmpty else { continue }
            let sortedEntries = Self.sortedEntriesForDisplay(entries)
            if entries != sortedEntries {
                pages[index].entries = sortedEntries
                changed = true
            }
        }
        if changed {
            save(shouldRebuildSearchIndex: false)
        }
    }

    private func normalizeRecentlyDeleted() {
        var changed = false
        for index in recentlyDeletedPages.indices {
            guard let entries = recentlyDeletedPages[index].page.entries, !entries.isEmpty else { continue }
            let sortedEntries = Self.sortedEntriesForDisplay(entries)
            if entries != sortedEntries {
                recentlyDeletedPages[index].page.entries = sortedEntries
                changed = true
            }
        }
        sortRecentlyDeletedPages()
        if changed {
            save(shouldRebuildSearchIndex: false)
        }
    }

    private func backfillContentHashes() {
        var changed = false
        for index in pages.indices where pages[index].contentSHA256 == nil {
            let entryURL = entryURL(for: pages[index])
            guard fileManager.fileExists(atPath: entryURL.path),
                  let contentSHA256 = try? Self.sha256HexDigest(for: entryURL) else {
                continue
            }
            pages[index].contentSHA256 = contentSHA256
            changed = true
        }
        if changed {
            save(shouldRebuildSearchIndex: false)
        }
    }

    private func mergeDuplicateContentPages() {
        var keptHashes = Set<String>()
        var duplicateIDs = Set<WebPage.ID>()
        var duplicatePages: [WebPage] = []

        sortPages()
        for page in pages {
            guard let contentSHA256 = page.contentSHA256 else { continue }
            if keptHashes.contains(contentSHA256) {
                duplicateIDs.insert(page.id)
                duplicatePages.append(page)
            } else {
                keptHashes.insert(contentSHA256)
            }
        }

        guard !duplicateIDs.isEmpty else { return }

        pages.removeAll { duplicateIDs.contains($0.id) }
        for duplicatePage in duplicatePages {
            try? fileManager.removeItem(at: folderURL(for: duplicatePage))
        }
        save()
    }

    private func refreshSafeAreaBackgrounds() {
        var changed = false

        for index in pages.indices {
            let pageFolderURL = folderURL(for: pages[index])
            var entries = pages[index].resolvedEntries
            let hasMissingEntryBackground = entries.contains { entry in
                entry.safeAreaTopColor == nil || entry.safeAreaBottomColor == nil
            }
            let hasMissingProjectBackground = pages[index].safeAreaTopColor == nil ||
                pages[index].safeAreaBottomColor == nil
            guard hasMissingEntryBackground || hasMissingProjectBackground else {
                continue
            }

            for entryIndex in entries.indices {
                guard entries[entryIndex].safeAreaTopColor == nil ||
                    entries[entryIndex].safeAreaBottomColor == nil else {
                    continue
                }

                let entryURL = entryURL(for: pages[index], entry: entries[entryIndex])
                guard let htmlContent = Self.htmlContent(
                    for: entries[entryIndex],
                    in: pageFolderURL,
                    fileManager: fileManager
                ) else {
                    continue
                }

                let (topBackground, bottomBackground) = BackgroundColorExtractor.extractColors(
                    from: htmlContent,
                    htmlFileURL: entryURL,
                    projectFolderURL: pageFolderURL,
                    fileManager: fileManager
                )
                if entries[entryIndex].safeAreaTopColor != topBackground ||
                    entries[entryIndex].safeAreaBottomColor != bottomBackground {
                    entries[entryIndex].safeAreaTopColor = topBackground
                    entries[entryIndex].safeAreaBottomColor = bottomBackground
                    changed = true
                }
            }

            if pages[index].entries ?? [] != entries {
                pages[index].entries = entries
                let defaultEntry = pages[index].defaultEntryID.flatMap { entryID in
                    entries.first { $0.id == entryID }
                } ?? entries[0]
                pages[index].safeAreaTopColor = defaultEntry.safeAreaTopColor
                pages[index].safeAreaBottomColor = defaultEntry.safeAreaBottomColor
                changed = true
            }

            if let defaultEntry = pages[index].defaultEntryID.flatMap({ entryID in
                entries.first { $0.id == entryID }
            }) ?? entries.first {
                if pages[index].safeAreaTopColor == nil {
                    pages[index].safeAreaTopColor = defaultEntry.safeAreaTopColor
                    changed = true
                }
                if pages[index].safeAreaBottomColor == nil {
                    pages[index].safeAreaBottomColor = defaultEntry.safeAreaBottomColor
                    changed = true
                }
            }
        }

        if changed {
            save(shouldRebuildSearchIndex: false)
        }
    }

    private func refreshAutomaticProjectIcon(forPageAt index: Int, htmlContent: String? = nil) {
        guard pages.indices.contains(index),
              pages[index].projectIcon?.source != .custom else {
            return
        }

        let page = pages[index]
        let entry = defaultEntry(for: page)
        let pageFolderURL = folderURL(for: page)
        let icon: WebPageProjectIcon?
        if page.resolvedProjectKind == .html ||
            (page.resolvedProjectKind == .singleFile && page.singleFileFormat == .html) {
            let content = htmlContent ?? Self.htmlContent(
                for: entry,
                in: pageFolderURL,
                fileManager: fileManager
            )
            guard let content else { return }
            icon = Self.generatedProjectIcon(
                from: content,
                entryRelativePath: entry.entryRelativePath,
                folderURL: pageFolderURL,
                fileManager: fileManager,
                existingIcon: pages[index].projectIcon
            )
        } else if page.resolvedProjectKind == .singleFile {
            icon = Self.generatedSingleFileProjectIcon(
                format: page.singleFileFormat ?? WebPageSingleFileFormat.format(
                    for: pageFolderURL.appendingPathComponent(entry.entryRelativePath, isDirectory: false)
                ),
                in: pageFolderURL,
                fileManager: fileManager,
                existingIcon: pages[index].projectIcon
            )
        } else {
            icon = Self.generatedProjectImageIcon(
                in: pageFolderURL,
                fileManager: fileManager,
                existingIcon: pages[index].projectIcon
            )
        }
        if pages[index].projectIcon != icon {
            pages[index].projectIcon = icon
            pages[index].updatedAt = icon?.updatedAt ?? Date()
            Self.cleanupProjectIconFiles(
                in: pageFolderURL,
                keeping: icon?.fileName,
                fileManager: fileManager
            )
        }
    }

    private func restoreEntryIfNeeded(for page: WebPage, from sourceURL: URL) throws {
        let entryURL = entryURL(for: page)
        guard !fileManager.fileExists(atPath: entryURL.path) else { return }

        try fileManager.createDirectory(
            at: entryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.copyItem(at: sourceURL, to: entryURL)
    }

    private func restoreSingleFileProjectIfNeeded(
        forPageAt index: Int,
        from sourceURL: URL,
        format: WebPageSingleFileFormat
    ) throws {
        guard pages.indices.contains(index) else { return }
        let folderURL = folderURL(for: pages[index])
        let files = Self.archiveProjectFiles(in: folderURL, fileManager: fileManager)

        let relativePath: String
        if files.count == 1 {
            relativePath = files[0].relativePath
        } else {
            relativePath = Self.safeImportedFileName(from: sourceURL)
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
            let destinationURL = folderURL.appendingPathComponent(relativePath, isDirectory: false)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }

        let entry = Self.singleFileEntry(
            id: pages[index].defaultEntryID ?? pages[index].id,
            title: Self.fileProjectTitle(from: sourceURL),
            relativePath: relativePath,
            openedAt: Date()
        )
        upsertEntries([entry], forPageAt: index)
        pages[index].entryRelativePath = relativePath
        pages[index].defaultEntryID = entry.id
        pages[index].singleFileFormat = format
    }

    private func restoreArchiveFolder(for page: WebPage, from sourceURL: URL) throws {
        let folderURL = folderURL(for: page)
        let temporaryFolderURL = webPagesDirectory.appendingPathComponent(
            "\(page.folderName)-restore-\(UUID().uuidString)",
            isDirectory: true
        )
        defer {
            try? fileManager.removeItem(at: temporaryFolderURL)
        }

        do {
            try ZipArchiveExtractor(
                fileManager: fileManager,
                maximumExpandedByteCount: webPageMaximumImportedFileByteCount
            ).extractArchive(at: sourceURL, to: temporaryFolderURL)
        } catch ZipArchiveExtractorError.archiveTooLarge {
            throw WebPageLibraryError.importFileTooLarge
        } catch {
            throw WebPageLibraryError.unableToExtractArchive
        }

        if Self.preparedSingleFileProject(
            in: temporaryFolderURL,
            openedAt: Date(),
            entryID: page.defaultEntryID ?? page.id,
            fileManager: fileManager
        ) != nil {
            try? WebPageRuntimeStorage.copyRuntimeDirectoryIfPresent(
                from: folderURL,
                to: temporaryFolderURL,
                fileManager: fileManager
            )
            try? fileManager.removeItem(at: folderURL)
            try fileManager.moveItem(at: temporaryFolderURL, to: folderURL)
            return
        }

        let entries: [WebPageEntry]
        do {
            entries = try Self.htmlEntries(
                in: temporaryFolderURL,
                openedAt: Date(),
                fallbackArchiveName: page.sourceFileName ?? page.title,
                fileManager: fileManager
            )
        } catch {
            throw WebPageLibraryError.missingEntryFile
        }

        guard !entries.isEmpty else {
            throw WebPageLibraryError.missingEntryFile
        }

        try? WebPageRuntimeStorage.copyRuntimeDirectoryIfPresent(
            from: folderURL,
            to: temporaryFolderURL,
            fileManager: fileManager
        )
        try? fileManager.removeItem(at: folderURL)
        try fileManager.moveItem(at: temporaryFolderURL, to: folderURL)
    }

    private func upsertCloudPage(_ snapshotPage: WebPageCloudSnapshotPage) -> Bool {
        var incomingPage = snapshotPage.page
        if let deletedIndex = recentlyDeletedPages.firstIndex(where: { $0.id == incomingPage.id }) {
            let deletedPage = recentlyDeletedPages.remove(at: deletedIndex)
            try? fileManager.removeItem(at: recoverableFolderURL(for: deletedPage))
        }

        if incomingPage.folderName.isEmpty {
            incomingPage.folderName = incomingPage.id.uuidString
        }
        if incomingPage.entryRelativePath.isEmpty {
            incomingPage.entryRelativePath = "index.html"
        }

        if let index = pages.firstIndex(where: { $0.id == incomingPage.id }) {
            var changed = false
            let shouldUseIncomingMetadata = Self.metadataRevisionDate(for: incomingPage) >
                Self.metadataRevisionDate(for: pages[index])
            if shouldUseIncomingMetadata && pages[index] != incomingPage {
                let localPage = pages[index]
                pages[index] = incomingPage
                _ = mergeCloudEntryMetadata(from: localPage, intoPageAt: index)
                changed = true
            } else if mergeCloudEntryMetadata(from: incomingPage, intoPageAt: index) {
                changed = true
            }

            if writeCloudFilesIfNeeded(snapshotPage, for: pages[index]) {
                pages[index].lastLoadStatus = .ready
                changed = true
            }
            return changed
        }

        if pages.contains(where: { $0.title == incomingPage.title }) {
            incomingPage.title = uniqueTitle(for: incomingPage.title)
        }

        pages.append(incomingPage)
        if !writeCloudFilesIfNeeded(snapshotPage, for: incomingPage) {
            try? writeCloudHTML(snapshotPage.htmlData, for: incomingPage)
        }
        return true
    }

    private func mergeCloudEntryMetadata(from incomingPage: WebPage, intoPageAt pageIndex: Int) -> Bool {
        var changed = false
        if let incomingIcon = incomingPage.projectIcon {
            let currentIcon = pages[pageIndex].projectIcon
            if currentIcon == nil || incomingIcon.updatedAt > (currentIcon?.updatedAt ?? .distantPast) {
                pages[pageIndex].projectIcon = incomingIcon
                pages[pageIndex].updatedAt = max(pages[pageIndex].updatedAt ?? .distantPast, incomingIcon.updatedAt)
                changed = true
            }
        }

        let incomingEntries = incomingPage.resolvedEntries
        guard !incomingEntries.isEmpty else { return changed }

        let existingEntries = pages[pageIndex].resolvedEntries
        var mergedEntries = existingEntries

        for incomingEntry in incomingEntries {
            if let existingIndex = mergedEntries.firstIndex(where: {
                $0.entryRelativePath == incomingEntry.entryRelativePath
            }) {
                var mergedEntry = incomingEntry
                mergedEntry.id = mergedEntries[existingIndex].id
                mergedEntry.title = mergedEntries[existingIndex].title
                mergedEntry.lastOpenedAt = max(
                    mergedEntries[existingIndex].lastOpenedAt,
                    incomingEntry.lastOpenedAt
                )
                mergedEntries[existingIndex] = mergedEntry
            } else {
                mergedEntries.append(incomingEntry)
            }
        }

        mergedEntries = Self.sortedEntriesForDisplay(Self.uniquedEntryTitles(mergedEntries))
        guard pages[pageIndex].entries ?? [] != mergedEntries else {
            return changed
        }

        pages[pageIndex].entries = mergedEntries
        let currentDefaultExists = pages[pageIndex].defaultEntryID.map { defaultEntryID in
            mergedEntries.contains { $0.id == defaultEntryID }
        } ?? false

        if !currentDefaultExists {
            let incomingDefaultPath = incomingPage.defaultEntryID.flatMap { defaultEntryID in
                incomingEntries.first { $0.id == defaultEntryID }?.entryRelativePath
            } ?? incomingPage.entryRelativePath
            pages[pageIndex].defaultEntryID = mergedEntries.first {
                $0.entryRelativePath == incomingDefaultPath
            }?.id ?? Self.preferredEntry(in: mergedEntries)?.id
        }

        let defaultEntry = defaultEntry(for: pages[pageIndex])
        pages[pageIndex].entryRelativePath = defaultEntry.entryRelativePath
        pages[pageIndex].safeAreaTopColor = defaultEntry.safeAreaTopColor
        pages[pageIndex].safeAreaBottomColor = defaultEntry.safeAreaBottomColor
        return true
    }

    private static func mergedProjectIcon(
        local: WebPageProjectIcon?,
        incoming: WebPageProjectIcon?
    ) -> WebPageProjectIcon? {
        guard let local else { return incoming }
        guard let incoming else { return local }

        if incoming.updatedAt > local.updatedAt {
            return incoming
        }
        return local
    }

    private static func canWriteIncomingProjectIconData(
        from incomingIcon: WebPageProjectIcon?,
        into currentIcon: WebPageProjectIcon?
    ) -> Bool {
        guard let incomingIcon,
              let currentIcon else {
            return false
        }

        return incomingIcon == currentIcon
    }

    private static func resourcePackageManifest(
        projectID: WebPage.ID,
        defaultEntryRelativePath: String,
        folderURL: URL,
        fileManager: FileManager
    ) throws -> WebPageResourcePackageManifest {
        let paths = try ZipArchiveWriter(fileManager: fileManager).regularFileRelativePaths(
            in: folderURL,
            excluding: isResourcePackageExcludedPath
        )
        guard !paths.isEmpty else {
            throw WebPageLibraryError.unableToPrepareStorage
        }

        var files: [WebPageResourcePackageManifestFile] = []
        var totalByteCount: Int64 = 0
        for path in paths {
            let safePath = try safeStoredRelativePath(path)
            let fileURL = folderURL.appendingPathComponent(safePath, isDirectory: false)
            let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
            let byteCount = Int64(values.fileSize ?? 0)
            totalByteCount += byteCount
            guard totalByteCount <= webPageMaximumSnapshotFolderByteCount else {
                throw WebPageLibraryError.importFileTooLarge
            }
            files.append(
                WebPageResourcePackageManifestFile(
                    relativePath: safePath,
                    byteCount: byteCount,
                    sha256: try sha256HexDigest(for: fileURL)
                )
            )
        }

        let sortedFiles = files.sorted {
            $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
        }
        return WebPageResourcePackageManifest(
            schemaVersion: 1,
            projectID: projectID,
            packageHash: resourcePackageHash(for: sortedFiles),
            defaultEntryRelativePath: defaultEntryRelativePath,
            fileCount: sortedFiles.count,
            totalByteCount: totalByteCount,
            files: sortedFiles
        )
    }

    private static func isResourcePackageExcludedPath(_ relativePath: String) -> Bool {
        isAppManagedFallbackPath(relativePath) ||
            WebPageRuntimeStorage.isRuntimeStoragePath(relativePath)
    }

    private static func resourcePackageHash(for files: [WebPageResourcePackageManifestFile]) -> String {
        var hasher = SHA256()
        for file in files {
            hasher.update(data: Data(file.relativePath.utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: Data(String(file.byteCount).utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: Data(file.sha256.utf8))
            hasher.update(data: Data([10]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func cloudFolderFiles(for page: WebPage) -> [WebPageCloudSnapshotFile]? {
        let folderURL = folderURL(for: page)
        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: []
        ) else {
            return nil
        }

        var fileURLs: [(url: URL, relativePath: String)] = []
        var totalByteCount: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]) else {
                return nil
            }
            guard resourceValues.isRegularFile == true else {
                continue
            }
            guard let relativePath = Self.relativePath(of: fileURL, in: folderURL) else {
                return nil
            }
            totalByteCount += Int64(resourceValues.fileSize ?? 0)
            guard totalByteCount <= webPageMaximumSnapshotFolderByteCount else {
                return nil
            }
            fileURLs.append((fileURL, relativePath))
        }

        var files: [WebPageCloudSnapshotFile] = []
        for file in fileURLs {
            guard let data = try? Data(contentsOf: file.url) else {
                return nil
            }
            files.append(WebPageCloudSnapshotFile(relativePath: file.relativePath, data: data))
        }

        return files.sorted { $0.relativePath < $1.relativePath }
    }

    private static func folderFilesContainAllEntries(
        _ folderFiles: [WebPageCloudSnapshotFile],
        for page: WebPage
    ) -> Bool {
        let filePaths = Set(folderFiles.map(\.relativePath))
        return page.resolvedEntries.allSatisfy { entry in
            if entry.source == .bundledArchiveIndex || entry.source == .nativeFileIndex {
                return true
            }
            return filePaths.contains(entry.entryRelativePath)
        }
    }

    private static func totalByteCount(in folderFiles: [WebPageCloudSnapshotFile]) -> Int {
        folderFiles.reduce(0) { $0 + $1.data.count }
    }

    private static func iso8601String(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func writeCloudFilesIfNeeded(_ snapshotPage: WebPageCloudSnapshotPage, for page: WebPage) -> Bool {
        guard let folderFiles = snapshotPage.folderFiles, !folderFiles.isEmpty else {
            return writeCloudHTMLIfNeeded(snapshotPage.htmlData, for: page)
        }

        do {
            guard let existingFiles = cloudFolderFiles(for: page) else {
                try writeCloudFolderFiles(folderFiles, for: page)
                return true
            }
            if existingFiles == folderFiles {
                return false
            }
            if Self.shouldPreserveLocalFolderFiles(existingFiles, overIncoming: folderFiles, for: page) {
                return false
            }
            try writeCloudFolderFiles(folderFiles, for: page)
            return true
        } catch {
            return false
        }
    }

    private static func shouldPreserveLocalFolderFiles(
        _ localFolderFiles: [WebPageCloudSnapshotFile],
        overIncoming incomingFolderFiles: [WebPageCloudSnapshotFile],
        for page: WebPage
    ) -> Bool {
        guard !localFolderFiles.isEmpty else {
            return false
        }
        let localComplete = folderFilesContainAllEntries(localFolderFiles, for: page)
        let incomingComplete = folderFilesContainAllEntries(incomingFolderFiles, for: page)
        let localRuntimeSavedAt = WebPageRuntimeStorage.localStorageSavedAt(in: localFolderFiles)
        let incomingRuntimeSavedAt = WebPageRuntimeStorage.localStorageSavedAt(in: incomingFolderFiles)

        if let localRuntimeSavedAt,
           let incomingRuntimeSavedAt,
           localRuntimeSavedAt != incomingRuntimeSavedAt {
            return localRuntimeSavedAt > incomingRuntimeSavedAt
        }
        if localRuntimeSavedAt != nil, incomingRuntimeSavedAt == nil {
            return true
        }

        if localComplete && !incomingComplete {
            return true
        }
        if localComplete && incomingComplete && localFolderFiles.count > incomingFolderFiles.count {
            return true
        }
        return localFolderFiles.count > incomingFolderFiles.count &&
            totalByteCount(in: localFolderFiles) > totalByteCount(in: incomingFolderFiles)
    }

    private func writeCloudFolderFiles(_ folderFiles: [WebPageCloudSnapshotFile], for page: WebPage) throws {
        let folderURL = folderURL(for: page)
        try? fileManager.removeItem(at: folderURL)
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)

        for file in folderFiles {
            let relativePath = try Self.safeStoredRelativePath(file.relativePath)
            let destinationURL = folderURL.appendingPathComponent(relativePath, isDirectory: false)
            guard Self.isDescendant(destinationURL, of: folderURL) else {
                throw WebPageLibraryError.unableToPrepareStorage
            }
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try file.data.write(to: destinationURL, options: [.atomic])
        }
    }

    private func writeCloudHTMLIfNeeded(_ htmlData: Data, for page: WebPage) -> Bool {
        let url = entryURL(for: page)
        if let existingData = try? Data(contentsOf: url), existingData == htmlData {
            return false
        }
        do {
            try writeCloudHTML(htmlData, for: page)
            return true
        } catch {
            return false
        }
    }

    private func writeCloudHTML(_ htmlData: Data, for page: WebPage) throws {
        let url = entryURL(for: page)
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try htmlData.write(to: url, options: [.atomic])
    }

    private func recordDeletion(for page: WebPage, at deletedAt: Date = .now, kind: WebPageDeletionKind = .soft) {
        upsertDeletionTombstone(
            WebPageDeletionTombstone(pageID: page.id, deletedAt: deletedAt, kind: kind)
        )
    }

    @discardableResult
    private func mergeDeletionTombstones(_ incoming: [WebPageDeletionTombstone]) -> Bool {
        var changed = false
        for tombstone in incoming {
            if upsertDeletionTombstone(tombstone) {
                changed = true
            }
        }
        return changed
    }

    @discardableResult
    private func upsertDeletionTombstone(_ tombstone: WebPageDeletionTombstone) -> Bool {
        if let index = deletionTombstones.firstIndex(where: { $0.pageID == tombstone.pageID }) {
            guard deletionTombstones[index].deletedAt < tombstone.deletedAt else { return false }
            deletionTombstones[index] = tombstone
            return true
        }
        deletionTombstones.append(tombstone)
        return true
    }

    @discardableResult
    private func mergeRestoreRevisions(_ incoming: [WebPageRestoreRevision]) -> Bool {
        var changed = false
        for revision in incoming {
            if upsertRestoreRevision(revision) {
                changed = true
            }
        }
        return changed
    }

    @discardableResult
    private func upsertRestoreRevision(_ revision: WebPageRestoreRevision) -> Bool {
        if let index = restoreRevisions.firstIndex(where: { $0.pageID == revision.pageID }) {
            guard restoreRevisions[index].restoredAt < revision.restoredAt else { return false }
            restoreRevisions[index] = revision
            return true
        }
        restoreRevisions.append(revision)
        return true
    }

    private func shouldAcceptCloudPage(_ page: WebPage) -> Bool {
        effectiveBlockingTombstone(for: page.id) == nil
    }

    private func effectiveBlockingTombstone(for pageID: WebPage.ID) -> WebPageDeletionTombstone? {
        guard let tombstone = deletionTombstones.first(where: { $0.pageID == pageID }) else {
            return nil
        }
        let restoreRevision = restoreRevisions.first { $0.pageID == pageID }
        if let restoreRevision, restoreRevision.restoredAt > tombstone.deletedAt {
            return nil
        }
        return tombstone
    }

    private func applyTombstone(
        _ tombstone: WebPageDeletionTombstone,
        toActivePage page: WebPage
    ) -> (changed: Bool, detail: String) {
        guard let index = pages.firstIndex(where: { $0.id == page.id }) else {
            return (false, "\(page.title): already inactive")
        }

        var removedPage = pages.remove(at: index)
        removedPage.updatedAt = tombstone.deletedAt

        if tombstone.resolvedKind == .permanent {
            try? fileManager.removeItem(at: folderURL(for: page))
            return (true, "\(page.title) (\(page.id.uuidString)): active -> permanently deleted")
        }

        let recoverableFolderName = uniqueRecoverableFolderName(for: removedPage.folderName)
        let sourceFolderURL = folderURL(for: page)
        let destinationFolderURL = recentlyDeletedDirectory.appendingPathComponent(
            recoverableFolderName,
            isDirectory: true
        )
        do {
            try fileManager.createDirectory(at: recentlyDeletedDirectory, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: sourceFolderURL.path) {
                try fileManager.moveItem(at: sourceFolderURL, to: destinationFolderURL)
            }
            recentlyDeletedPages.removeAll { $0.id == removedPage.id }
            recentlyDeletedPages.append(
                DeletedWebPage(
                    page: removedPage,
                    deletedAt: tombstone.deletedAt,
                    recoverableFolderName: recoverableFolderName
                )
            )
            sortRecentlyDeletedPages()
            return (true, "\(page.title) (\(page.id.uuidString)): active -> 最近删除")
        } catch {
            return (true, "\(page.title) (\(page.id.uuidString)): active removed, missing recoverable folder")
        }
    }

    private func upsertEntries(_ entries: [WebPageEntry], forPageAt pageIndex: Int) {
        let existingEntries = pages[pageIndex].resolvedEntries
        let mergedEntries = entries.map { nextEntry in
            if let existingEntry = existingEntries.first(where: { $0.entryRelativePath == nextEntry.entryRelativePath }) {
                var entry = nextEntry
                entry.id = existingEntry.id
                entry.lastOpenedAt = existingEntry.lastOpenedAt
                entry.lastLoadStatus = nextEntry.lastLoadStatus
                return entry
            }
            return nextEntry
        }

        let uniqueEntries = Self.sortedEntriesForDisplay(Self.uniquedEntryTitles(mergedEntries))
        pages[pageIndex].entries = uniqueEntries
        if pages[pageIndex].defaultEntryID == nil ||
            !uniqueEntries.contains(where: { $0.id == pages[pageIndex].defaultEntryID }) {
            pages[pageIndex].defaultEntryID = Self.preferredEntry(in: uniqueEntries)?.id
        }
        let defaultEntry = defaultEntry(for: pages[pageIndex])
        pages[pageIndex].entryRelativePath = defaultEntry.entryRelativePath
        pages[pageIndex].safeAreaTopColor = defaultEntry.safeAreaTopColor
        pages[pageIndex].safeAreaBottomColor = defaultEntry.safeAreaBottomColor
    }

    private static func updateEntry(
        _ entryID: WebPageEntry.ID,
        in page: inout WebPage,
        mutate: (inout WebPageEntry) -> Void
    ) {
        var entries = page.resolvedEntries
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        mutate(&entries[index])
        page.entries = entries
        if page.defaultEntryID == entryID {
            page.entryRelativePath = entries[index].entryRelativePath
            page.safeAreaTopColor = entries[index].safeAreaTopColor
            page.safeAreaBottomColor = entries[index].safeAreaBottomColor
        }
    }

    private func uniqueTitle(for baseTitle: String, excluding pageID: WebPage.ID? = nil) -> String {
        let existingTitles = Set(
            pages
                .filter { $0.id != pageID }
                .map(\.title)
        )
        guard existingTitles.contains(baseTitle) else {
            return baseTitle
        }

        var suffix = 2
        while existingTitles.contains("\(baseTitle) (\(suffix))") {
            suffix += 1
        }
        return "\(baseTitle) (\(suffix))"
    }

    private func uniqueActiveFolderName(for baseName: String) -> String {
        uniqueFolderName(for: baseName, in: webPagesDirectory)
    }

    private func uniqueRecoverableFolderName(for baseName: String) -> String {
        uniqueFolderName(for: baseName, in: recentlyDeletedDirectory)
    }

    private func uniqueFolderName(for baseName: String, in directoryURL: URL) -> String {
        let trimmedBaseName = baseName.isEmpty ? UUID().uuidString : baseName
        var candidate = trimmedBaseName
        var suffix = 2
        while fileManager.fileExists(atPath: directoryURL.appendingPathComponent(candidate, isDirectory: true).path) {
            candidate = "\(trimmedBaseName)-\(suffix)"
            suffix += 1
        }
        return candidate
    }

    private func sortRecentlyDeletedPages() {
        recentlyDeletedPages.sort { lhs, rhs in
            lhs.deletedAt > rhs.deletedAt
        }
    }

    private func deletedDiagnosticLine(_ deletedPage: DeletedWebPage) -> String {
        let folderURL = recoverableFolderURL(for: deletedPage)
        let folderFiles = folderFiles(in: folderURL)
        let filePaths = Set(folderFiles.map(\.relativePath))
        let missingEntries = deletedPage.page.resolvedEntries
            .map(\.entryRelativePath)
            .filter { !filePaths.contains($0) }
        let runtimeSummary: String
        if let runtimeSnapshot = WebPageRuntimeStorage.localStorageSnapshot(in: folderFiles),
           let runtimeFile = folderFiles.first(where: {
               $0.relativePath == WebPageRuntimeStorage.localStorageRelativePath
           }) {
            runtimeSummary = "cache savedAt=\(Self.iso8601String(runtimeSnapshot.savedAt)), keys=\(runtimeSnapshot.items.count), bytes=\(runtimeFile.data.count)"
        } else {
            runtimeSummary = "cache=none"
        }

        return [
            deletedPage.page.title,
            "page id=\(deletedPage.page.id.uuidString)",
            "source=\(deletedPage.page.sourceFileName ?? "-")",
            "sha=\(deletedPage.page.contentSHA256.map { String($0.prefix(12)) } ?? "-")",
            "deletedAt=\(Self.iso8601String(deletedPage.deletedAt))",
            "folder=\(deletedPage.recoverableFolderName)",
            "folderExists=\(fileManager.fileExists(atPath: folderURL.path))",
            "files=\(folderFiles.count)",
            "bytes=\(Self.totalByteCount(in: folderFiles))",
            "entriesPresent=\(missingEntries.isEmpty)",
            runtimeSummary
        ].joined(separator: ", ")
    }

    private func tombstoneDiagnosticLine(_ tombstone: WebPageDeletionTombstone) -> String {
        let hasRecoverableCopy = recentlyDeletedPages.contains { $0.id == tombstone.pageID }
        let hasActivePage = pages.contains { $0.id == tombstone.pageID }
        return [
            "page id=\(tombstone.pageID.uuidString)",
            "deletedAt=\(Self.iso8601String(tombstone.deletedAt))",
            "type=\(tombstone.resolvedKind.rawValue)",
            "localRecoverable=\(hasRecoverableCopy)",
            "remoteActiveConflict=\(hasActivePage)",
            "uploadIndex=true"
        ].joined(separator: ", ")
    }

    private func restoreRevisionDiagnosticLine(_ revision: WebPageRestoreRevision) -> String {
        let tombstone = deletionTombstones.first { $0.pageID == revision.pageID }
        let isNewerThanTombstone = tombstone.map { revision.restoredAt > $0.deletedAt } ?? true
        let willUploadPackage = pages.contains { $0.id == revision.pageID }
        return [
            "page id=\(revision.pageID.uuidString)",
            "restoredAt=\(Self.iso8601String(revision.restoredAt))",
            "activeRevisionAt=\(Self.iso8601String(revision.activeRevisionAt))",
            "newerThanTombstone=\(isNewerThanTombstone)",
            "packageUpload=\(willUploadPackage)"
        ].joined(separator: ", ")
    }

    private func deletionAnomalyDetails() -> [String] {
        var details: [String] = []
        let deletedIDs = Set(recentlyDeletedPages.map(\.id))
        let activeIDs = Set(pages.map(\.id))

        for tombstone in deletionTombstones where tombstone.resolvedKind == .soft && !deletedIDs.contains(tombstone.pageID) && !activeIDs.contains(tombstone.pageID) {
            details.append("tombstone without local delete record: \(tombstone.pageID.uuidString)")
        }
        for deletedPage in recentlyDeletedPages where !fileManager.fileExists(atPath: recoverableFolderURL(for: deletedPage).path) {
            details.append("recently deleted record missing folder: \(deletedPage.id.uuidString)")
        }
        for page in pages where page.folderName.hasPrefix("RecentlyDeleted") || fileManager.fileExists(atPath: recentlyDeletedDirectory.appendingPathComponent(page.folderName, isDirectory: true).path) {
            details.append("active record folder appears in recently deleted area: \(page.id.uuidString)")
        }
        for revision in restoreRevisions {
            guard let tombstone = deletionTombstones.first(where: { $0.pageID == revision.pageID }),
                  revision.restoredAt < tombstone.deletedAt,
                  activeIDs.contains(revision.pageID) else {
                continue
            }
            details.append("restore revision older than tombstone but active: \(revision.pageID.uuidString)")
        }
        for tombstone in deletionTombstones where tombstone.resolvedKind == .permanent && activeIDs.contains(tombstone.pageID) {
            details.append("permanent delete still active/upload candidate: \(tombstone.pageID.uuidString)")
        }
        return details
    }

    private func sameContentDifferentIdentityDetails() -> [String] {
        let grouped = Dictionary(grouping: pages.filter { $0.contentSHA256 != nil }) { page in
            page.contentSHA256 ?? ""
        }
        return grouped.values
            .filter { $0.count > 1 }
            .map { pages in
                let ids = pages.map { "\($0.title)=\($0.id.uuidString)" }.joined(separator: ", ")
                return "same content, different page id, restore kept separate: \(ids)"
            }
            .sorted()
    }

    private func folderFiles(in folderURL: URL) -> [WebPageCloudSnapshotFile] {
        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: []
        ) else {
            return []
        }

        var fileURLs: [(url: URL, relativePath: String)] = []
        var totalByteCount: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  resourceValues.isRegularFile == true,
                  let relativePath = Self.relativePath(of: fileURL, in: folderURL) else {
                continue
            }
            totalByteCount += Int64(resourceValues.fileSize ?? 0)
            guard totalByteCount <= webPageMaximumSnapshotFolderByteCount else {
                return []
            }
            fileURLs.append((fileURL, relativePath))
        }

        var files: [WebPageCloudSnapshotFile] = []
        for file in fileURLs {
            guard let data = try? Data(contentsOf: file.url) else {
                continue
            }
            files.append(WebPageCloudSnapshotFile(relativePath: file.relativePath, data: data))
        }
        return files.sorted { $0.relativePath < $1.relativePath }
    }

    private static func metadataRevisionDate(for page: WebPage) -> Date {
        max(page.updatedAt ?? .distantPast, page.lastOpenedAt)
    }

    private func load() {
        do {
            let data = try Data(contentsOf: storeURL)
            pages = try decoder.decode([WebPage].self, from: data)
            sortPages()
        } catch {
            pages = []
        }
    }

    private func loadDeletionTombstones() {
        do {
            let data = try Data(contentsOf: deletionTombstonesURL)
            deletionTombstones = try decoder.decode([WebPageDeletionTombstone].self, from: data)
        } catch {
            deletionTombstones = []
        }
    }

    private func loadRecentlyDeletedPages() {
        do {
            let data = try Data(contentsOf: recentlyDeletedStoreURL)
            recentlyDeletedPages = try decoder.decode([DeletedWebPage].self, from: data)
            sortRecentlyDeletedPages()
        } catch {
            recentlyDeletedPages = []
        }
    }

    private func loadRestoreRevisions() {
        do {
            let data = try Data(contentsOf: restoreRevisionsURL)
            restoreRevisions = try decoder.decode([WebPageRestoreRevision].self, from: data)
        } catch {
            restoreRevisions = []
        }
    }

    private func promoteStoredSingleFileProjectsIfNeeded() {
        var changed = false

        for index in pages.indices {
            let folderURL = folderURL(for: pages[index])
            if promoteStoredSingleFileProject(&pages[index], folderURL: folderURL) {
                changed = true
            }
        }

        for index in recentlyDeletedPages.indices {
            let folderURL = recoverableFolderURL(for: recentlyDeletedPages[index])
            if promoteStoredSingleFileProject(&recentlyDeletedPages[index].page, folderURL: folderURL) {
                changed = true
            }
        }

        if changed {
            sortPages()
            sortRecentlyDeletedPages()
            save(shouldRebuildSearchIndex: false)
        }
    }

    private func promoteStoredSingleFileProject(_ page: inout WebPage, folderURL: URL) -> Bool {
        guard page.resolvedProjectKind == .nativeFileArchive,
              let singleFileProject = Self.preparedSingleFileProject(
                  in: folderURL,
                  openedAt: page.lastOpenedAt,
                  entryID: page.defaultEntryID ?? page.id,
                  fileManager: fileManager
              ) else {
            return false
        }

        page.projectKind = .singleFile
        page.singleFileFormat = singleFileProject.format
        page.entryRelativePath = singleFileProject.entry.entryRelativePath
        page.entries = [singleFileProject.entry]
        page.defaultEntryID = singleFileProject.entry.id
        page.safeAreaTopColor = singleFileProject.entry.safeAreaTopColor
        page.safeAreaBottomColor = singleFileProject.entry.safeAreaBottomColor
        if page.projectIcon?.source != .custom {
            page.projectIcon = Self.generatedSingleFileProjectIcon(
                format: singleFileProject.format,
                htmlContent: singleFileProject.htmlContent,
                entryRelativePath: singleFileProject.entry.entryRelativePath,
                in: folderURL,
                fileManager: fileManager,
                existingIcon: page.projectIcon
            )
        }
        page.updatedAt = page.updatedAt ?? Date()
        return true
    }

    private func save(shouldRebuildSearchIndex: Bool = true) {
        do {
            try ensureStorage()
            let data = try encoder.encode(pages)
            try data.write(to: storeURL, options: [.atomic])
            let recentlyDeletedData = try encoder.encode(recentlyDeletedPages)
            try recentlyDeletedData.write(to: recentlyDeletedStoreURL, options: [.atomic])
            let deletionData = try encoder.encode(deletionTombstones)
            try deletionData.write(to: deletionTombstonesURL, options: [.atomic])
            let restoreData = try encoder.encode(restoreRevisions)
            try restoreData.write(to: restoreRevisionsURL, options: [.atomic])
            if shouldRebuildSearchIndex {
                scheduleSearchIndexRefresh()
                scheduleOpportunisticFullContentSearchIndexBuildIfNeeded()
            }
            refreshProjectWidgetSnapshot()
        } catch {
            assertionFailure("Failed to save web page library: \(error)")
        }
    }

    private func refreshProjectWidgetSnapshot(reloadsTimelines: Bool = true) {
        let projects = pages.map { page in
            let defaultEntry = defaultEntry(for: page)
            let loadStatus = projectWidgetLoadStatus(for: page, defaultEntry: defaultEntry)
            let iconFileName = page.projectIcon == nil ? nil : copyProjectWidgetIcon(for: page)
            let usesCustomIcon = page.projectIcon?.source == .custom && iconFileName != nil
            let safeAreaTopBackground = defaultEntry.safeAreaTopColor ?? page.safeAreaTopColor
            let isOpenable = loadStatus == .ready && entryExists(for: page, entry: defaultEntry)
            let updatedAt = max(
                page.updatedAt ?? page.lastOpenedAt,
                page.projectIcon?.updatedAt ?? .distantPast
            )

            return ProjectWidgetProject(
                id: page.id,
                title: page.title,
                kind: projectWidgetKind(for: page),
                loadStatus: loadStatus,
                isOpenable: isOpenable,
                usesCustomIcon: usesCustomIcon,
                safeAreaTopBackground: safeAreaTopBackground,
                iconFileName: iconFileName,
                fallbackSymbolName: projectWidgetFallbackSymbolName(for: page),
                updatedAt: updatedAt
            )
        }

        guard ProjectWidgetShared.writeSnapshot(
            ProjectWidgetSnapshot(updatedAt: Date(), projects: projects),
            fileManager: fileManager
        ) else {
            return
        }

        cleanupProjectWidgetIcons(keeping: Set(projects.compactMap(\.iconFileName)))

        if reloadsTimelines {
            WidgetCenter.shared.reloadTimelines(ofKind: ProjectWidgetShared.widgetKind)
        }
    }

    private func projectWidgetKind(for page: WebPage) -> ProjectWidgetProjectKind {
        switch page.resolvedProjectKind {
        case .html:
            return .html
        case .singleFile:
            return .singleFile
        case .nativeFileArchive:
            return .nativeFileArchive
        }
    }

    private func projectWidgetLoadStatus(
        for page: WebPage,
        defaultEntry: WebPageEntry
    ) -> ProjectWidgetLoadStatus {
        let status = page.opensInNativeFileViewer || page.opensInSingleFilePreview ? page.lastLoadStatus : defaultEntry.lastLoadStatus
        return ProjectWidgetLoadStatus(rawValue: status.rawValue) ?? .failed
    }

    private func projectWidgetFallbackSymbolName(for page: WebPage) -> String {
        if page.resolvedProjectKind == .singleFile {
            return projectWidgetSingleFileFallbackSymbolName(for: page.singleFileFormat)
        }

        if page.opensInNativeFileViewer {
            return "doc.fill"
        }

        if page.resolvedEntries.count > 1 {
            return "folder.fill"
        }

        return "doc.text.fill"
    }

    private func projectWidgetSingleFileFallbackSymbolName(for format: WebPageSingleFileFormat?) -> String {
        switch format {
        case .html:
            return "doc.text.fill"
        case .markdown:
            return "text.document.fill"
        case .image:
            return "photo.fill"
        case .video:
            return "film.fill"
        case .audio:
            return "waveform"
        case .pdf:
            return "doc.richtext.fill"
        case .text:
            return "doc.plaintext.fill"
        case .document, .file, nil:
            return "doc.fill"
        }
    }

    private func copyProjectWidgetIcon(for page: WebPage) -> String? {
        guard let projectIcon = page.projectIcon,
              let sourceURL = projectIconURL(for: page),
              let iconsDirectoryURL = ProjectWidgetShared.iconsDirectoryURL(fileManager: fileManager) else {
            return nil
        }

        let versionToken = Self.projectIconVersionToken(for: projectIcon.updatedAt)
        let fileName = "\(page.id.uuidString)-\(versionToken).png"
        let destinationURL = iconsDirectoryURL.appendingPathComponent(fileName, isDirectory: false)

        do {
            try fileManager.createDirectory(at: iconsDirectoryURL, withIntermediateDirectories: true)
            if let existingData = try? Data(contentsOf: destinationURL),
               let sourceData = try? Data(contentsOf: sourceURL),
               existingData == sourceData {
                return fileName
            }
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            return fileName
        } catch {
            return nil
        }
    }

    private func cleanupProjectWidgetIcons(keeping fileNames: Set<String>) {
        guard let iconsDirectoryURL = ProjectWidgetShared.iconsDirectoryURL(fileManager: fileManager),
              let contents = try? fileManager.contentsOfDirectory(
                at: iconsDirectoryURL,
                includingPropertiesForKeys: nil
              ) else {
            return
        }

        for fileURL in contents where !fileNames.contains(fileURL.lastPathComponent) {
            try? fileManager.removeItem(at: fileURL)
        }
    }

    private func loadSearchIndexOrRebuild() {
        if let savedIndex = WebPageSearchIndex.load(from: searchIndexURL, decoder: decoder) {
            searchIndex = savedIndex
            return
        }
        searchIndex = WebPageSearchIndex.build(
            pages: pages,
            folderURL: { [self] page in folderURL(for: page) },
            fileManager: fileManager,
            includeHTMLContent: false
        )
        searchIndex.save(to: searchIndexURL)
    }

    private func scheduleSearchIndexRefresh(includeHTMLContent: Bool? = nil) {
        searchIndexRefreshSequence += 1
        let refreshSequence = searchIndexRefreshSequence
        let pagesSnapshot = pages
        let pageFolders = pagesSnapshot.map { page in
            (page: page, folderURL: folderURL(for: page))
        }
        let fileManager = fileManager
        let searchIndexURL = searchIndexURL
        let shouldIncludeHTMLContent = includeHTMLContent ?? searchIndex.hasHTMLContent

        Task.detached(priority: .utility) {
            let nextIndex = WebPageSearchIndex.build(
                pageFolders: pageFolders,
                fileManager: fileManager,
                includeHTMLContent: shouldIncludeHTMLContent
            )
            let shouldSave = await MainActor.run { [weak self] in
                guard let self,
                      self.searchIndexRefreshSequence == refreshSequence else {
                    return false
                }
                self.searchIndex = nextIndex
                return true
            }
            if shouldSave {
                nextIndex.save(to: searchIndexURL)
            }
        }
    }

    private func ensureStorage() throws {
        do {
            try fileManager.createDirectory(at: webPagesDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: recentlyDeletedDirectory, withIntermediateDirectories: true)
        } catch {
            throw WebPageLibraryError.unableToPrepareStorage
        }
    }

    private func sortPages() {
        pages.sort { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.lastOpenedAt > rhs.lastOpenedAt
        }
    }

    private var applicationSupportDirectory: URL {
        let urls = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        return urls[0].appendingPathComponent("HTMLKeep", isDirectory: true)
    }

    private var webPagesDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("WebPages", isDirectory: true)
    }

    private var recentlyDeletedDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("RecentlyDeletedWebPages", isDirectory: true)
    }

    private var storeURL: URL {
        applicationSupportDirectory.appendingPathComponent("web-pages.json", isDirectory: false)
    }

    private var recentlyDeletedStoreURL: URL {
        applicationSupportDirectory.appendingPathComponent("recently-deleted-web-pages.json", isDirectory: false)
    }

    private var deletionTombstonesURL: URL {
        applicationSupportDirectory.appendingPathComponent("web-page-deletions.json", isDirectory: false)
    }

    private var restoreRevisionsURL: URL {
        applicationSupportDirectory.appendingPathComponent("web-page-restore-revisions.json", isDirectory: false)
    }

    private var searchIndexURL: URL {
        applicationSupportDirectory.appendingPathComponent("web-page-search-index.json", isDirectory: false)
    }

    private static func isSupportedHTML(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "html" || ext == "htm"
    }

    private static func isSupportedArchive(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "zip"
    }

    private static func isSupportedSource(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
        return values?.isRegularFile == true
    }

    private static func validateImportSize(of url: URL) throws {
        let byteCount = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        guard byteCount <= webPageMaximumImportedFileByteCount else {
            throw WebPageLibraryError.importFileTooLarge
        }
    }

    private static func safeImportedFileName(from url: URL) -> String {
        let fileName = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return fileName.isEmpty ? "file" : fileName
    }

    private static func fileProjectTitle(from url: URL) -> String {
        let title = url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? safeImportedFileName(from: url) : title
    }

    private static func htmlEntries(
        in folderURL: URL,
        openedAt: Date,
        fallbackArchiveName: String? = nil,
        fileManager: FileManager
    ) throws -> [WebPageEntry] {
        let htmlPaths = try htmlRelativePaths(in: folderURL, fileManager: fileManager)
        if htmlPaths.isEmpty, let fallbackArchiveName {
            let entry = try archiveFallbackEntry(
                in: folderURL,
                archiveName: fallbackArchiveName,
                openedAt: openedAt,
                fileManager: fileManager
            )
            return [entry]
        }

        guard !htmlPaths.isEmpty else {
            throw WebPageLibraryError.archiveMissingHTML
        }

        let entries = htmlPaths.map { relativePath -> WebPageEntry in
            let htmlURL = folderURL.appendingPathComponent(relativePath, isDirectory: false)
            let htmlContent = (try? String(contentsOf: htmlURL, encoding: .utf8)) ?? ""
            return htmlEntry(
                title: title(from: htmlContent, fallbackURL: htmlURL),
                relativePath: relativePath,
                htmlContent: htmlContent,
                openedAt: openedAt,
                htmlFileURL: htmlURL,
                projectFolderURL: folderURL,
                fileManager: fileManager
            )
        }

        let uniqueEntries = uniquedEntryTitles(entries)
        return sortedEntriesForDisplay(uniqueEntries)
    }

    nonisolated private static let archiveFallbackIndexDataFileName = ".htmlanywhere-file-index.json"
    nonisolated private static let archiveFallbackEntryRelativePath = ".htmlanywhere-bundled-file-list.html"

    private struct ArchiveFallbackFile {
        var relativePath: String
        var byteCount: Int64
    }

    private struct PreparedSingleFileProject {
        var file: WebPageProjectFile
        var format: WebPageSingleFileFormat
        var entry: WebPageEntry
        var htmlContent: String?
    }

    private struct ArchiveFallbackIndex: Encodable {
        var schemaVersion: Int
        var archiveName: String
        var files: [ArchiveFallbackIndexFile]
    }

    private struct ArchiveFallbackIndexFile: Encodable {
        var relativePath: String
        var href: String
        var byteCount: Int64
    }

    private static func archiveFallbackEntry(
        in folderURL: URL,
        archiveName: String,
        openedAt: Date,
        fileManager: FileManager
    ) throws -> WebPageEntry {
        try writeArchiveFallbackIndexData(
            files: archiveFallbackFiles(in: folderURL, fileManager: fileManager),
            archiveName: archiveName,
            folderURL: folderURL
        )

        let htmlContent = bundledArchiveFallbackTemplateHTML()
        let colors = BackgroundColorExtractor.extractColors(from: htmlContent)
        return WebPageEntry(
            id: UUID(),
            title: AppStrings.localized("文件清单"),
            entryRelativePath: archiveFallbackEntryRelativePath,
            source: .nativeFileIndex,
            lastOpenedAt: openedAt,
            lastLoadStatus: .ready,
            safeAreaTopColor: colors.top,
            safeAreaBottomColor: colors.bottom
        )
    }

    private static func writeArchiveFallbackIndexData(
        files: [ArchiveFallbackFile],
        archiveName: String,
        folderURL: URL
    ) throws {
        let index = ArchiveFallbackIndex(
            schemaVersion: 1,
            archiveName: archiveName,
            files: files.map { file in
                ArchiveFallbackIndexFile(
                    relativePath: file.relativePath,
                    href: percentEncodedRelativeHref(file.relativePath),
                    byteCount: file.byteCount
                )
            }
        )
        let data = try JSONEncoder().encode(index)
        let indexDataURL = folderURL.appendingPathComponent(archiveFallbackIndexDataFileName, isDirectory: false)
        try data.write(to: indexDataURL, options: [.atomic])
    }

    private static func archiveProjectFiles(
        in folderURL: URL,
        fileManager: FileManager
    ) -> [WebPageProjectFile] {
        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: []
        ) else {
            return []
        }

        var files: [WebPageProjectFile] = []
        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  resourceValues.isRegularFile == true,
                  let relativePath = relativePath(of: fileURL, in: folderURL),
                  !isAppManagedFallbackPath(relativePath) else {
                continue
            }
            let typeIdentifier = UTType(filenameExtension: fileURL.pathExtension)?.identifier
            files.append(WebPageProjectFile(
                relativePath: relativePath,
                byteCount: Int64(resourceValues.fileSize ?? 0),
                typeIdentifier: typeIdentifier
            ))
        }

        return files.sorted {
            $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
        }
    }

    private static func preparedSingleFileProject(
        in folderURL: URL,
        openedAt: Date,
        entryID: WebPageEntry.ID = UUID(),
        fileManager: FileManager
    ) -> PreparedSingleFileProject? {
        let files = archiveProjectFiles(in: folderURL, fileManager: fileManager)
        guard files.count == 1, let file = files.first else {
            return nil
        }

        let fileURL = folderURL.appendingPathComponent(file.relativePath, isDirectory: false)
        let format = WebPageSingleFileFormat.format(for: fileURL, typeIdentifier: file.typeIdentifier)
        let displayTitle: String
        let htmlContent: String?
        let topColor: String?
        let bottomColor: String?

        if format == .html, let content = try? String(contentsOf: fileURL, encoding: .utf8) {
            htmlContent = content
            displayTitle = title(from: content, fallbackURL: fileURL)
            let colors = BackgroundColorExtractor.extractColors(
                from: content,
                htmlFileURL: fileURL,
                projectFolderURL: folderURL,
                fileManager: fileManager
            )
            topColor = colors.top
            bottomColor = colors.bottom
        } else {
            htmlContent = nil
            displayTitle = fileProjectTitle(from: fileURL)
            topColor = nil
            bottomColor = nil
        }

        return PreparedSingleFileProject(
            file: file,
            format: format,
            entry: singleFileEntry(
                id: entryID,
                title: displayTitle,
                relativePath: file.relativePath,
                openedAt: openedAt,
                safeAreaTopColor: topColor,
                safeAreaBottomColor: bottomColor
            ),
            htmlContent: htmlContent
        )
    }

    private static func hasFixedResourceFiles(in folderURL: URL, fileManager: FileManager) -> Bool {
        !archiveProjectFiles(in: folderURL, fileManager: fileManager).isEmpty
    }

    private static func archiveFallbackFiles(
        in folderURL: URL,
        fileManager: FileManager
    ) -> [ArchiveFallbackFile] {
        archiveProjectFiles(in: folderURL, fileManager: fileManager).map { file in
            ArchiveFallbackFile(relativePath: file.relativePath, byteCount: file.byteCount)
        }
    }

    nonisolated private static func isAppManagedFallbackPath(_ relativePath: String) -> Bool {
        relativePath == archiveFallbackEntryRelativePath ||
            relativePath == archiveFallbackIndexDataFileName ||
            relativePath == WebPageRuntimeStorage.directoryName ||
            relativePath.hasPrefix("\(WebPageRuntimeStorage.directoryName)/")
    }

    nonisolated static func isAppManagedProjectFilePath(_ relativePath: String) -> Bool {
        isAppManagedFallbackPath(relativePath)
    }

    static func bundledArchiveFallbackTemplateURL() -> URL? {
        Bundle.main.url(forResource: "FallbackArchiveIndex", withExtension: "html")
    }

    static func bundledArchiveFallbackTemplateHTML() -> String {
        guard let templateURL = bundledArchiveFallbackTemplateURL(),
              let html = try? String(contentsOf: templateURL, encoding: .utf8) else {
            return archiveFallbackTemplateHTML
        }
        return html
    }

    static func bundledArchiveFallbackHTML(for folderURL: URL) -> String {
        let indexURL = folderURL.appendingPathComponent(archiveFallbackIndexDataFileName, isDirectory: false)
        let indexJSON = (try? String(contentsOf: indexURL, encoding: .utf8)) ?? #"{"schemaVersion":1,"archiveName":"","files":[]}"#
        let script = #"<script>window.__HTMLKeepArchiveIndex = \#(indexJSON);</script>"#
        let template = bundledArchiveFallbackTemplateHTML()
        if let headRange = template.range(of: "<head>") {
            return template.replacingCharacters(in: headRange, with: "<head>\n    \(script)")
        }
        return script + template
    }

    private static func htmlContent(
        for entry: WebPageEntry,
        in folderURL: URL,
        fileManager: FileManager
    ) -> String? {
        if entry.source == .bundledArchiveIndex || entry.source == .nativeFileIndex {
            return bundledArchiveFallbackTemplateHTML()
        }
        let entryURL = folderURL.appendingPathComponent(entry.entryRelativePath, isDirectory: false)
        return try? String(contentsOf: entryURL, encoding: .utf8)
    }

    private static func singleFileEntry(
        id: WebPageEntry.ID = UUID(),
        title: String,
        relativePath: String,
        openedAt: Date,
        safeAreaTopColor: String? = nil,
        safeAreaBottomColor: String? = nil
    ) -> WebPageEntry {
        WebPageEntry(
            id: id,
            title: title,
            entryRelativePath: relativePath,
            lastOpenedAt: openedAt,
            lastLoadStatus: .ready,
            safeAreaTopColor: safeAreaTopColor,
            safeAreaBottomColor: safeAreaBottomColor
        )
    }

    private static func percentEncodedRelativeHref(_ relativePath: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/#?%")
        return relativePath
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { component in
                String(component).addingPercentEncoding(withAllowedCharacters: allowed) ?? String(component)
            }
            .joined(separator: "/")
    }

    private static let archiveFallbackTemplateHTML = """
    <!doctype html>
    <html>
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
        <title>文件清单</title>
    </head>
    <body>
        <p>File index unavailable.</p>
    </body>
    </html>
    """

    private static func htmlEntry(
        id: WebPageEntry.ID = UUID(),
        title: String,
        relativePath: String,
        htmlContent: String,
        openedAt: Date,
        htmlFileURL: URL? = nil,
        projectFolderURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> WebPageEntry {
        let colors: (top: String, bottom: String)
        if let htmlFileURL, let projectFolderURL {
            colors = BackgroundColorExtractor.extractColors(
                from: htmlContent,
                htmlFileURL: htmlFileURL,
                projectFolderURL: projectFolderURL,
                fileManager: fileManager
            )
        } else {
            colors = BackgroundColorExtractor.extractColors(from: htmlContent)
        }
        return WebPageEntry(
            id: id,
            title: title,
            entryRelativePath: relativePath,
            lastOpenedAt: openedAt,
            lastLoadStatus: .ready,
            safeAreaTopColor: colors.top,
            safeAreaBottomColor: colors.bottom
        )
    }

    private static func htmlRelativePaths(in folderURL: URL, fileManager: FileManager) throws -> [String] {
        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        ) else {
            throw WebPageLibraryError.archiveMissingHTML
        }

        var htmlPaths: [String] = []
        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  resourceValues.isRegularFile == true,
                  isSupportedHTML(fileURL),
                  let relativePath = relativePath(of: fileURL, in: folderURL) else {
                continue
            }
            htmlPaths.append(relativePath)
        }

        return htmlPaths.sorted { lhs, rhs in
            lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

    private static func preferredEntry(in entries: [WebPageEntry]) -> WebPageEntry? {
        sortedEntriesForDisplay(entries).first
    }

    private static func uniquedEntryTitles(_ entries: [WebPageEntry]) -> [WebPageEntry] {
        var usedTitles = Set<String>()
        return entries.map { entry in
            var nextEntry = entry
            let baseTitle = nextEntry.title
            if usedTitles.contains(baseTitle) {
                var suffix = 2
                while usedTitles.contains("\(baseTitle) (\(suffix))") {
                    suffix += 1
                }
                nextEntry.title = "\(baseTitle) (\(suffix))"
            }
            usedTitles.insert(nextEntry.title)
            return nextEntry
        }
    }

    private static func sortedEntriesForDisplay(_ entries: [WebPageEntry]) -> [WebPageEntry] {
        entries.sorted { lhs, rhs in
            let lhsRank = entryLandingRank(lhs)
            let rhsRank = entryLandingRank(rhs)
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }

            let titleComparison = lhs.title.localizedStandardCompare(rhs.title)
            if titleComparison != .orderedSame {
                return titleComparison == .orderedAscending
            }

            return lhs.entryRelativePath.localizedStandardCompare(rhs.entryRelativePath) == .orderedAscending
        }
    }

    private static func entryLandingRank(_ entry: WebPageEntry) -> Int {
        let path = entry.entryRelativePath
        let fileName = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent.lowercased()
        let depth = path.split(separator: "/").count

        switch fileName {
        case "index":
            return depth == 1 ? 0 : 2 + depth
        case "default":
            return depth == 1 ? 1 : 102 + depth
        default:
            return 1_000
        }
    }

    private static func relativePath(of fileURL: URL, in folderURL: URL) -> String? {
        let rootPath = folderURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/") else {
            return nil
        }
        return String(filePath.dropFirst(rootPath.count + 1))
    }

    private static func safeStoredRelativePath(_ path: String) throws -> String {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        guard !normalized.isEmpty,
              !normalized.hasPrefix("/"),
              !normalized.contains("\0") else {
            throw WebPageLibraryError.unableToPrepareStorage
        }

        let components = normalized.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({ $0 != "." && $0 != ".." }) else {
            throw WebPageLibraryError.unableToPrepareStorage
        }

        return components.joined(separator: "/")
    }

    private static func isDescendant(_ url: URL, of rootURL: URL) -> Bool {
        let rootPath = rootURL.standardizedFileURL.path
        let candidatePath = url.standardizedFileURL.path
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }

    private static let legacyProjectIconFileName = "project-icon.png"
    private static let projectIconFileStem = "project-icon"
    private static let projectIconFileExtension = "png"

    private static func generatedProjectIcon(
        from htmlContent: String,
        entryRelativePath: String,
        folderURL: URL,
        fileManager: FileManager,
        existingIcon: WebPageProjectIcon? = nil
    ) -> WebPageProjectIcon? {
        if let imageData = preferredFaviconData(
            from: htmlContent,
            entryRelativePath: entryRelativePath,
            folderURL: folderURL
        ),
           let image = UIImage(data: imageData) {
            return normalizedProjectIcon(
                image,
                source: .favicon,
                in: folderURL,
                fileManager: fileManager,
                existingIcon: existingIcon
            )
        }

        if let image = preferredProjectImage(in: folderURL, fileManager: fileManager) {
            return normalizedProjectIcon(
                image,
                source: .image,
                in: folderURL,
                fileManager: fileManager,
                existingIcon: existingIcon
            )
        }

        cleanupProjectIconFiles(in: folderURL, keeping: nil, fileManager: fileManager)
        return nil
    }

    private static func generatedProjectImageIcon(
        in folderURL: URL,
        fileManager: FileManager,
        existingIcon: WebPageProjectIcon? = nil
    ) -> WebPageProjectIcon? {
        if let image = preferredProjectImage(in: folderURL, fileManager: fileManager) {
            return normalizedProjectIcon(
                image,
                source: .image,
                in: folderURL,
                fileManager: fileManager,
                existingIcon: existingIcon
            )
        }

        cleanupProjectIconFiles(in: folderURL, keeping: nil, fileManager: fileManager)
        return nil
    }

    private static func generatedSingleFileProjectIcon(
        format: WebPageSingleFileFormat,
        htmlContent: String? = nil,
        entryRelativePath: String? = nil,
        in folderURL: URL,
        fileManager: FileManager,
        existingIcon: WebPageProjectIcon? = nil
    ) -> WebPageProjectIcon? {
        switch format {
        case .html:
            guard let htmlContent, let entryRelativePath else { return nil }
            return generatedProjectIcon(
                from: htmlContent,
                entryRelativePath: entryRelativePath,
                folderURL: folderURL,
                fileManager: fileManager,
                existingIcon: existingIcon
            )
        case .image:
            return generatedProjectImageIcon(
                in: folderURL,
                fileManager: fileManager,
                existingIcon: existingIcon
            )
        case .markdown, .video, .audio, .pdf, .text, .document, .file:
            cleanupProjectIconFiles(in: folderURL, keeping: nil, fileManager: fileManager)
            return nil
        }
    }

    private static func normalizedProjectIcon(
        _ image: UIImage,
        source: WebPageProjectIconSource,
        in folderURL: URL,
        fileManager: FileManager,
        existingIcon: WebPageProjectIcon?
    ) -> WebPageProjectIcon? {
        guard let data = normalizedProjectIconData(from: image) else {
            return nil
        }

        if let existingIcon,
           existingIcon.source == source,
           let existingData = try? Data(
               contentsOf: folderURL.appendingPathComponent(existingIcon.fileName, isDirectory: false)
           ),
           existingData == data {
            return existingIcon
        }

        let updatedAt = Date()
        guard let fileName = try? writeNormalizedProjectIconData(
            data,
            in: folderURL,
            fileManager: fileManager,
            updatedAt: updatedAt
        ) else {
            return nil
        }

        return WebPageProjectIcon(source: source, fileName: fileName, updatedAt: updatedAt)
    }

    private static func writeNormalizedProjectIcon(
        _ image: UIImage,
        in folderURL: URL,
        fileManager: FileManager,
        updatedAt: Date
    ) throws -> String {
        guard let data = normalizedProjectIconData(from: image) else {
            throw WebPageLibraryError.unableToPrepareStorage
        }
        return try writeNormalizedProjectIconData(data, in: folderURL, fileManager: fileManager, updatedAt: updatedAt)
    }

    private static func normalizedProjectIconData(from image: UIImage) -> Data? {
        let targetSize = CGSize(width: 180, height: 180)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.pngData { _ in
            let sourceSize = image.size
            let scale = max(targetSize.width / sourceSize.width, targetSize.height / sourceSize.height)
            let drawSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
            let drawOrigin = CGPoint(
                x: (targetSize.width - drawSize.width) / 2,
                y: (targetSize.height - drawSize.height) / 2
            )
            image.draw(in: CGRect(origin: drawOrigin, size: drawSize))
        }
    }

    private static func writeNormalizedProjectIconData(
        _ data: Data,
        in folderURL: URL,
        fileManager: FileManager,
        updatedAt: Date
    ) throws -> String {
        let fileName = projectIconRelativePath(fileName: projectIconFileName(updatedAt: updatedAt))
        let iconURL = folderURL.appendingPathComponent(fileName, isDirectory: false)
        try fileManager.createDirectory(
            at: iconURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: iconURL, options: [.atomic])
        return fileName
    }

    private static func projectIconFileName(updatedAt: Date) -> String {
        "\(projectIconFileStem)-\(projectIconVersionToken(for: updatedAt)).\(projectIconFileExtension)"
    }

    private static func projectIconRelativePath(fileName: String) -> String {
        "\(WebPageRuntimeStorage.directoryName)/\(fileName)"
    }

    private static func projectIconVersionToken(for date: Date) -> String {
        String(Int64((date.timeIntervalSince1970 * 1_000_000).rounded()))
    }

    private static func cleanupProjectIconFiles(
        in folderURL: URL,
        keeping currentFileName: String?,
        fileManager: FileManager
    ) {
        let runtimeURL = folderURL.appendingPathComponent(WebPageRuntimeStorage.directoryName, isDirectory: true)
        guard let contents = try? fileManager.contentsOfDirectory(
            at: runtimeURL,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        let keepPath = currentFileName?.replacingOccurrences(of: "\\", with: "/")
        for fileURL in contents {
            let relativePath = projectIconRelativePath(fileName: fileURL.lastPathComponent)
            guard isManagedProjectIconRelativePath(relativePath),
                  relativePath != keepPath else {
                continue
            }
            try? fileManager.removeItem(at: fileURL)
        }
    }

    private static func isManagedProjectIconRelativePath(_ relativePath: String) -> Bool {
        let normalized = relativePath.replacingOccurrences(of: "\\", with: "/")
        let runtimePrefix = "\(WebPageRuntimeStorage.directoryName)/"
        guard normalized.hasPrefix(runtimePrefix) else {
            return false
        }

        let fileName = String(normalized.dropFirst(runtimePrefix.count))
        guard !fileName.contains("/") else {
            return false
        }
        return fileName == legacyProjectIconFileName ||
            (fileName.hasPrefix("\(projectIconFileStem)-") && fileName.hasSuffix(".\(projectIconFileExtension)"))
    }

    private static func preferredFaviconData(
        from htmlContent: String,
        entryRelativePath: String,
        folderURL: URL
    ) -> Data? {
        guard let headContent = firstTagContent(named: "head", in: htmlContent) else {
            return nil
        }

        let links = tagAttributes(named: "link", in: headContent)
        let appleTouchIcons = links.filter { attributes in
            relValues(in: attributes).contains { $0 == "apple-touch-icon" || $0 == "apple-touch-icon-precomposed" }
        }
        let favicons = links.filter { attributes in
            let values = relValues(in: attributes)
            return values.contains("icon") || (values.contains("shortcut") && values.contains("icon"))
        }

        for attributes in appleTouchIcons + favicons {
            if let href = attributes["href"],
               let data = imageData(for: href, entryRelativePath: entryRelativePath, folderURL: folderURL) {
                return data
            }
        }

        for attributes in links where relValues(in: attributes).contains("manifest") {
            guard let href = attributes["href"],
                  let manifestRelativePath = resolvedRelativePath(
                    for: href,
                    entryRelativePath: entryRelativePath,
                    folderURL: folderURL
                  ),
                  let manifestData = try? Data(
                    contentsOf: folderURL.appendingPathComponent(manifestRelativePath, isDirectory: false)
                  ),
                  let iconData = manifestIconData(
                    from: manifestData,
                    manifestRelativePath: manifestRelativePath,
                    folderURL: folderURL
                  ) else {
                continue
            }
            return iconData
        }

        let entryDirectory = (entryRelativePath as NSString).deletingLastPathComponent
        let fallbackNames = ["favicon.ico", "favicon.png", "favicon.jpg", "favicon.jpeg", "favicon.svg"]
        for name in fallbackNames {
            let entryRelative = entryDirectory.isEmpty || entryDirectory == "." ? name : "\(entryDirectory)/\(name)"
            if let data = imageData(for: entryRelative, entryRelativePath: entryRelativePath, folderURL: folderURL) {
                return data
            }
            if let data = imageData(for: "/\(name)", entryRelativePath: entryRelativePath, folderURL: folderURL) {
                return data
            }
        }

        return nil
    }

    private static func manifestIconData(
        from manifestData: Data,
        manifestRelativePath: String,
        folderURL: URL
    ) -> Data? {
        guard let object = try? JSONSerialization.jsonObject(with: manifestData),
              let manifest = object as? [String: Any],
              let icons = manifest["icons"] as? [[String: Any]] else {
            return nil
        }

        let sortedIcons = icons.sorted { lhs, rhs in
            iconSizeScore(lhs["sizes"] as? String) > iconSizeScore(rhs["sizes"] as? String)
        }
        for icon in sortedIcons {
            guard let src = icon["src"] as? String,
                  let data = imageData(for: src, entryRelativePath: manifestRelativePath, folderURL: folderURL) else {
                continue
            }
            return data
        }
        return nil
    }

    private static func iconSizeScore(_ sizes: String?) -> Int {
        guard let sizes else { return 0 }
        return sizes
            .split(separator: " ")
            .compactMap { size -> Int? in
                let parts = size.lowercased().split(separator: "x")
                guard let first = parts.first, let value = Int(first) else { return nil }
                return value
            }
            .max() ?? 0
    }

    private static func imageData(for reference: String, entryRelativePath: String, folderURL: URL) -> Data? {
        if let data = dataURLImageData(reference) {
            return data
        }
        guard let relativePath = resolvedRelativePath(
            for: reference,
            entryRelativePath: entryRelativePath,
            folderURL: folderURL
        ) else {
            return nil
        }
        let url = folderURL.appendingPathComponent(relativePath, isDirectory: false)
        return try? Data(contentsOf: url)
    }

    private static func resolvedRelativePath(
        for reference: String,
        entryRelativePath: String,
        folderURL: URL
    ) -> String? {
        var cleaned = decodeBasicHTMLEntities(in: reference)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty,
              !hasCaseInsensitivePrefix(cleaned, "http://"),
              !hasCaseInsensitivePrefix(cleaned, "https://") else {
            return nil
        }

        if let markerRange = cleaned.range(of: "#") {
            cleaned = String(cleaned[..<markerRange.lowerBound])
        }
        if let markerRange = cleaned.range(of: "?") {
            cleaned = String(cleaned[..<markerRange.lowerBound])
        }
        guard !cleaned.isEmpty else { return nil }

        let candidateURL: URL
        if cleaned.hasPrefix("/") {
            candidateURL = folderURL.appendingPathComponent(String(cleaned.dropFirst()), isDirectory: false)
        } else {
            let entryURL = folderURL.appendingPathComponent(entryRelativePath, isDirectory: false)
            candidateURL = URL(fileURLWithPath: cleaned, relativeTo: entryURL.deletingLastPathComponent())
        }

        let standardized = candidateURL.standardizedFileURL
        guard isDescendant(standardized, of: folderURL),
              let relativePath = relativePath(of: standardized, in: folderURL) else {
            return nil
        }
        return relativePath
    }

    private static func dataURLImageData(_ reference: String) -> Data? {
        guard hasCaseInsensitivePrefix(reference, "data:image/"),
              let commaIndex = reference.firstIndex(of: ",") else {
            return nil
        }
        let metadata = reference[..<commaIndex].lowercased()
        let payload = String(reference[reference.index(after: commaIndex)...])
        if metadata.contains(";base64") {
            return Data(base64Encoded: payload, options: [.ignoreUnknownCharacters])
        }
        return payload.removingPercentEncoding?.data(using: .utf8)
    }

    private static func relValues(in attributes: [String: String]) -> [String] {
        attributes["rel"]?
            .lowercased()
            .split(separator: " ")
            .map(String.init) ?? []
    }

    private static func hasCaseInsensitivePrefix(_ value: String, _ prefix: String) -> Bool {
        value.range(of: prefix, options: [.caseInsensitive, .anchored]) != nil
    }

    private static func tagAttributes(named tagName: String, in text: String) -> [[String: String]] {
        let pattern = "<\\s*\(tagName)\\b[^>]*>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        return matches.map { match in
            let tagText = nsText.substring(with: match.range)
            return attributes(in: tagText)
        }
    }

    private static func attributes(in tagText: String) -> [String: String] {
        let pattern = #"([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [:]
        }

        let nsText = tagText as NSString
        var result: [String: String] = [:]
        for match in regex.matches(in: tagText, range: NSRange(location: 0, length: nsText.length)) {
            guard match.numberOfRanges == 3 else { continue }
            let key = nsText.substring(with: match.range(at: 1)).lowercased()
            var value = nsText.substring(with: match.range(at: 2))
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
                (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            result[key] = value
        }
        return result
    }

    private static func preferredProjectImage(in folderURL: URL, fileManager: FileManager) -> UIImage? {
        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var candidates: [(score: Int, image: UIImage)] = []
        for case let fileURL as URL in enumerator {
            guard let relativePath = relativePath(of: fileURL, in: folderURL),
                  !relativePath.hasPrefix("\(WebPageRuntimeStorage.directoryName)/"),
                  supportedProjectImageExtensions.contains(fileURL.pathExtension.lowercased()),
                  let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true,
                  let image = UIImage(contentsOfFile: fileURL.path),
                  isUsableProjectIconCandidate(image) else {
                continue
            }
            let score = imageCandidateScore(for: fileURL)
            guard score >= 0 else { continue }
            candidates.append((score: score, image: image))
        }

        return candidates.sorted { $0.score > $1.score }.first?.image
    }

    private static let supportedProjectImageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "webp", "gif", "ico", "svg"
    ]

    private static func isUsableProjectIconCandidate(_ image: UIImage) -> Bool {
        guard image.size.width >= 40, image.size.height >= 40 else { return false }
        let aspectRatio = max(image.size.width / image.size.height, image.size.height / image.size.width)
        return aspectRatio <= 3
    }

    private static func imageCandidateScore(for url: URL) -> Int {
        let name = url.deletingPathExtension().lastPathComponent.lowercased()
        if name.contains("sprite") || name.contains("background") || name.contains("banner") || name.contains("ad") {
            return -100
        }

        var score = 0
        if name.contains("icon") { score += 50 }
        if name.contains("logo") { score += 45 }
        if name.contains("app") { score += 35 }
        if name.contains("avatar") { score += 25 }
        if name.contains("thumbnail") || name.contains("thumb") { score += 20 }
        if name.contains("favicon") { score += 45 }
        return score
    }

    private static func title(from htmlContent: String, fallbackURL url: URL) -> String {
        if let htmlTitle = documentTitle(from: htmlContent) {
            return htmlTitle
        }

        let name = url.deletingPathExtension().lastPathComponent
        return name.isEmpty ? AppStrings.localized("未命名网页") : name
    }

    private static func archiveTitle(from url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        return name.isEmpty ? AppStrings.localized("未命名网页") : name
    }

    private static func archiveTitle(
        from url: URL,
        defaultEntry: WebPageEntry,
        htmlContent: String
    ) -> String {
        if defaultEntry.source == nil,
           let htmlTitle = documentTitle(from: htmlContent) {
            return htmlTitle
        }

        return archiveTitle(from: url)
    }

    private static func normalizedDisplayTitle(_ title: String) -> String {
        title
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func sourceFileName(from url: URL) -> String? {
        let fileName = url.lastPathComponent
        return fileName.isEmpty ? nil : fileName
    }

    private static func documentTitle(from htmlContent: String) -> String? {
        guard let headContent = firstTagContent(named: "head", in: htmlContent),
              let titleContent = firstTagContent(named: "title", in: headContent) else {
            return nil
        }

        let cleanedTitle = normalizeTitle(titleContent)
        return cleanedTitle.isEmpty ? nil : cleanedTitle
    }

    private static func firstTagContent(named tagName: String, in text: String) -> String? {
        guard let openingRange = text.range(
            of: "<\\s*\(tagName)(?:\\s[^>]*)?>",
            options: [.caseInsensitive, .regularExpression]
        ) else {
            return nil
        }

        guard let closingRange = text[openingRange.upperBound...].range(
            of: "</\\s*\(tagName)\\s*>",
            options: [.caseInsensitive, .regularExpression]
        ) else {
            return nil
        }

        return String(text[openingRange.upperBound..<closingRange.lowerBound])
    }

    private static func normalizeTitle(_ title: String) -> String {
        let withoutTags = title.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: [.regularExpression]
        )
        let decoded = decodeBasicHTMLEntities(in: withoutTags)
        return decoded
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func decodeBasicHTMLEntities(in text: String) -> String {
        text
            .replacingOccurrences(of: "&nbsp;", with: " ", options: .caseInsensitive)
            .replacingOccurrences(of: "&amp;", with: "&", options: .caseInsensitive)
            .replacingOccurrences(of: "&lt;", with: "<", options: .caseInsensitive)
            .replacingOccurrences(of: "&gt;", with: ">", options: .caseInsensitive)
            .replacingOccurrences(of: "&quot;", with: "\"", options: .caseInsensitive)
            .replacingOccurrences(of: "&#39;", with: "'", options: .caseInsensitive)
            .replacingOccurrences(of: "&apos;", with: "'", options: .caseInsensitive)
    }

    private static func sha256HexDigest(for url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

extension JSONDecoder {
    static var webPageRuntimeStorageDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
