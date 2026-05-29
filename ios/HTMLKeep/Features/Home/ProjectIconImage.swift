import Foundation
import SwiftUI
import UIKit

struct ProjectIconImage: View {
    @Environment(\.colorScheme) private var colorScheme

    let iconURL: URL?
    let iconVersion: Date?
    let fallbackSymbolName: String
    let size: CGFloat
    let cornerRadius: CGFloat
    let fallbackBackground: ProjectIconFallbackBackground
    let fallbackPlacement: ProjectIconFallbackPlacement

    init(
        iconURL: URL?,
        iconVersion: Date? = nil,
        fallbackSymbolName: String,
        size: CGFloat,
        cornerRadius: CGFloat,
        fallbackBackground: ProjectIconFallbackBackground = .surface,
        fallbackPlacement: ProjectIconFallbackPlacement = .listItem
    ) {
        self.iconURL = iconURL
        self.iconVersion = iconVersion
        self.fallbackSymbolName = fallbackSymbolName
        self.size = size
        self.cornerRadius = cornerRadius
        self.fallbackBackground = fallbackBackground
        self.fallbackPlacement = fallbackPlacement
    }

    var body: some View {
        let fallbackAppearance = ProjectIconFallbackAppearance(
            background: fallbackBackground,
            placement: fallbackPlacement,
            colorScheme: colorScheme
        )

        ZStack {
            fallbackAppearance.backgroundView

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .id(iconIdentity)
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                Image(systemName: fallbackSymbolName)
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: size * 0.54, weight: .semibold))
                    .foregroundStyle(fallbackAppearance.symbolForegroundColor)
                    .frame(width: size * 0.72, height: size * 0.72)
            }
        }
        .overlay {
            if image == nil, let borderColor = fallbackAppearance.borderColor {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }

    private var image: UIImage? {
        guard let iconURL,
              let data = try? Data(contentsOf: iconURL) else {
            return nil
        }
        return UIImage(data: data)
    }

    private var iconIdentity: String {
        let path = iconURL?.path ?? "missing"
        let version = iconVersion?.timeIntervalSinceReferenceDate ?? 0
        return "\(path)#\(version)"
    }
}

enum ProjectIconFallbackBackground {
    case surface
    case webPageTop(String?)
}

enum ProjectIconFallbackPlacement {
    case listItem
    case pageBackground
}

private struct ProjectIconFallbackAppearance {
    let source: ProjectIconFallbackBackground
    let placement: ProjectIconFallbackPlacement
    let colorScheme: ColorScheme
    private let parsedStyle: ProjectIconCSSBackgroundStyle?

    init(
        background: ProjectIconFallbackBackground,
        placement: ProjectIconFallbackPlacement,
        colorScheme: ColorScheme
    ) {
        self.source = background
        self.placement = placement
        self.colorScheme = colorScheme
        if case .webPageTop(let value) = background {
            parsedStyle = ProjectIconCSSBackgroundStyle.parse(value)
        } else {
            parsedStyle = nil
        }
    }

    @ViewBuilder
    var backgroundView: some View {
        switch source {
        case .surface:
            Rectangle()
                .fill(AppTheme.surfaceStrong)
        case .webPageTop:
            switch parsedStyle {
            case .solid(let color):
                Rectangle()
                    .fill(color.swiftUIColor)
            case .gradient(let colors, let startPoint, let endPoint):
                LinearGradient(colors: colors.map(\.swiftUIColor), startPoint: startPoint, endPoint: endPoint)
            case .none:
                Rectangle()
                    .fill(AppTheme.surfaceStrong)
            }
        }
    }

    var symbolForegroundColor: Color {
        switch source {
        case .surface:
            return AppTheme.contentPrimary
        case .webPageTop:
            switch parsedStyle {
            case .solid(let color):
                return ProjectIconForegroundColor.color(for: [color])
            case .gradient(let colors, _, _):
                return ProjectIconForegroundColor.color(for: colors)
            case .none:
                return AppTheme.contentPrimary
            }
        }
    }

    var borderColor: Color? {
        let iconColors = backgroundColors
        guard ProjectIconBorder.shouldShowBorder(
            iconBackgroundColors: iconColors,
            placement: placement,
            colorScheme: colorScheme
        ) else {
            return nil
        }
        return ProjectIconBorder.color(for: iconColors)
    }

    private var backgroundColors: [ProjectIconColor] {
        switch source {
        case .surface:
            return [ProjectIconColor.surfaceStrong(colorScheme: colorScheme)]
        case .webPageTop:
            switch parsedStyle {
            case .solid(let color):
                return [color]
            case .gradient(let colors, _, _):
                return colors
            case .none:
                return [ProjectIconColor.surfaceStrong(colorScheme: colorScheme)]
            }
        }
    }
}

private enum ProjectIconCSSBackgroundStyle {
    case solid(ProjectIconColor)
    case gradient([ProjectIconColor], UnitPoint, UnitPoint)

    static func parse(_ value: String?) -> ProjectIconCSSBackgroundStyle? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.range(of: "gradient\\s*\\(", options: [.regularExpression, .caseInsensitive]) == nil,
           let color = parseColor(trimmed) {
            return .solid(color)
        }

        let gradient = firstLinearGradientExpression(in: trimmed) ?? trimmed
        let colors = colorTokens(in: gradient).compactMap(parseColor)
        if let first = colors.first, let last = colors.last, colors.count >= 2 {
            return .gradient([first, last], gradientStartPoint(in: gradient), gradientEndPoint(in: gradient))
        }
        if let color = colors.first {
            return .solid(color)
        }
        return nil
    }

    private static func colorTokens(in value: String) -> [String] {
        let pattern = "#[0-9A-Fa-f]{3,8}\\b|rgba?\\s*\\([^)]+\\)|hsla?\\s*\\([^)]+\\)|\\b(?:black|white|transparent)\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return []
        }

        let nsString = value as NSString
        return regex.matches(in: value, options: [], range: NSRange(location: 0, length: nsString.length))
            .compactMap { match in
                guard match.range.location != NSNotFound else { return nil }
                return nsString.substring(with: match.range)
            }
    }

    private static func parseColor(_ value: String) -> ProjectIconColor? {
        let trimmed = value
            .replacingOccurrences(of: "!important", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.caseInsensitiveCompare("transparent") == .orderedSame {
            return nil
        }
        if trimmed.caseInsensitiveCompare("white") == .orderedSame {
            return .white
        }
        if trimmed.caseInsensitiveCompare("black") == .orderedSame {
            return .black
        }
        if trimmed.hasPrefix("#") {
            return colorFromHex(trimmed)
        }
        if trimmed.range(of: "^rgba?\\s*\\(", options: [.regularExpression, .caseInsensitive]) != nil {
            return colorFromRGB(trimmed)
        }
        if trimmed.range(of: "^hsla?\\s*\\(", options: [.regularExpression, .caseInsensitive]) != nil {
            return colorFromHSL(trimmed)
        }
        return nil
    }

    private static func colorFromHex(_ value: String) -> ProjectIconColor? {
        let hex = String(value.dropFirst())
        let expanded: String
        switch hex.count {
        case 3, 4:
            expanded = hex.prefix(3).flatMap { [$0, $0] }.map(String.init).joined()
        case 6, 8:
            expanded = String(hex.prefix(6))
        default:
            return nil
        }

        guard let int = UInt32(expanded, radix: 16) else { return nil }
        return ProjectIconColor(hex: int)
    }

    private static func colorFromRGB(_ value: String) -> ProjectIconColor? {
        let components = functionArguments(in: value)
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard components.count >= 3 else { return nil }

        let red = rgbComponent(components[0])
        let green = rgbComponent(components[1])
        let blue = rgbComponent(components[2])
        let alpha = components.count >= 4 ? alphaComponent(components[3]) : 1
        guard alpha >= 0.1 else { return nil }

        return ProjectIconColor(red: red, green: green, blue: blue)
    }

    private static func colorFromHSL(_ value: String) -> ProjectIconColor? {
        let components = functionArguments(in: value)
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard components.count >= 3 else { return nil }

        let hue = positiveRemainder(Double(components[0].replacingOccurrences(of: "deg", with: "")) ?? 0, by: 360) / 360
        let saturation = percentageComponent(components[1])
        let lightness = percentageComponent(components[2])
        let alpha = components.count >= 4 ? alphaComponent(components[3]) : 1
        guard alpha >= 0.1 else { return nil }

        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let huePrime = hue * 6
        let x = chroma * (1 - abs(huePrime.truncatingRemainder(dividingBy: 2) - 1))
        let base: (Double, Double, Double)
        switch huePrime {
        case 0..<1: base = (chroma, x, 0)
        case 1..<2: base = (x, chroma, 0)
        case 2..<3: base = (0, chroma, x)
        case 3..<4: base = (0, x, chroma)
        case 4..<5: base = (x, 0, chroma)
        default: base = (chroma, 0, x)
        }
        let m = lightness - chroma / 2
        return ProjectIconColor(red: base.0 + m, green: base.1 + m, blue: base.2 + m)
    }

    private static func functionArguments(in value: String) -> String {
        guard let open = value.firstIndex(of: "("),
              let close = value.lastIndex(of: ")"),
              open < close else {
            return ""
        }
        return String(value[value.index(after: open)..<close])
    }

    private static func rgbComponent(_ value: String) -> Double {
        if value.hasSuffix("%") {
            return percentageComponent(value)
        }
        return min(max((Double(value) ?? 0) / 255, 0), 1)
    }

    private static func alphaComponent(_ value: String) -> Double {
        if value.hasSuffix("%") {
            return percentageComponent(value)
        }
        return min(max(Double(value) ?? 1, 0), 1)
    }

    private static func percentageComponent(_ value: String) -> Double {
        min(max((Double(value.replacingOccurrences(of: "%", with: "")) ?? 0) / 100, 0), 1)
    }

    private static func firstLinearGradientExpression(in value: String) -> String? {
        let pattern = "\\b(?:repeating-)?linear-gradient\\s*\\("
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }

        let nsString = value as NSString
        let range = NSRange(location: 0, length: nsString.length)
        guard let match = regex.firstMatch(in: value, options: [], range: range) else {
            return nil
        }
        guard let expressionRange = balancedFunctionRange(startingAt: match.range.location, in: value) else {
            return nil
        }
        return nsString.substring(with: expressionRange)
    }

    private static func balancedFunctionRange(startingAt start: Int, in value: String) -> NSRange? {
        let nsString = value as NSString
        let length = nsString.length
        var depth = 0
        var hasOpenedFunction = false

        for index in start..<length {
            let character = nsString.character(at: index)
            if character == 40 {
                depth += 1
                hasOpenedFunction = true
            } else if character == 41 {
                depth -= 1
                if hasOpenedFunction && depth == 0 {
                    return NSRange(location: start, length: index - start + 1)
                }
            }
        }

        return nil
    }

    private static func gradientStartPoint(in value: String) -> UnitPoint {
        let direction = gradientDirection(in: value)
        return UnitPoint(x: 0.5 - direction.dx / 2, y: 0.5 - direction.dy / 2)
    }

    private static func gradientEndPoint(in value: String) -> UnitPoint {
        let direction = gradientDirection(in: value)
        return UnitPoint(x: 0.5 + direction.dx / 2, y: 0.5 + direction.dy / 2)
    }

    private static func gradientDirection(in value: String) -> (dx: Double, dy: Double) {
        let firstArgument = firstGradientArgument(in: value).lowercased()
        if firstArgument.hasPrefix("to ") {
            var dx = 0.0
            var dy = 0.0
            if firstArgument.contains("left") {
                dx = -1
            } else if firstArgument.contains("right") {
                dx = 1
            }
            if firstArgument.contains("top") {
                dy = -1
            } else if firstArgument.contains("bottom") {
                dy = 1
            }
            let length = sqrt(dx * dx + dy * dy)
            return length > 0 ? (dx / length, dy / length) : (1, 0)
        }
        if firstArgument.hasSuffix("deg"),
           let degrees = Double(firstArgument.dropLast(3).trimmingCharacters(in: .whitespacesAndNewlines)) {
            let radians = positiveRemainder(degrees, by: 360) * .pi / 180
            return (sin(radians), -cos(radians))
        }
        return (1, 0)
    }

    private static func firstGradientArgument(in value: String) -> String {
        let arguments = functionArguments(in: value)
        var depth = 0
        var component = ""
        for character in arguments {
            if character == "(" {
                depth += 1
            } else if character == ")" {
                depth -= 1
            }
            if character == "," && depth == 0 {
                break
            }
            component.append(character)
        }
        return component.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func positiveRemainder(_ value: Double, by divisor: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: divisor)
        return remainder >= 0 ? remainder : remainder + divisor
    }
}

private struct ProjectIconColor {
    let red: Double
    let green: Double
    let blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = Self.clamped(red)
        self.green = Self.clamped(green)
        self.blue = Self.clamped(blue)
    }

    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    static let black = ProjectIconColor(red: 0, green: 0, blue: 0)
    static let white = ProjectIconColor(red: 1, green: 1, blue: 1)

    static func surfaceStrong(colorScheme: ColorScheme) -> ProjectIconColor {
        colorScheme == .dark ? ProjectIconColor(hex: 0x1A212B) : .white
    }

    static func pageBackgroundColors(colorScheme: ColorScheme) -> [ProjectIconColor] {
        if colorScheme == .dark {
            return [
                ProjectIconColor(hex: 0x0D1118),
                ProjectIconColor(hex: 0x111722),
                ProjectIconColor(hex: 0x141B25)
            ]
        }
        return [
            ProjectIconColor(hex: 0xDDE7FB),
            ProjectIconColor(hex: 0xEEF3FA),
            ProjectIconColor(hex: 0xF6F9FC)
        ]
    }

    var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue)
    }

    var relativeLuminance: Double {
        0.2126 * linearized(red) + 0.7152 * linearized(green) + 0.0722 * linearized(blue)
    }

    var isNearWhiteNeutral: Bool {
        min(red, green, blue) >= 0.94 && (max(red, green, blue) - min(red, green, blue)) <= 0.06
    }

    var hsl: (hue: Double, saturation: Double, lightness: Double) {
        let maxComponent = max(red, green, blue)
        let minComponent = min(red, green, blue)
        let delta = maxComponent - minComponent
        let lightness = (maxComponent + minComponent) / 2

        guard delta > 0 else {
            return (0, 0, lightness)
        }

        let saturation = delta / (1 - abs(2 * lightness - 1))
        let hue: Double
        if maxComponent == red {
            hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6) / 6
        } else if maxComponent == green {
            hue = (((blue - red) / delta) + 2) / 6
        } else {
            hue = (((red - green) / delta) + 4) / 6
        }
        return (Self.positiveRemainder(hue, by: 1), saturation, lightness)
    }

    func contrastRatio(with other: ProjectIconColor) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    func perceptualDistance(to other: ProjectIconColor) -> Double {
        let redDelta = red - other.red
        let greenDelta = green - other.green
        let blueDelta = blue - other.blue
        return sqrt(redDelta * redDelta * 0.30 + greenDelta * greenDelta * 0.59 + blueDelta * blueDelta * 0.11)
    }

    static func average(_ colors: [ProjectIconColor]) -> ProjectIconColor {
        guard !colors.isEmpty else { return .white }
        let count = Double(colors.count)
        return ProjectIconColor(
            red: colors.reduce(0) { $0 + $1.red } / count,
            green: colors.reduce(0) { $0 + $1.green } / count,
            blue: colors.reduce(0) { $0 + $1.blue } / count
        )
    }

    static func hsl(hue: Double, saturation: Double, lightness: Double) -> ProjectIconColor {
        let hue = positiveRemainder(hue, by: 1)
        let saturation = clamped(saturation)
        let lightness = clamped(lightness)
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let huePrime = hue * 6
        let x = chroma * (1 - abs(huePrime.truncatingRemainder(dividingBy: 2) - 1))
        let base: (Double, Double, Double)
        switch huePrime {
        case 0..<1: base = (chroma, x, 0)
        case 1..<2: base = (x, chroma, 0)
        case 2..<3: base = (0, chroma, x)
        case 3..<4: base = (0, x, chroma)
        case 4..<5: base = (x, 0, chroma)
        default: base = (chroma, 0, x)
        }
        let m = lightness - chroma / 2
        return ProjectIconColor(red: base.0 + m, green: base.1 + m, blue: base.2 + m)
    }

    private static func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private func linearized(_ component: Double) -> Double {
        if component <= 0.03928 {
            return component / 12.92
        }
        return pow((component + 0.055) / 1.055, 2.4)
    }

    private static func positiveRemainder(_ value: Double, by divisor: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: divisor)
        return remainder >= 0 ? remainder : remainder + divisor
    }
}

private enum ProjectIconBorder {
    static func shouldShowBorder(
        iconBackgroundColors: [ProjectIconColor],
        placement: ProjectIconFallbackPlacement,
        colorScheme: ColorScheme
    ) -> Bool {
        let hostColors = hostBackgroundColors(for: placement, colorScheme: colorScheme)
        return iconBackgroundColors.contains { iconColor in
            hostColors.contains { hostColor in
                iconColor.contrastRatio(with: hostColor) < 1.18 ||
                    iconColor.perceptualDistance(to: hostColor) < 0.08
            }
        }
    }

    static func color(for iconBackgroundColors: [ProjectIconColor]) -> Color {
        let representative = ProjectIconColor.average(iconBackgroundColors)
        if representative.relativeLuminance > 0.5 {
            return Color.black.opacity(0.08)
        }
        return Color.white.opacity(0.12)
    }

    private static func hostBackgroundColors(
        for placement: ProjectIconFallbackPlacement,
        colorScheme: ColorScheme
    ) -> [ProjectIconColor] {
        switch placement {
        case .listItem:
            return [ProjectIconColor.surfaceStrong(colorScheme: colorScheme)]
        case .pageBackground:
            return ProjectIconColor.pageBackgroundColors(colorScheme: colorScheme)
        }
    }
}

private enum ProjectIconForegroundColor {
    private static let minimumContrast = 3.4

    static func color(for backgroundColors: [ProjectIconColor]) -> Color {
        let backgrounds = backgroundColors.isEmpty ? [.white] : backgroundColors
        if backgrounds.allSatisfy(\.isNearWhiteNeutral) {
            return AppTheme.ink
        }

        let representative = ProjectIconColor.average(backgrounds)
        let backgroundHSL = representative.hsl
        let averageLuminance = backgrounds.reduce(0) { $0 + $1.relativeLuminance } / Double(backgrounds.count)
        let targetLightness = averageLuminance > 0.42 ? 0.22 : 0.86
        let saturation = backgroundHSL.saturation < 0.08 ?
            0.34 :
            min(max(backgroundHSL.saturation + 0.18, 0.42), 0.72)

        let candidates = [
            candidate(hue: backgroundHSL.hue + 0.5, saturation: saturation, lightness: targetLightness, priority: 3),
            candidate(hue: backgroundHSL.hue + 150.0 / 360.0, saturation: saturation, lightness: targetLightness, priority: 2),
            candidate(hue: backgroundHSL.hue - 150.0 / 360.0, saturation: saturation, lightness: targetLightness, priority: 2),
            candidate(hue: backgroundHSL.hue + 120.0 / 360.0, saturation: saturation, lightness: targetLightness, priority: 1),
            candidate(hue: backgroundHSL.hue - 120.0 / 360.0, saturation: saturation, lightness: targetLightness, priority: 1)
        ]

        if let selected = candidates
            .map({ scoredCandidate($0, against: backgrounds) })
            .filter({ $0.minimumContrast >= minimumContrast })
            .max(by: { $0.score < $1.score }) {
            return selected.color.swiftUIColor
        }

        return [ProjectIconColor.black, .white]
            .map { scoredCandidate(($0, 0), against: backgrounds) }
            .max(by: { $0.minimumContrast < $1.minimumContrast })?
            .color
            .swiftUIColor ?? AppTheme.contentAccent
    }

    private static func candidate(
        hue: Double,
        saturation: Double,
        lightness: Double,
        priority: Double
    ) -> (color: ProjectIconColor, priority: Double) {
        (ProjectIconColor.hsl(hue: hue, saturation: saturation, lightness: lightness), priority)
    }

    private static func scoredCandidate(
        _ candidate: (color: ProjectIconColor, priority: Double),
        against backgrounds: [ProjectIconColor]
    ) -> (color: ProjectIconColor, minimumContrast: Double, score: Double) {
        let minimumContrast = backgrounds
            .map { candidate.color.contrastRatio(with: $0) }
            .min() ?? 1
        return (
            candidate.color,
            minimumContrast,
            min(minimumContrast, 7) + candidate.priority
        )
    }
}

#Preview("Project Icon Fallbacks - List Light") {
    ProjectIconFallbackDebugPreview(layout: .list)
        .preferredColorScheme(.light)
}

#Preview("Project Icon Fallbacks - Grid Light") {
    ProjectIconFallbackDebugPreview(layout: .grid)
        .preferredColorScheme(.light)
}

#Preview("Project Icon Fallbacks - List Dark") {
    ProjectIconFallbackDebugPreview(layout: .list)
        .preferredColorScheme(.dark)
}

#Preview("Project Icon Fallbacks - Grid Dark") {
    ProjectIconFallbackDebugPreview(layout: .grid)
        .preferredColorScheme(.dark)
}

private struct ProjectIconFallbackDebugPreview: View {
    let layout: ProjectIconFallbackDebugLayout

    private let samples: [ProjectIconFallbackDebugSample] = [
        .init(title: "Missing", background: nil, symbolName: "doc.text.fill"),
        .init(title: "White", background: "#FFFFFF", symbolName: "doc.text.fill"),
        .init(title: "Near white", background: "#F8F9FB", symbolName: "doc.text.fill"),
        .init(title: "Page blue", background: "#DDE7FB", symbolName: "doc.text.fill"),
        .init(title: "Pale gray", background: "#EEF3FA", symbolName: "folder.fill"),
        .init(title: "Warm paper", background: "#FFF7E6", symbolName: "doc.text.fill"),
        .init(title: "Gold", background: "#FFD100", symbolName: "doc.text.fill"),
        .init(title: "Sky", background: "#4CC8FF", symbolName: "folder.fill"),
        .init(title: "Leaf", background: "#0FEA94", symbolName: "doc.text.fill"),
        .init(title: "Coral", background: "#FF5553", symbolName: "folder.fill"),
        .init(title: "Dark page", background: "#111722", symbolName: "doc.text.fill"),
        .init(title: "Dark surface", background: "#1A212B", symbolName: "folder.fill"),
        .init(title: "Soft gradient", background: "linear-gradient(135deg, #F6F9FC, #DDE7FB)", symbolName: "doc.text.fill"),
        .init(title: "Vivid gradient", background: "linear-gradient(135deg, #4CC8FF, #C47EFF)", symbolName: "folder.fill")
    ]

    private let columns = [
        GridItem(.adaptive(minimum: 82), spacing: 18, alignment: .top)
    ]

    var body: some View {
        ZStack {
            AppPageBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    previewSectionTitle(layout.title)

                    switch layout {
                    case .list:
                        listPreview
                    case .grid:
                        gridPreview
                    }
                }
                .padding(20)
            }
        }
    }

    private var listPreview: some View {
        VStack(spacing: 8) {
            ForEach(samples) { sample in
                HStack(spacing: 12) {
                    previewIcon(sample, size: 28, placement: .listItem)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(sample.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppTheme.listItemTitle)
                        Text(sample.background ?? "fallback surface")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AppTheme.surfaceStrong, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var gridPreview: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
            ForEach(samples) { sample in
                VStack(spacing: 6) {
                    previewIcon(sample, size: 60, placement: .pageBackground)

                    Text(sample.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.contentPrimary)
                        .lineLimit(1)
                }
                .frame(width: 82)
            }
        }
    }

    private func previewSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(AppTheme.textSecondary)
            .textCase(.uppercase)
            .padding(.horizontal, 4)
    }

    private func previewIcon(
        _ sample: ProjectIconFallbackDebugSample,
        size: CGFloat,
        placement: ProjectIconFallbackPlacement
    ) -> some View {
        ProjectIconImage(
            iconURL: nil,
            fallbackSymbolName: sample.symbolName,
            size: size,
            cornerRadius: size * 0.225,
            fallbackBackground: .webPageTop(sample.background),
            fallbackPlacement: placement
        )
    }
}

private enum ProjectIconFallbackDebugLayout {
    case list
    case grid

    var title: String {
        switch self {
        case .list:
            "List row host"
        case .grid:
            "Grid page host"
        }
    }
}

private struct ProjectIconFallbackDebugSample: Identifiable {
    let id = UUID()
    let title: String
    let background: String?
    let symbolName: String
}
