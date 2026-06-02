import Foundation
import SwiftUI

enum AppRuntimeConfiguration {
    static func string(forInfoKey key: String, default defaultValue: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return defaultValue
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? defaultValue : trimmedValue
    }

    static var appGroupIdentifier: String {
        string(
            forInfoKey: "HTMLKeepAppGroupIdentifier",
            default: "group.com.htmlkeep.community"
        )
    }

    static var iCloudContainerIdentifier: String {
        string(
            forInfoKey: "HTMLKeepICloudContainerIdentifier",
            default: "iCloud.com.htmlkeep.community.accountsync"
        )
    }
}

enum ProjectWidgetShared {
    static let widgetKind = "ProjectEntryWidget"
    static var appGroupIdentifier: String { AppRuntimeConfiguration.appGroupIdentifier }
    static let snapshotFileName = "project-widget-snapshot.json"
    static let entitlementFileName = "project-widget-entitlement.json"
    static let iconsDirectoryName = "ProjectWidgetIcons"
    static let openProjectScheme = "htmlanywhere"
    static let openProjectHost = "open-project"
    static let proEntitlementHost = "proEntitlement"
    static let homeHost = "home"

    static func containerURL(fileManager: FileManager = .default) -> URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    static func snapshotURL(fileManager: FileManager = .default) -> URL? {
        containerURL(fileManager: fileManager)?.appendingPathComponent(snapshotFileName, isDirectory: false)
    }

    static func entitlementURL(fileManager: FileManager = .default) -> URL? {
        containerURL(fileManager: fileManager)?.appendingPathComponent(entitlementFileName, isDirectory: false)
    }

    static func iconsDirectoryURL(fileManager: FileManager = .default) -> URL? {
        containerURL(fileManager: fileManager)?.appendingPathComponent(iconsDirectoryName, isDirectory: true)
    }

    static func iconURL(fileName: String, fileManager: FileManager = .default) -> URL? {
        guard !fileName.contains("/"), !fileName.contains("\\") else {
            return nil
        }
        return iconsDirectoryURL(fileManager: fileManager)?.appendingPathComponent(fileName, isDirectory: false)
    }

    static func openProjectURL(projectID: UUID, safeAreaTopBackground: String? = nil) -> URL {
        var components = URLComponents()
        components.scheme = openProjectScheme
        components.host = openProjectHost
        components.path = "/\(projectID.uuidString)"

        if let safeAreaTopBackground,
           !safeAreaTopBackground.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            components.queryItems = [
                URLQueryItem(name: "background", value: safeAreaTopBackground)
            ]
        }

        return components.url!
    }

    static var homeURL: URL {
        URL(string: "\(openProjectScheme)://\(homeHost)")!
    }

    static var proEntitlementURL: URL {
        URL(string: "\(openProjectScheme)://\(proEntitlementHost)")!
    }

    static func isProEntitlementURL(_ url: URL) -> Bool {
        url.scheme == openProjectScheme && url.host == proEntitlementHost
    }

    static func projectID(from url: URL) -> UUID? {
        guard url.scheme == openProjectScheme, url.host == openProjectHost else {
            return nil
        }

        if let idString = url.pathComponents.dropFirst().first,
           let id = UUID(uuidString: idString) {
            return id
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let idString = components?.queryItems?.first { $0.name == "id" }?.value
        return idString.flatMap(UUID.init(uuidString:))
    }

    static func isHomeURL(_ url: URL) -> Bool {
        url.scheme == openProjectScheme && url.host == homeHost
    }

    static func launchBackground(from url: URL) -> String? {
        guard url.scheme == openProjectScheme else {
            return nil
        }

        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == "background" }?
            .value
    }

    static func readSnapshot(fileManager: FileManager = .default) -> ProjectWidgetSnapshot {
        guard let url = snapshotURL(fileManager: fileManager),
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(ProjectWidgetSnapshot.self, from: data) else {
            return ProjectWidgetSnapshot(updatedAt: .distantPast, projects: [])
        }
        return snapshot
    }

    static func readEntitlement(fileManager: FileManager = .default) -> ProjectWidgetEntitlementSnapshot {
        guard let url = entitlementURL(fileManager: fileManager),
              let data = try? Data(contentsOf: url),
              let entitlement = try? JSONDecoder().decode(ProjectWidgetEntitlementSnapshot.self, from: data) else {
            return ProjectWidgetEntitlementSnapshot()
        }
        return entitlement
    }

    @discardableResult
    static func writeSnapshot(_ snapshot: ProjectWidgetSnapshot, fileManager: FileManager = .default) -> Bool {
        guard let url = snapshotURL(fileManager: fileManager),
              let containerURL = containerURL(fileManager: fileManager) else {
            return false
        }

        do {
            try fileManager.createDirectory(at: containerURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: [.atomic])
            reconcileEntitlement(activeProjectIDs: Set(snapshot.projects.map(\.id)), fileManager: fileManager)
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    static func updateEntitlement(
        canBindMultipleProjects: Bool,
        activeProjectIDs: Set<UUID>,
        fileManager: FileManager = .default
    ) -> Bool {
        var entitlement = readEntitlement(fileManager: fileManager)
        entitlement.canBindMultipleProjects = canBindMultipleProjects
        entitlement.updatedAt = Date()
        if let boundProjectID = entitlement.freeBoundProjectID,
           !activeProjectIDs.contains(boundProjectID) {
            entitlement.freeBoundProjectID = nil
        }
        return writeEntitlement(entitlement, fileManager: fileManager)
    }

    static func projectsAvailableForWidgetConfiguration(
        in snapshot: ProjectWidgetSnapshot,
        fileManager _: FileManager = .default
    ) -> [ProjectWidgetProject] {
        snapshot.projects.filter(\.isOpenable)
    }

    static func bindingAccess(
        for projectID: UUID,
        activeProjectIDs: Set<UUID>,
        fileManager: FileManager = .default
    ) -> ProjectWidgetBindingAccess {
        var entitlement = readEntitlement(fileManager: fileManager)
            .normalized(activeProjectIDs: activeProjectIDs)

        if entitlement.canBindMultipleProjects {
            return .allowed
        }

        if let freeBoundProjectID = entitlement.freeBoundProjectID {
            if freeBoundProjectID == projectID {
                return .allowed
            }
            return .requiresProEntitlement
        }

        entitlement.freeBoundProjectID = projectID
        entitlement.updatedAt = Date()
        _ = writeEntitlement(entitlement, fileManager: fileManager)
        return .allowed
    }

    @discardableResult
    private static func writeEntitlement(
        _ entitlement: ProjectWidgetEntitlementSnapshot,
        fileManager: FileManager = .default
    ) -> Bool {
        guard let url = entitlementURL(fileManager: fileManager),
              let containerURL = containerURL(fileManager: fileManager) else {
            return false
        }

        do {
            try fileManager.createDirectory(at: containerURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(entitlement)
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    private static func reconcileEntitlement(activeProjectIDs: Set<UUID>, fileManager: FileManager) {
        let entitlement = readEntitlement(fileManager: fileManager)
        let normalized = entitlement.normalized(activeProjectIDs: activeProjectIDs)
        if normalized != entitlement {
            _ = writeEntitlement(normalized, fileManager: fileManager)
        }
    }
}

struct ProjectWidgetSnapshot: Codable, Hashable {
    var updatedAt: Date
    var projects: [ProjectWidgetProject]
}

struct ProjectWidgetEntitlementSnapshot: Codable, Hashable {
    var updatedAt: Date
    var canBindMultipleProjects: Bool
    var freeBoundProjectID: UUID?

    init(
        updatedAt: Date = .distantPast,
        canBindMultipleProjects: Bool = false,
        freeBoundProjectID: UUID? = nil
    ) {
        self.updatedAt = updatedAt
        self.canBindMultipleProjects = canBindMultipleProjects
        self.freeBoundProjectID = freeBoundProjectID
    }

    func normalized(activeProjectIDs: Set<UUID>) -> ProjectWidgetEntitlementSnapshot {
        guard let freeBoundProjectID, !activeProjectIDs.contains(freeBoundProjectID) else {
            return self
        }

        var copy = self
        copy.freeBoundProjectID = nil
        copy.updatedAt = Date()
        return copy
    }
}

enum ProjectWidgetBindingAccess: Hashable {
    case allowed
    case requiresProEntitlement
}

struct ProjectWidgetProject: Codable, Hashable, Identifiable {
    var id: UUID
    var title: String
    var kind: ProjectWidgetProjectKind
    var loadStatus: ProjectWidgetLoadStatus
    var isOpenable: Bool
    var usesCustomIcon: Bool
    var safeAreaTopBackground: String?
    var iconFileName: String?
    var fallbackSymbolName: String
    var updatedAt: Date

    init(
        id: UUID,
        title: String,
        kind: ProjectWidgetProjectKind,
        loadStatus: ProjectWidgetLoadStatus,
        isOpenable: Bool,
        usesCustomIcon: Bool,
        safeAreaTopBackground: String?,
        iconFileName: String?,
        fallbackSymbolName: String,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.loadStatus = loadStatus
        self.isOpenable = isOpenable
        self.usesCustomIcon = usesCustomIcon
        self.safeAreaTopBackground = safeAreaTopBackground
        self.iconFileName = iconFileName
        self.fallbackSymbolName = fallbackSymbolName
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case kind
        case loadStatus
        case isOpenable
        case usesCustomIcon
        case safeAreaTopBackground
        case iconFileName
        case fallbackSymbolName
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        kind = try container.decode(ProjectWidgetProjectKind.self, forKey: .kind)
        loadStatus = try container.decode(ProjectWidgetLoadStatus.self, forKey: .loadStatus)
        isOpenable = try container.decode(Bool.self, forKey: .isOpenable)
        usesCustomIcon = try container.decodeIfPresent(Bool.self, forKey: .usesCustomIcon) ?? false
        safeAreaTopBackground = try container.decodeIfPresent(String.self, forKey: .safeAreaTopBackground)
        iconFileName = try container.decodeIfPresent(String.self, forKey: .iconFileName)
        fallbackSymbolName = try container.decode(String.self, forKey: .fallbackSymbolName)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

enum ProjectWidgetProjectKind: String, Codable, Hashable {
    case html
    case singleFile
    case nativeFileArchive
}

enum ProjectWidgetLoadStatus: String, Codable, Hashable {
    case ready
    case missing
    case failed
    case metadataOnly
    case downloading
    case downloadFailed
    case invalidPackage

    var isCloudPackageUnavailable: Bool {
        switch self {
        case .metadataOnly, .downloading, .downloadFailed, .invalidPackage:
            return true
        case .ready, .missing, .failed:
            return false
        }
    }
}

struct ProjectWidgetPaint {
    let colors: [Color]
    let startPoint: UnitPoint
    let endPoint: UnitPoint
    let foreground: Color
    let foregroundIsDark: Bool

    @ViewBuilder
    var background: some View {
        if colors.count == 1, let color = colors.first {
            Rectangle().fill(color)
        } else {
            LinearGradient(colors: colors, startPoint: startPoint, endPoint: endPoint)
        }
    }

    static func resolve(from cssBackground: String?, colorScheme: ColorScheme) -> ProjectWidgetPaint {
        if let cssBackground,
           let parsed = ProjectWidgetBackgroundParser.paint(from: cssBackground) {
            return parsed
        }

        switch colorScheme {
        case .dark:
            return ProjectWidgetPaint(
                colors: [
                    Color(red: 0.06, green: 0.08, blue: 0.12),
                    Color(red: 0.10, green: 0.14, blue: 0.19)
                ],
                startPoint: .top,
                endPoint: .bottom,
                foreground: .white.opacity(0.92),
                foregroundIsDark: false
            )
        default:
            return ProjectWidgetPaint(
                colors: [
                    Color(red: 0.88, green: 0.93, blue: 0.99),
                    Color(red: 0.98, green: 0.99, blue: 1.00)
                ],
                startPoint: .top,
                endPoint: .bottom,
                foreground: Color(red: 0.23, green: 0.31, blue: 0.43),
                foregroundIsDark: true
            )
        }
    }
}

private enum ProjectWidgetBackgroundParser {
    static func paint(from cssBackground: String) -> ProjectWidgetPaint? {
        let trimmed = cssBackground.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let gradient = linearGradient(from: trimmed) {
            return gradient
        }

        guard let token = colorToken(from: trimmed) else {
            return nil
        }

        return ProjectWidgetPaint(
            colors: [token.color],
            startPoint: .top,
            endPoint: .bottom,
            foreground: foregroundColor(forAverageLuminance: token.luminance),
            foregroundIsDark: token.luminance > 0.58
        )
    }

    private static func linearGradient(from cssBackground: String) -> ProjectWidgetPaint? {
        let lowercased = cssBackground.lowercased()
        guard let prefixRange = lowercased.range(of: "linear-gradient(") else {
            return nil
        }

        let start = prefixRange.upperBound
        guard let end = closingParenthesis(in: cssBackground, from: start) else {
            return nil
        }

        var arguments = splitTopLevelCommas(String(cssBackground[start..<end]))
        guard arguments.count >= 2 else {
            return nil
        }

        let direction = gradientDirection(from: arguments[0])
        if direction.didConsumeArgument {
            arguments.removeFirst()
        }

        let tokens = arguments.compactMap(colorToken(from:))
        guard let first = tokens.first,
              let last = tokens.dropFirst().last ?? tokens.dropFirst().first else {
            return nil
        }

        let averageLuminance = (first.luminance + last.luminance) / 2
        return ProjectWidgetPaint(
            colors: [first.color, last.color],
            startPoint: direction.start,
            endPoint: direction.end,
            foreground: foregroundColor(forAverageLuminance: averageLuminance),
            foregroundIsDark: averageLuminance > 0.58
        )
    }

    private static func colorToken(from text: String) -> ProjectWidgetColorToken? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let hexIndex = trimmed.firstIndex(of: "#") {
            let hexTail = trimmed[hexIndex...].prefix { character in
                character == "#" || character.isHexDigit
            }
            if let token = colorToken(fromHex: String(hexTail)) {
                return token
            }
        }

        for prefix in ["rgba(", "rgb("] {
            if let range = trimmed.range(of: prefix, options: .caseInsensitive),
               let close = closingParenthesis(in: trimmed, from: range.upperBound) {
                let inside = trimmed[range.upperBound..<close]
                if let token = colorToken(fromRGBComponents: String(inside)) {
                    return token
                }
            }
        }

        let lowercased = trimmed.lowercased()
        if lowercased.contains("white") {
            return ProjectWidgetColorToken(color: .white, luminance: 1)
        }
        if lowercased.contains("black") {
            return ProjectWidgetColorToken(color: .black, luminance: 0)
        }

        return nil
    }

    private static func colorToken(fromHex hexString: String) -> ProjectWidgetColorToken? {
        let hex = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 3 || hex.count == 6 || hex.count == 8 else {
            return nil
        }

        var value: UInt64 = 0
        guard Scanner(string: hex).scanHexInt64(&value) else {
            return nil
        }

        let red: UInt64
        let green: UInt64
        let blue: UInt64
        let alpha: UInt64
        switch hex.count {
        case 3:
            red = ((value >> 8) & 0xF) * 17
            green = ((value >> 4) & 0xF) * 17
            blue = (value & 0xF) * 17
            alpha = 255
        case 6:
            red = (value >> 16) & 0xFF
            green = (value >> 8) & 0xFF
            blue = value & 0xFF
            alpha = 255
        case 8:
            red = (value >> 24) & 0xFF
            green = (value >> 16) & 0xFF
            blue = (value >> 8) & 0xFF
            alpha = value & 0xFF
        default:
            return nil
        }

        return colorToken(
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            alpha: Double(alpha) / 255
        )
    }

    private static func colorToken(fromRGBComponents components: String) -> ProjectWidgetColorToken? {
        let values = components
            .split { character in
                character == "," || character == "/" || character.isWhitespace
            }
            .compactMap { part -> Double? in
                let clean = part.trimmingCharacters(in: CharacterSet(charactersIn: "%"))
                return Double(clean)
            }

        guard values.count >= 3 else {
            return nil
        }

        let red = normalizedRGB(values[0])
        let green = normalizedRGB(values[1])
        let blue = normalizedRGB(values[2])
        let alpha = values.count >= 4 ? min(max(values[3], 0), 1) : 1
        return colorToken(red: red, green: green, blue: blue, alpha: alpha)
    }

    private static func colorToken(red: Double, green: Double, blue: Double, alpha: Double) -> ProjectWidgetColorToken {
        let color = Color(red: red, green: green, blue: blue, opacity: alpha)
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        return ProjectWidgetColorToken(color: color, luminance: luminance)
    }

    private static func normalizedRGB(_ value: Double) -> Double {
        min(max(value / 255, 0), 1)
    }

    private static func foregroundColor(forAverageLuminance luminance: Double) -> Color {
        luminance > 0.58 ? Color.black.opacity(0.86) : Color.white.opacity(0.94)
    }

    private static func gradientDirection(from argument: String) -> ProjectWidgetGradientDirection {
        let lowercased = argument.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lowercased.contains("to right") {
            return ProjectWidgetGradientDirection(start: .leading, end: .trailing, didConsumeArgument: true)
        }
        if lowercased.contains("to left") {
            return ProjectWidgetGradientDirection(start: .trailing, end: .leading, didConsumeArgument: true)
        }
        if lowercased.contains("to top") {
            return ProjectWidgetGradientDirection(start: .bottom, end: .top, didConsumeArgument: true)
        }
        if lowercased.contains("to bottom") {
            return ProjectWidgetGradientDirection(start: .top, end: .bottom, didConsumeArgument: true)
        }

        if let degreeRange = lowercased.range(of: "deg"),
           let degree = Double(lowercased[..<degreeRange.lowerBound].split(separator: " ").last ?? "") {
            let normalized = degree.truncatingRemainder(dividingBy: 360)
            let positive = normalized >= 0 ? normalized : normalized + 360
            switch positive {
            case 45..<135:
                return ProjectWidgetGradientDirection(start: .leading, end: .trailing, didConsumeArgument: true)
            case 135..<225:
                return ProjectWidgetGradientDirection(start: .top, end: .bottom, didConsumeArgument: true)
            case 225..<315:
                return ProjectWidgetGradientDirection(start: .trailing, end: .leading, didConsumeArgument: true)
            default:
                return ProjectWidgetGradientDirection(start: .bottom, end: .top, didConsumeArgument: true)
            }
        }

        return ProjectWidgetGradientDirection(start: .top, end: .bottom, didConsumeArgument: false)
    }

    private static func splitTopLevelCommas(_ text: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0

        for character in text {
            if character == "(" {
                depth += 1
            } else if character == ")" {
                depth = max(depth - 1, 0)
            }

            if character == ",", depth == 0 {
                parts.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
            } else {
                current.append(character)
            }
        }

        let finalPart = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !finalPart.isEmpty {
            parts.append(finalPart)
        }
        return parts
    }

    private static func closingParenthesis(in text: String, from startIndex: String.Index) -> String.Index? {
        var depth = 1
        var index = startIndex

        while index < text.endIndex {
            let character = text[index]
            if character == "(" {
                depth += 1
            } else if character == ")" {
                depth -= 1
                if depth == 0 {
                    return index
                }
            }
            index = text.index(after: index)
        }

        return nil
    }
}

private struct ProjectWidgetColorToken {
    let color: Color
    let luminance: Double
}

private struct ProjectWidgetGradientDirection {
    let start: UnitPoint
    let end: UnitPoint
    let didConsumeArgument: Bool
}
