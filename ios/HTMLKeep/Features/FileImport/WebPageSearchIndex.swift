import Foundation

private let maximumHTMLSearchReadByteCount = 4_000_000

struct WebPageSearchResult: Identifiable, Hashable {
    var page: WebPage
    var entry: WebPageEntry
    var matchKind: WebPageSearchMatchKind
    var snippet: String?
    var score: Int

    var id: String {
        "\(page.id.uuidString)-\(entry.id.uuidString)-\(matchKind.rawValue)"
    }
}

enum WebPageSearchScope: Hashable {
    case basic
    case full
}

enum WebPageSearchMatchKind: String, Codable, Hashable {
    case projectTitle
    case pageTitle
    case fileName
    case content
}

struct WebPageSearchIndex: Codable {
    private var documents: [WebPageSearchDocument] = []
    private var includesHTMLContent = false

    var hasHTMLContent: Bool {
        includesHTMLContent
    }

    init() {}

    private init(documents: [WebPageSearchDocument], includesHTMLContent: Bool) {
        self.documents = documents
        self.includesHTMLContent = includesHTMLContent
    }

    func replacingDocuments(
        for page: WebPage,
        folderURL: URL,
        fileManager: FileManager,
        includeHTMLContent: Bool? = nil
    ) -> WebPageSearchIndex {
        let nextDocuments = Self.buildDocuments(
            for: page,
            folderURL: folderURL,
            fileManager: fileManager,
            includeHTMLContent: includeHTMLContent ?? includesHTMLContent
        )
        return WebPageSearchIndex(
            documents: documents.filter { $0.pageID != page.id } + nextDocuments,
            includesHTMLContent: includeHTMLContent ?? includesHTMLContent
        )
    }

    func removingDocuments(for pageIDs: Set<WebPage.ID>) -> WebPageSearchIndex {
        WebPageSearchIndex(
            documents: documents.filter { !pageIDs.contains($0.pageID) },
            includesHTMLContent: includesHTMLContent
        )
    }

    private enum CodingKeys: String, CodingKey {
        case documents
        case includesHTMLContent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        documents = try container.decode([WebPageSearchDocument].self, forKey: .documents)
        includesHTMLContent = try container.decodeIfPresent(Bool.self, forKey: .includesHTMLContent) ?? true
    }

    static func build(
        pages: [WebPage],
        folderURL: (WebPage) -> URL,
        fileManager: FileManager,
        includeHTMLContent: Bool = true
    ) -> WebPageSearchIndex {
        build(
            pageFolders: pages.map { page in
                (page: page, folderURL: folderURL(page))
            },
            fileManager: fileManager,
            includeHTMLContent: includeHTMLContent
        )
    }

    static func build(
        pageFolders: [(page: WebPage, folderURL: URL)],
        fileManager: FileManager,
        includeHTMLContent: Bool = true
    ) -> WebPageSearchIndex {
        let documents = pageFolders.flatMap { pageFolder in
            buildDocuments(
                for: pageFolder.page,
                folderURL: pageFolder.folderURL,
                fileManager: fileManager,
                includeHTMLContent: includeHTMLContent
            )
        }
        return WebPageSearchIndex(documents: documents, includesHTMLContent: includeHTMLContent)
    }

    func search(_ query: String, pages: [WebPage]) -> [WebPageSearchResult] {
        Self.search(query, pages: pages, documents: documents, includesContentResults: includesHTMLContent)
    }

    static func searchMetadata(_ query: String, pages: [WebPage]) -> [WebPageSearchResult] {
        let documents = pages.flatMap { page in
            buildMetadataDocuments(for: page)
        }
        return search(query, pages: pages, documents: documents, includesContentResults: false)
    }

    private static func search(
        _ query: String,
        pages: [WebPage],
        documents: [WebPageSearchDocument],
        includesContentResults: Bool
    ) -> [WebPageSearchResult] {
        let tokens = Self.queryTokens(in: query)
        guard !tokens.isEmpty else { return [] }

        let pageByID = Dictionary(uniqueKeysWithValues: pages.map { ($0.id, $0) })
        var bestResults: [String: WebPageSearchResult] = [:]

        for document in documents {
            guard let page = pageByID[document.pageID],
                  let entry = page.resolvedEntries.first(where: { $0.id == document.entryID }) else {
                continue
            }

            let defaultEntryID = page.defaultEntryID ?? page.resolvedEntries.first?.id
            let projectLevelEntry = defaultEntryID == entry.id

            if projectLevelEntry, Self.contains(tokens, in: document.projectTitleSearchText) {
                Self.upsert(
                    WebPageSearchResult(
                        page: page,
                        entry: entry,
                        matchKind: .projectTitle,
                        snippet: Self.snippet(in: document.projectTitle, query: query, tokens: tokens),
                        score: 400
                    ),
                    into: &bestResults
                )
            }

            if Self.contains(tokens, in: document.entryTitleSearchText) {
                Self.upsert(
                    WebPageSearchResult(
                        page: page,
                        entry: entry,
                        matchKind: .pageTitle,
                        snippet: Self.snippet(in: document.entryTitle, query: query, tokens: tokens),
                        score: 300
                    ),
                    into: &bestResults
                )
            }

            if Self.contains(tokens, in: document.fileSearchText) {
                Self.upsert(
                    WebPageSearchResult(
                        page: page,
                        entry: entry,
                        matchKind: .fileName,
                        snippet: Self.snippet(in: document.fileText, query: query, tokens: tokens),
                        score: 220
                    ),
                    into: &bestResults
                )
            }

            if includesContentResults, Self.contains(tokens, in: document.contentSearchText) {
                Self.upsert(
                    WebPageSearchResult(
                        page: page,
                        entry: entry,
                        matchKind: .content,
                        snippet: Self.snippet(in: document.contentText, query: query, tokens: tokens),
                        score: 120
                    ),
                    into: &bestResults
                )
            }
        }

        return bestResults.values.sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            if lhs.page.createdAt != rhs.page.createdAt {
                return lhs.page.createdAt > rhs.page.createdAt
            }
            return lhs.page.title.localizedStandardCompare(rhs.page.title) == .orderedAscending
        }
    }

    func save(to url: URL, encoder: JSONEncoder = JSONEncoder()) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(self)
            try data.write(to: url, options: [.atomic])
        } catch {
            assertionFailure("Failed to save web page search index: \(error)")
        }
    }

    static func load(from url: URL, decoder: JSONDecoder = JSONDecoder()) -> WebPageSearchIndex? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(WebPageSearchIndex.self, from: data)
    }

    private static func buildDocuments(
        for page: WebPage,
        folderURL: URL,
        fileManager: FileManager,
        includeHTMLContent: Bool
    ) -> [WebPageSearchDocument] {
        page.resolvedEntries.map { entry in
            let entryFileName = entry.entryFileName
            let htmlText: String
            if includeHTMLContent,
               page.resolvedProjectKind == .html,
               entry.source != .bundledArchiveIndex,
               entry.source != .nativeFileIndex {
                let entryURL = folderURL.appendingPathComponent(entry.entryRelativePath, isDirectory: false)
                htmlText = Self.extractedText(fromHTMLAt: entryURL, fileManager: fileManager)
            } else {
                htmlText = ""
            }

            let fileText = [
                page.sourceFileName,
                entry.entryRelativePath,
                entryFileName
            ]
            .compactMap { $0 }
            .joined(separator: " ")

            return WebPageSearchDocument(
                pageID: page.id,
                entryID: entry.id,
                projectTitle: page.title,
                entryTitle: entry.title,
                fileText: fileText,
                contentText: htmlText
            )
        }
    }

    private static func buildMetadataDocuments(for page: WebPage) -> [WebPageSearchDocument] {
        page.resolvedEntries.map { entry in
            WebPageSearchDocument(
                pageID: page.id,
                entryID: entry.id,
                projectTitle: page.title,
                entryTitle: entry.title,
                fileText: [
                    page.sourceFileName,
                    entry.entryRelativePath,
                    entry.entryFileName
                ]
                .compactMap { $0 }
                .joined(separator: " "),
                contentText: ""
            )
        }
    }

    private static func upsert(
        _ result: WebPageSearchResult,
        into results: inout [String: WebPageSearchResult]
    ) {
        let key = "\(result.page.id.uuidString)-\(result.entry.id.uuidString)"
        guard let existing = results[key] else {
            results[key] = result
            return
        }
        if result.score > existing.score {
            var nextResult = result
            if nextResult.snippet == nil {
                nextResult.snippet = existing.snippet
            }
            results[key] = nextResult
        } else if existing.snippet == nil, result.snippet != nil {
            var nextExisting = existing
            nextExisting.snippet = result.snippet
            results[key] = nextExisting
        }
    }

    private static func extractedText(fromHTMLAt url: URL, fileManager: FileManager) -> String {
        guard fileManager.fileExists(atPath: url.path),
              let html = Self.readTextFile(at: url) else {
            return ""
        }

        var text = html
        text = text.replacingMatches(of: #"(?is)<!--.*?-->"#, with: " ")
        text = text.replacingMatches(of: #"(?is)<(script|style|noscript|svg)\b[^>]*>.*?</\1>"#, with: " ")
        text = text.replacingMatches(of: #"(?is)<[^>]+>"#, with: " ")
        text = Self.decodedEntities(in: text)
        text = text.replacingMatches(of: #"\s+"#, with: " ")
        return String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(20_000))
    }

    private static func readTextFile(at url: URL) -> String? {
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer {
            try? fileHandle.close()
        }

        let data = (try? fileHandle.read(upToCount: maximumHTMLSearchReadByteCount)) ?? Data()
        guard !data.isEmpty else {
            return ""
        }

        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        if let unicode = String(data: data, encoding: .unicode) {
            return unicode
        }
        return String(data: data, encoding: .isoLatin1)
    }

    private static func decodedEntities(in text: String) -> String {
        var decoded = text
        let namedEntities = [
            "&nbsp;": " ",
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&apos;": "'"
        ]
        for (entity, value) in namedEntities {
            decoded = decoded.replacingOccurrences(of: entity, with: value)
        }
        return decoded.replacingMatches(of: #"&#(\d+);"#) { match in
            guard let value = Int(match.capturedGroup(at: 1) ?? ""),
                  let scalar = UnicodeScalar(value) else {
                return match.matchedString
            }
            return String(scalar)
        }
    }

    private static func queryTokens(in query: String) -> [String] {
        normalized(query)
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    fileprivate static func normalized(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .replacingMatches(of: #"\s+"#, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func contains(_ tokens: [String], in normalizedText: String) -> Bool {
        guard !normalizedText.isEmpty else { return false }
        return tokens.allSatisfy { normalizedText.contains($0) }
    }

    private static func snippet(
        in text: String,
        query: String,
        tokens: [String],
        leadingContext: Int = 8,
        trailingContext: Int = 56
    ) -> String? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return nil }

        let candidates = [query] + tokens
        let range = candidates.lazy.compactMap { candidate in
            trimmedText.range(of: candidate, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive])
        }.first

        guard let range else {
            return String(trimmedText.prefix(leadingContext + trailingContext))
        }

        let lower = trimmedText.index(range.lowerBound, offsetBy: -leadingContext, limitedBy: trimmedText.startIndex) ?? trimmedText.startIndex
        let upper = trimmedText.index(range.upperBound, offsetBy: trailingContext, limitedBy: trimmedText.endIndex) ?? trimmedText.endIndex
        let prefix = lower == trimmedText.startIndex ? "" : "..."
        let suffix = upper == trimmedText.endIndex ? "" : "..."
        return prefix + String(trimmedText[lower..<upper]) + suffix
    }
}

private struct WebPageSearchDocument: Codable {
    var pageID: WebPage.ID
    var entryID: WebPageEntry.ID
    var projectTitle: String
    var entryTitle: String
    var fileText: String
    var contentText: String
    var projectTitleSearchText: String
    var entryTitleSearchText: String
    var fileSearchText: String
    var contentSearchText: String
    var indexedAt: Date = .now

    init(
        pageID: WebPage.ID,
        entryID: WebPageEntry.ID,
        projectTitle: String,
        entryTitle: String,
        fileText: String,
        contentText: String,
        indexedAt: Date = .now
    ) {
        self.pageID = pageID
        self.entryID = entryID
        self.projectTitle = projectTitle
        self.entryTitle = entryTitle
        self.fileText = fileText
        self.contentText = contentText
        self.projectTitleSearchText = WebPageSearchIndex.normalized(projectTitle)
        self.entryTitleSearchText = WebPageSearchIndex.normalized(entryTitle)
        self.fileSearchText = WebPageSearchIndex.normalized(fileText)
        self.contentSearchText = WebPageSearchIndex.normalized(contentText)
        self.indexedAt = indexedAt
    }

    private enum CodingKeys: String, CodingKey {
        case pageID
        case entryID
        case projectTitle
        case entryTitle
        case fileText
        case contentText
        case projectTitleSearchText
        case entryTitleSearchText
        case fileSearchText
        case contentSearchText
        case indexedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pageID = try container.decode(WebPage.ID.self, forKey: .pageID)
        entryID = try container.decode(WebPageEntry.ID.self, forKey: .entryID)
        projectTitle = try container.decode(String.self, forKey: .projectTitle)
        entryTitle = try container.decode(String.self, forKey: .entryTitle)
        fileText = try container.decode(String.self, forKey: .fileText)
        contentText = try container.decode(String.self, forKey: .contentText)
        projectTitleSearchText = try container.decodeIfPresent(String.self, forKey: .projectTitleSearchText)
            ?? WebPageSearchIndex.normalized(projectTitle)
        entryTitleSearchText = try container.decodeIfPresent(String.self, forKey: .entryTitleSearchText)
            ?? WebPageSearchIndex.normalized(entryTitle)
        fileSearchText = try container.decodeIfPresent(String.self, forKey: .fileSearchText)
            ?? WebPageSearchIndex.normalized(fileText)
        contentSearchText = try container.decodeIfPresent(String.self, forKey: .contentSearchText)
            ?? WebPageSearchIndex.normalized(contentText)
        indexedAt = try container.decodeIfPresent(Date.self, forKey: .indexedAt) ?? .now
    }
}

private extension String {
    func replacingMatches(of pattern: String, with replacement: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return self
        }
        let range = NSRange(startIndex..<endIndex, in: self)
        return expression.stringByReplacingMatches(in: self, range: range, withTemplate: replacement)
    }

    func replacingMatches(
        of pattern: String,
        using transform: (RegexMatch) -> String
    ) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return self
        }
        let nsString = self as NSString
        let matches = expression.matches(in: self, range: NSRange(location: 0, length: nsString.length))
        guard !matches.isEmpty else { return self }

        var result = self
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: transform(RegexMatch(match: match, source: nsString)))
        }
        return result
    }
}

private struct RegexMatch {
    let match: NSTextCheckingResult
    let source: NSString

    var matchedString: String {
        source.substring(with: match.range)
    }

    func capturedGroup(at index: Int) -> String? {
        guard index < match.numberOfRanges else { return nil }
        let range = match.range(at: index)
        guard range.location != NSNotFound else { return nil }
        return source.substring(with: range)
    }
}
