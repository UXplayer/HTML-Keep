import Foundation

enum BackgroundColorExtractor {
    private static let fallbackColor = "#FFFFFF"

    private enum Edge {
        case top
        case bottom

        var normalizedY: Double {
            switch self {
            case .top: return 0
            case .bottom: return 1
            }
        }
    }

    static func extractColors(from htmlContent: String) -> (top: String, bottom: String) {
        extractColors(from: htmlContent, stylesheetContents: [])
    }

    static func extractColors(
        from htmlContent: String,
        htmlFileURL: URL,
        projectFolderURL: URL,
        fileManager: FileManager = .default
    ) -> (top: String, bottom: String) {
        let stylesheetContents = extractLinkedStylesheetContents(
            from: htmlContent,
            htmlFileURL: htmlFileURL,
            projectFolderURL: projectFolderURL,
            fileManager: fileManager
        )
        return extractColors(from: htmlContent, stylesheetContents: stylesheetContents)
    }

    private static func extractColors(
        from htmlContent: String,
        stylesheetContents: [String]
    ) -> (top: String, bottom: String) {
        let htmlWithoutComments = removeCSSComments(from: htmlContent)
        let stylesheetsWithoutComments = stylesheetContents.map(removeCSSComments)
        let cssVariableSource = (stylesheetsWithoutComments + extractStyleBlocks(from: htmlWithoutComments))
            .map(removeCSSAtRuleBlocks)
            .joined(separator: "\n")
        let cssVariables = extractCSSVariables(from: cssVariableSource)

        if let (top, bottom) = extractPageLevelColors(
            from: htmlWithoutComments,
            stylesheetContents: stylesheetsWithoutComments,
            variables: cssVariables
        ) {
            return (top, bottom)
        }
        if let solidColor = extractSolidColor(from: htmlWithoutComments, variables: cssVariables) {
            return (solidColor, solidColor)
        }
        return (fallbackColor, fallbackColor)
    }

    private static func removeCSSComments(from htmlContent: String) -> String {
        htmlContent.replacingOccurrences(
            of: "/\\*[\\s\\S]*?\\*/",
            with: "",
            options: .regularExpression
        )
    }

    private static func removeCSSAtRuleBlocks(from cssContent: String) -> String {
        var result = ""
        var index = cssContent.startIndex

        while index < cssContent.endIndex {
            guard cssContent[index] == "@" else {
                result.append(cssContent[index])
                index = cssContent.index(after: index)
                continue
            }

            var cursor = index
            while cursor < cssContent.endIndex,
                  cssContent[cursor] != "{",
                  cssContent[cursor] != ";" {
                cursor = cssContent.index(after: cursor)
            }

            guard cursor < cssContent.endIndex, cssContent[cursor] == "{" else {
                result.append(cssContent[index])
                index = cssContent.index(after: index)
                continue
            }

            var depth = 0
            var blockEnd = cursor
            while blockEnd < cssContent.endIndex {
                if cssContent[blockEnd] == "{" {
                    depth += 1
                } else if cssContent[blockEnd] == "}" {
                    depth -= 1
                    if depth == 0 {
                        blockEnd = cssContent.index(after: blockEnd)
                        break
                    }
                }
                blockEnd = cssContent.index(after: blockEnd)
            }
            index = blockEnd
        }

        return result
    }

    private static func extractCSSVariables(from htmlContent: String) -> [String: String] {
        var variables: [String: String] = [:]
        let pattern = "--([a-zA-Z0-9-]+)\\s*:\\s*([^;]+);"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return variables
        }

        let nsString = htmlContent as NSString
        let matches = regex.matches(in: htmlContent, options: [], range: NSRange(location: 0, length: nsString.length))

        for match in matches {
            if match.numberOfRanges >= 3 {
                let nameRange = match.range(at: 1)
                let valueRange = match.range(at: 2)
                if nameRange.location != NSNotFound && valueRange.location != NSNotFound {
                    let name = nsString.substring(with: nameRange)
                    let value = nsString.substring(with: valueRange).trimmingCharacters(in: .whitespaces)
                    variables[name] = value
                }
            }
        }
        return variables
    }

    private static func extractPageLevelColors(
        from htmlContent: String,
        stylesheetContents: [String],
        variables: [String: String]
    ) -> (top: String, bottom: String)? {
        var rootColors: (top: String, bottom: String)?
        var htmlColors: (top: String, bottom: String)?
        var bodyColors: (top: String, bottom: String)?

        for styleBlock in stylesheetContents + extractStyleBlocks(from: htmlContent) {
            for rule in extractCSSRules(from: styleBlock) {
                guard let colors = extractColorsFromDeclarations(rule.declarations, variables: variables) else {
                    continue
                }

                for selector in rule.selectors {
                    if selectorTargetsRoot(selector) {
                        rootColors = colors
                    }
                    if selectorTargetsElement(selector, element: "html") {
                        htmlColors = colors
                    }
                    if selectorTargetsElement(selector, element: "body") {
                        bodyColors = colors
                    }
                }
            }
        }

        if let inlineHTMLColors = extractInlineStyleColors(for: "html", from: htmlContent, variables: variables) {
            htmlColors = inlineHTMLColors
        }
        if let inlineBodyColors = extractInlineStyleColors(for: "body", from: htmlContent, variables: variables) {
            bodyColors = inlineBodyColors
        }

        return bodyColors ?? htmlColors ?? rootColors
    }

    private static func extractLinkedStylesheetContents(
        from htmlContent: String,
        htmlFileURL: URL,
        projectFolderURL: URL,
        fileManager: FileManager
    ) -> [String] {
        let pattern = "<link\\b[^>]*>"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return []
        }

        let nsString = htmlContent as NSString
        let matches = regex.matches(in: htmlContent, options: [], range: NSRange(location: 0, length: nsString.length))

        return matches.compactMap { match in
            let tag = nsString.substring(with: match.range)
            guard let rel = attributeValue(named: "rel", in: tag)?.lowercased(),
                  rel.split(whereSeparator: { $0.isWhitespace }).contains(where: { $0 == "stylesheet" }),
                  let href = attributeValue(named: "href", in: tag),
                  let stylesheetURL = localStylesheetURL(
                    fromHref: href,
                    htmlFileURL: htmlFileURL,
                    projectFolderURL: projectFolderURL
                  ),
                  stylesheetURL.pathExtension.lowercased() == "css",
                  fileManager.fileExists(atPath: stylesheetURL.path) else {
                return nil
            }
            return try? String(contentsOf: stylesheetURL, encoding: .utf8)
        }
    }

    private static func attributeValue(named name: String, in tag: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let pattern = "\\b\(escapedName)\\s*=\\s*(?:([\"'])([\\s\\S]*?)\\1|([^\\s\"'=<>`]+))"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }

        let nsString = tag as NSString
        let range = NSRange(location: 0, length: nsString.length)
        guard let match = regex.firstMatch(in: tag, options: [], range: range) else {
            return nil
        }

        if match.numberOfRanges >= 3, match.range(at: 2).location != NSNotFound {
            return nsString.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if match.numberOfRanges >= 4, match.range(at: 3).location != NSNotFound {
            return nsString.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func localStylesheetURL(
        fromHref href: String,
        htmlFileURL: URL,
        projectFolderURL: URL
    ) -> URL? {
        let trimmedHref = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHref.isEmpty,
              !trimmedHref.hasPrefix("#"),
              !trimmedHref.hasPrefix("//"),
              let components = URLComponents(string: trimmedHref),
              components.scheme == nil,
              components.host == nil,
              let path = components.path.removingPercentEncoding,
              !path.isEmpty else {
            return nil
        }

        let candidateURL: URL
        if path.hasPrefix("/") {
            candidateURL = projectFolderURL.appendingPathComponent(String(path.dropFirst()), isDirectory: false)
        } else {
            candidateURL = htmlFileURL.deletingLastPathComponent().appendingPathComponent(path, isDirectory: false)
        }

        let standardizedCandidate = candidateURL.standardizedFileURL
        let standardizedRoot = projectFolderURL.standardizedFileURL
        guard fileURL(standardizedCandidate, isInside: standardizedRoot) else {
            return nil
        }
        return standardizedCandidate
    }

    private static func fileURL(_ fileURL: URL, isInside rootURL: URL) -> Bool {
        let filePath = fileURL.path
        let rootPath = rootURL.path
        return filePath == rootPath || filePath.hasPrefix(rootPath + "/")
    }

    private static func extractStyleBlocks(from htmlContent: String) -> [String] {
        let pattern = "<style\\b[^>]*>([\\s\\S]*?)</style>"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return []
        }

        let nsString = htmlContent as NSString
        let matches = regex.matches(in: htmlContent, options: [], range: NSRange(location: 0, length: nsString.length))

        return matches.compactMap { match in
            guard match.numberOfRanges >= 2, match.range(at: 1).location != NSNotFound else {
                return nil
            }
            return nsString.substring(with: match.range(at: 1))
        }
    }

    private static func extractCSSRules(from cssContent: String) -> [(selectors: [String], declarations: String)] {
        let pattern = "([^{}]+)\\{([^{}]*)\\}"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let nsString = cssContent as NSString
        let matches = regex.matches(in: cssContent, options: [], range: NSRange(location: 0, length: nsString.length))

        return matches.compactMap { match in
            guard match.numberOfRanges >= 3 else {
                return nil
            }

            let selectors = nsString.substring(with: match.range(at: 1))
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let declarations = nsString.substring(with: match.range(at: 2))

            guard !selectors.isEmpty else {
                return nil
            }
            return (selectors, declarations)
        }
    }

    private static func extractInlineStyleColors(
        for element: String,
        from htmlContent: String,
        variables: [String: String]
    ) -> (top: String, bottom: String)? {
        let pattern = "<\(element)\\b[^>]*\\sstyle\\s*=\\s*([\"'])([\\s\\S]*?)\\1"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }

        let nsString = htmlContent as NSString
        let range = NSRange(location: 0, length: nsString.length)
        guard let match = regex.firstMatch(in: htmlContent, options: [], range: range),
              match.numberOfRanges >= 3,
              match.range(at: 2).location != NSNotFound else {
            return nil
        }

        let declarations = nsString.substring(with: match.range(at: 2))
        return extractColorsFromDeclarations(declarations, variables: variables)
    }

    private static func selectorTargetsRoot(_ selector: String) -> Bool {
        normalizedSimpleSelector(selector) == ":root"
    }

    private static func selectorTargetsElement(_ selector: String, element: String) -> Bool {
        let selector = normalizedSimpleSelector(selector)

        guard !selector.isEmpty else {
            return false
        }
        if selector == element {
            return true
        }

        let simplePrefixes = ["\(element).", "\(element)#", "\(element)[", "\(element):"]
        return simplePrefixes.contains { selector.hasPrefix($0) }
    }

    private static func normalizedSimpleSelector(_ selector: String) -> String {
        let normalized = selector
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        if normalized.contains(" ")
            || normalized.contains(">")
            || normalized.contains("+")
            || normalized.contains("~") {
            return ""
        }

        return normalized
    }

    private static func parseGradientColors(_ gradient: String, variables: [String: String]) -> [String] {
        extractColorTokens(from: gradient, variables: variables).compactMap(normalizeColor)
    }

    private static func complexGradientBackgroundNeedsPreservation(_ value: String) -> Bool {
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if normalizedValue.range(
            of: "\\b(?:radial|repeating-radial|conic|repeating-conic)-gradient\\s*\\(",
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            return true
        }

        let linearGradients = linearGradientExpressions(in: normalizedValue)
        return linearGradients.count != 1
    }

    private static func linearGradientExpressions(in value: String) -> [String] {
        let pattern = "(?:repeating-)?linear-gradient\\s*\\("

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return []
        }

        let nsString = value as NSString
        let matches = regex.matches(in: value, options: [], range: NSRange(location: 0, length: nsString.length))

        return matches.compactMap { match in
            guard let expressionRange = balancedFunctionRange(startingAt: match.range.location, in: value) else {
                return nil
            }
            return nsString.substring(with: expressionRange)
        }
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

    private static func linearGradientIsVertical(_ gradient: String) -> Bool {
        guard let arguments = gradientArguments(in: gradient) else {
            return false
        }

        let firstArgument = firstTopLevelComponent(in: arguments)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !firstArgument.isEmpty else {
            return true
        }

        if firstArgument.hasPrefix("to ") {
            return firstArgument == "to bottom" || firstArgument == "to top"
        }

        if firstArgument.hasSuffix("deg") {
            let degreesText = firstArgument.dropLast(3).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let degrees = Double(degreesText) else {
                return false
            }
            let normalizedDegrees = positiveRemainder(degrees, by: 360)
            return anglesMatch(normalizedDegrees, 0) || anglesMatch(normalizedDegrees, 180)
        }

        return true
    }

    private static func verticalGradientColors(
        from gradient: String,
        variables: [String: String]
    ) -> (top: String, bottom: String)? {
        let colors = parseGradientColors(gradient, variables: variables)
        guard let first = colors.first else {
            return nil
        }

        let isToTop = gradientDirectionIsToTop(gradient)
        let last = colors.last ?? first
        return isToTop ? (last, first) : (first, last)
    }

    private static func horizontalEdgeGradient(
        from gradient: String,
        variables: [String: String],
        edge: Edge
    ) -> String? {
        let colors = parseGradientColors(gradient, variables: variables)
        guard !colors.isEmpty else {
            return nil
        }
        guard let direction = linearGradientDirection(in: gradient), abs(direction.dx) > 0.001 else {
            return nil
        }

        guard colors.count > 1 else {
            return colors[0]
        }

        let colorStops = colors.enumerated().map { index, color in
            let normalizedPosition = Double(index) / Double(colors.count - 1)
            return (
                color: color,
                cssPosition: horizontalEdgeStopPosition(
                    normalizedGradientPosition: normalizedPosition,
                    direction: direction,
                    edge: edge
                )
            )
        }
        let orderedStops = direction.dx > 0 ? colorStops : colorStops.reversed()
        let stops = orderedStops.map { "\($0.color) \($0.cssPosition)" }.joined(separator: ", ")
        return "linear-gradient(to right, \(stops))"
    }

    private static func linearGradientDirection(in gradient: String) -> (dx: Double, dy: Double)? {
        guard let arguments = gradientArguments(in: gradient) else {
            return nil
        }

        let firstArgument = firstTopLevelComponent(in: arguments)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

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
            if length > 0 {
                return (dx / length, dy / length)
            }
        }

        if firstArgument.hasSuffix("deg") {
            let degreesText = firstArgument.dropLast(3).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let degrees = Double(degreesText) else {
                return nil
            }
            let radians = positiveRemainder(degrees, by: 360) * .pi / 180
            return (sin(radians), -cos(radians))
        }

        return (0, 1)
    }

    private static func horizontalEdgeStopPosition(
        normalizedGradientPosition: Double,
        direction: (dx: Double, dy: Double),
        edge: Edge
    ) -> String {
        let horizontalCoefficient = 0.5
            + (normalizedGradientPosition - 0.5) * abs(direction.dx) / direction.dx
        let verticalCoefficient = -direction.dy * (edge.normalizedY - 0.5) / direction.dx
            + (normalizedGradientPosition - 0.5) * abs(direction.dy) / direction.dx

        return cssViewportLengthExpression(
            vwCoefficient: horizontalCoefficient,
            vhCoefficient: verticalCoefficient
        )
    }

    private static func cssViewportLengthExpression(
        vwCoefficient: Double,
        vhCoefficient: Double
    ) -> String {
        let vwTerm = cssViewportTerm(coefficient: vwCoefficient * 100, unit: "vw")
        let vhTerm = cssViewportTerm(coefficient: vhCoefficient * 100, unit: "vh")
        let terms = [vwTerm, vhTerm].compactMap { $0 }

        guard !terms.isEmpty else {
            return "0"
        }
        if terms.count == 1 {
            return terms[0]
        }

        let joined = terms.enumerated().map { index, term in
            if index == 0 {
                return term
            }
            return term.hasPrefix("-") ? "- \(term.dropFirst())" : "+ \(term)"
        }.joined(separator: " ")

        return "calc(\(joined))"
    }

    private static func cssViewportTerm(coefficient: Double, unit: String) -> String? {
        if abs(coefficient) < 0.001 {
            return nil
        }

        let roundedCoefficient = abs(coefficient.rounded() - coefficient) < 0.001
            ? coefficient.rounded()
            : coefficient
        return "\(formatCSSNumber(roundedCoefficient))\(unit)"
    }

    private static func formatCSSNumber(_ value: Double) -> String {
        let formatted = String(format: "%.4f", value)
        return formatted
            .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
    }

    private static func gradientDirectionIsToTop(_ gradient: String) -> Bool {
        guard let arguments = gradientArguments(in: gradient) else {
            return false
        }

        let firstArgument = firstTopLevelComponent(in: arguments)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if firstArgument == "to top" {
            return true
        }
        if firstArgument.hasSuffix("deg") {
            let degreesText = firstArgument.dropLast(3).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let degrees = Double(degreesText) else {
                return false
            }
            return anglesMatch(positiveRemainder(degrees, by: 360), 0)
        }

        return false
    }

    private static func gradientArguments(in gradient: String) -> String? {
        guard let openParen = gradient.firstIndex(of: "("),
              let closeParen = gradient.lastIndex(of: ")"),
              openParen < closeParen else {
            return nil
        }
        return String(gradient[gradient.index(after: openParen)..<closeParen])
    }

    private static func firstTopLevelComponent(in value: String) -> String {
        var depth = 0
        var component = ""

        for character in value {
            if character == "(" {
                depth += 1
            } else if character == ")" {
                depth -= 1
            }

            if character == "," && depth == 0 {
                return component
            }
            component.append(character)
        }

        return component
    }

    private static func positiveRemainder(_ value: Double, by divisor: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: divisor)
        return remainder >= 0 ? remainder : remainder + divisor
    }

    private static func anglesMatch(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) < 0.001 || abs(abs(lhs - rhs) - 360) < 0.001
    }

    private static func extractColorsFromDeclarations(
        _ declarations: String,
        variables: [String: String]
    ) -> (top: String, bottom: String)? {
        let pattern = "\\b(background(?:-color)?)\\s*:\\s*([^;]+)"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }

        let nsString = declarations as NSString
        let matches = regex.matches(in: declarations, options: [], range: NSRange(location: 0, length: nsString.length))
        var colors: (top: String, bottom: String)?

        for match in matches {
            guard match.numberOfRanges >= 3, match.range(at: 2).location != NSNotFound else {
                continue
            }
            let value = nsString.substring(with: match.range(at: 2))
            if let parsedColors = parseBackgroundValue(value, variables: variables) {
                colors = parsedColors
            }
        }

        return colors
    }

    private static func parseBackgroundValue(
        _ value: String,
        variables: [String: String]
    ) -> (top: String, bottom: String)? {
        let resolvedValue = resolveCSSVariables(in: value, variables: variables)

        if resolvedValue.range(of: "gradient\\s*\\(", options: [.regularExpression, .caseInsensitive]) != nil {
            if complexGradientBackgroundNeedsPreservation(resolvedValue) {
                let preservedBackground = sanitizeBackgroundValue(resolvedValue)
                return (preservedBackground, preservedBackground)
            }

            guard let gradient = linearGradientExpressions(in: resolvedValue).first else {
                return nil
            }
            if linearGradientIsVertical(gradient) {
                return verticalGradientColors(from: gradient, variables: variables)
            }
            guard let topEdgeGradient = horizontalEdgeGradient(from: gradient, variables: variables, edge: .top),
                  let bottomEdgeGradient = horizontalEdgeGradient(from: gradient, variables: variables, edge: .bottom) else {
                return nil
            }
            return (topEdgeGradient, bottomEdgeGradient)
        }

        guard let color = extractColorTokens(from: resolvedValue, variables: variables).compactMap(normalizeColor).first else {
            return nil
        }
        return (color, color)
    }

    private static func extractSolidColor(from htmlContent: String, variables: [String: String]) -> String? {
        let patterns = [
            "background-color\\s*:\\s*([^;]+);",
            "background\\s*:\\s*([^;]+);"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let nsString = htmlContent as NSString
                let matches = regex.matches(in: htmlContent, options: [], range: NSRange(location: 0, length: nsString.length))

                for match in matches {
                    if match.numberOfRanges >= 2 {
                        let colorRange = match.range(at: 1)
                        let colorValue = nsString.substring(with: colorRange).trimmingCharacters(in: .whitespacesAndNewlines)

                        if colorValue.range(of: "gradient\\s*\\(", options: [.regularExpression, .caseInsensitive]) != nil {
                            continue
                        }

                        if let solidColor = parseBackgroundValue(colorValue, variables: variables)?.top {
                            return solidColor
                        }
                    }
                }
            }
        }
        return nil
    }

    private static func sanitizeBackgroundValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "!important", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractColorTokens(from value: String, variables: [String: String]) -> [String] {
        let resolvedValue = resolveCSSVariables(in: value, variables: variables)
        let colorPattern = "#[0-9A-Fa-f]{3,8}\\b|rgba?\\s*\\([^)]+\\)|hsla?\\s*\\([^)]+\\)|\\b(?:black|white|transparent)\\b"

        guard let regex = try? NSRegularExpression(pattern: colorPattern, options: .caseInsensitive) else {
            return []
        }

        let nsString = resolvedValue as NSString
        let matches = regex.matches(in: resolvedValue, options: [], range: NSRange(location: 0, length: nsString.length))

        return matches.compactMap { match in
            guard match.range.location != NSNotFound else {
                return nil
            }
            return nsString.substring(with: match.range)
        }
    }

    private static func resolveCSSVariables(in value: String, variables: [String: String]) -> String {
        var resolvedValue = value
        let pattern = "var\\(\\s*--([a-zA-Z0-9-]+)\\s*(?:,\\s*([^)]*))?\\)"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return resolvedValue
        }

        for _ in 0..<8 {
            let nsString = resolvedValue as NSString
            let matches = regex.matches(in: resolvedValue, options: [], range: NSRange(location: 0, length: nsString.length))
            if matches.isEmpty {
                break
            }

            for match in matches.reversed() {
                guard match.numberOfRanges >= 2, match.range(at: 1).location != NSNotFound else {
                    continue
                }

                let name = nsString.substring(with: match.range(at: 1))
                let fallback: String
                if match.numberOfRanges >= 3, match.range(at: 2).location != NSNotFound {
                    fallback = nsString.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    fallback = ""
                }
                let replacement = variables[name] ?? fallback
                resolvedValue = (resolvedValue as NSString).replacingCharacters(in: match.range, with: replacement)
            }
        }

        return resolvedValue
    }

    private static func normalizeColor(_ color: String) -> String? {
        let trimmed = color
            .replacingOccurrences(of: "!important", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.caseInsensitiveCompare("transparent") == .orderedSame {
            return nil
        }
        if trimmed.caseInsensitiveCompare("white") == .orderedSame {
            return "#FFFFFF"
        }
        if trimmed.caseInsensitiveCompare("black") == .orderedSame {
            return "#000000"
        }

        if trimmed.range(of: "^rgb\\s*\\(", options: [.regularExpression, .caseInsensitive]) != nil {
            return convertToHex(color)
        }
        if trimmed.range(of: "^rgba\\s*\\(", options: [.regularExpression, .caseInsensitive]) != nil {
            return rgbaIsTransparent(trimmed) ? nil : trimmed
        }
        if trimmed.range(of: "^hsla?\\s*\\(", options: [.regularExpression, .caseInsensitive]) != nil {
            return trimmed
        }
        if trimmed.hasPrefix("#") {
            return normalizeHexColor(trimmed)
        }
        return nil
    }

    private static func normalizeHexColor(_ color: String) -> String? {
        let hex = String(color.dropFirst())
        switch hex.count {
        case 3:
            let expanded = hex.map { "\($0)\($0)" }.joined()
            return "#\(expanded.uppercased())"
        case 4:
            let expanded = hex.prefix(3).map { "\($0)\($0)" }.joined()
            return "#\(expanded.uppercased())"
        case 6:
            return "#\(hex.uppercased())"
        case 8:
            return "#\(hex.prefix(6).uppercased())"
        default:
            return nil
        }
    }

    private static func convertToHex(_ color: String) -> String? {
        let rgbaPattern = "rgba?\\s*\\(\\s*([\\d.]+)\\s*,\\s*([\\d.]+)\\s*,\\s*([\\d.]+)\\s*(?:,\\s*([\\d.]+))?\\s*\\)"

        guard let regex = try? NSRegularExpression(pattern: rgbaPattern, options: .caseInsensitive) else {
            return nil
        }

        let nsString = color as NSString
        let range = NSRange(location: 0, length: nsString.length)

        if let match = regex.firstMatch(in: color, options: [], range: range) {
            guard match.numberOfRanges >= 4 else { return nil }

            let r = clampedRGBComponent(nsString.substring(with: match.range(at: 1)))
            let g = clampedRGBComponent(nsString.substring(with: match.range(at: 2)))
            let b = clampedRGBComponent(nsString.substring(with: match.range(at: 3)))

            let alpha: Double
            if match.numberOfRanges >= 5, match.range(at: 4).location != NSNotFound {
                alpha = (nsString.substring(with: match.range(at: 4)) as NSString).doubleValue
            } else {
                alpha = 1.0
            }

            if alpha < 0.1 {
                return nil
            }

            return String(format: "#%02X%02X%02X", r, g, b)
        }
        return nil
    }

    private static func rgbaIsTransparent(_ color: String) -> Bool {
        let alphaPattern = "rgba\\s*\\(\\s*[\\d.]+\\s*,\\s*[\\d.]+\\s*,\\s*[\\d.]+\\s*,\\s*([\\d.]+)\\s*\\)"

        guard let regex = try? NSRegularExpression(pattern: alphaPattern, options: .caseInsensitive) else {
            return false
        }

        let nsString = color as NSString
        let range = NSRange(location: 0, length: nsString.length)
        guard let match = regex.firstMatch(in: color, options: [], range: range),
              match.numberOfRanges >= 2,
              match.range(at: 1).location != NSNotFound else {
            return false
        }

        return (nsString.substring(with: match.range(at: 1)) as NSString).doubleValue < 0.1
    }

    private static func clampedRGBComponent(_ value: String) -> Int {
        min(255, max(0, Int((value as NSString).doubleValue.rounded())))
    }
}
