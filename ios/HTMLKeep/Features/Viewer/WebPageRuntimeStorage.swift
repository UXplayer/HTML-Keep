import Foundation
import WebKit

struct WebPageLocalStorageSnapshot: Codable, Equatable {
    var schemaVersion: Int
    var savedAt: Date
    var items: [String: String]
}

enum WebPageRuntimeStorage {
    static let directoryName = ".htmlanywhere"
    static let localStorageFileName = "local-storage.json"
    static let localStorageRelativePath = "\(directoryName)/\(localStorageFileName)"
    static let localStorageMessageName = "htmlAnywhereLocalStorage"

    static func dataStoreIdentifier(for page: WebPage) -> UUID {
        page.id
    }

    @MainActor
    static func websiteDataStore(for page: WebPage) -> WKWebsiteDataStore {
        WKWebsiteDataStore(forIdentifier: dataStoreIdentifier(for: page))
    }

    static func localStorageBootstrapState(
        in projectFolderURL: URL,
        fileManager: FileManager = .default
    ) -> (hasSnapshot: Bool, items: [String: String]) {
        let url = localStorageURL(in: projectFolderURL)
        guard fileManager.fileExists(atPath: url.path) else {
            return (false, [:])
        }
        return (true, localStorageItems(in: projectFolderURL, fileManager: fileManager))
    }

    static func localStorageItems(in projectFolderURL: URL, fileManager: FileManager = .default) -> [String: String] {
        let url = localStorageURL(in: projectFolderURL)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let snapshot = localStorageSnapshot(from: data),
              snapshot.schemaVersion == 1 else {
            return [:]
        }
        return snapshot.items
    }

    static func localStorageSavedAt(in files: [WebPageCloudSnapshotFile]) -> Date? {
        localStorageSnapshot(in: files)?.savedAt
    }

    static func localStorageSnapshot(in files: [WebPageCloudSnapshotFile]) -> WebPageLocalStorageSnapshot? {
        guard let file = files.first(where: { $0.relativePath == localStorageRelativePath }) else {
            return nil
        }
        guard let snapshot = localStorageSnapshot(from: file.data),
              snapshot.schemaVersion == 1 else {
            return nil
        }
        return snapshot
    }

    @discardableResult
    static func saveLocalStorageItems(
        _ items: [String: String],
        in projectFolderURL: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        do {
            try fileManager.createDirectory(
                at: runtimeDirectoryURL(in: projectFolderURL),
                withIntermediateDirectories: true
            )
            let snapshot = WebPageLocalStorageSnapshot(
                schemaVersion: 1,
                savedAt: .now,
                items: items
            )
            let url = localStorageURL(in: projectFolderURL)
            if let existingData = try? Data(contentsOf: url),
               let existingSnapshot = localStorageSnapshot(from: existingData),
               existingSnapshot.items == items {
                return false
            }
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    static func copyRuntimeDirectoryIfPresent(
        from sourceProjectFolderURL: URL,
        to destinationProjectFolderURL: URL,
        fileManager: FileManager = .default
    ) throws {
        let sourceURL = runtimeDirectoryURL(in: sourceProjectFolderURL)
        guard fileManager.fileExists(atPath: sourceURL.path) else { return }

        let destinationURL = runtimeDirectoryURL(in: destinationProjectFolderURL)
        try? fileManager.removeItem(at: destinationURL)
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    static func isRuntimeStoragePath(_ relativePath: String) -> Bool {
        relativePath == directoryName || relativePath.hasPrefix("\(directoryName)/")
    }

    @MainActor
    static func clearRuntimeData(
        for page: WebPage,
        projectFolderURL: URL,
        fileManager: FileManager = .default
    ) async throws {
        let runtimeURL = runtimeDirectoryURL(in: projectFolderURL)
        if fileManager.fileExists(atPath: runtimeURL.path) {
            try fileManager.removeItem(at: runtimeURL)
        }
        _ = saveLocalStorageItems([:], in: projectFolderURL, fileManager: fileManager)
        await removeWebsiteDataStore(identifier: dataStoreIdentifier(for: page))
    }

    @MainActor
    static func removeWebsiteDataStore(identifier: UUID) async {
        await withCheckedContinuation { continuation in
            WKWebsiteDataStore.remove(forIdentifier: identifier) { _ in
                continuation.resume()
            }
        }
    }

    private static func runtimeDirectoryURL(in projectFolderURL: URL) -> URL {
        projectFolderURL.appendingPathComponent(directoryName, isDirectory: true)
    }

    private static func localStorageURL(in projectFolderURL: URL) -> URL {
        runtimeDirectoryURL(in: projectFolderURL)
            .appendingPathComponent(localStorageFileName, isDirectory: false)
    }

    private static func localStorageSnapshot(from data: Data) -> WebPageLocalStorageSnapshot? {
        try? decoder.decode(WebPageLocalStorageSnapshot.self, from: data)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
