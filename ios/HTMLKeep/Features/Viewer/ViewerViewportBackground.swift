import UIKit

struct ViewerViewportBackground {
    let topCSS: String?
    let bottomCSS: String?
    let fallbackTopColor: UIColor
    let fallbackBottomColor: UIColor
}

enum ViewerViewportBackgroundMode {
    case triptych
    case topSafeArea
}

final class ViewerViewportBackgroundView: UIView {
    var background = ViewerViewportBackground(
        topCSS: nil,
        bottomCSS: nil,
        fallbackTopColor: .white,
        fallbackBottomColor: .white
    ) {
        didSet {
            if !background.matches(oldValue, traits: traitCollection) {
                setNeedsDisplay()
            }
        }
    }
    var mode = ViewerViewportBackgroundMode.triptych {
        didSet {
            if mode != oldValue {
                setNeedsDisplay()
            }
        }
    }
    var viewportReferenceSize = CGSize.zero {
        didSet {
            if abs(viewportReferenceSize.width - oldValue.width) > 0.5 ||
                abs(viewportReferenceSize.height - oldValue.height) > 0.5 {
                setNeedsDisplay()
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(),
              rect.width > 0,
              rect.height > 0,
              bounds.width > 0,
              bounds.height > 0 else {
            return
        }

        let fullRect = bounds
        let viewportSize = CGSize(
            width: max(viewportReferenceSize.width, fullRect.width),
            height: max(viewportReferenceSize.height, fullRect.height)
        )
        let topStyle = ViewerSafeAreaBackgroundStyle.parse(
            background.topCSS,
            fallback: background.fallbackTopColor
        )
        if mode == .topSafeArea {
            topStyle.draw(
                in: fullRect,
                context: context,
                viewportSize: viewportSize,
                viewportYStart: 0,
                traits: traitCollection
            )
            return
        }

        let bottomStyle = ViewerSafeAreaBackgroundStyle.parse(
            background.bottomCSS,
            fallback: background.fallbackBottomColor
        )

        let topHeight = fullRect.height / 3
        let middleHeight = fullRect.height / 3
        let topRect = CGRect(x: fullRect.minX, y: fullRect.minY, width: fullRect.width, height: topHeight)
        let middleRect = CGRect(x: fullRect.minX, y: topRect.maxY, width: fullRect.width, height: middleHeight)
        let bottomRect = CGRect(x: fullRect.minX, y: middleRect.maxY, width: fullRect.width, height: fullRect.maxY - middleRect.maxY)

        topStyle.draw(
            in: topRect,
            context: context,
            viewportSize: viewportSize,
            viewportYStart: 0,
            traits: traitCollection
        )
        ViewerSafeAreaBackgroundTransition.draw(
            from: topStyle,
            to: bottomStyle,
            in: middleRect,
            viewportSize: viewportSize,
            topViewportY: min(topRect.maxY, viewportSize.height),
            bottomViewportY: max(viewportSize.height - bottomRect.height, 0),
            context: context,
            traits: traitCollection
        )
        bottomStyle.draw(
            in: bottomRect,
            context: context,
            viewportSize: viewportSize,
            viewportYStart: max(viewportSize.height - bottomRect.height, 0),
            traits: traitCollection
        )
    }

}

private extension ViewerViewportBackground {
    func matches(_ other: ViewerViewportBackground, traits: UITraitCollection) -> Bool {
        topCSS == other.topCSS &&
            bottomCSS == other.bottomCSS &&
            fallbackTopColor.matches(other.fallbackTopColor, traits: traits) &&
            fallbackBottomColor.matches(other.fallbackBottomColor, traits: traits)
    }
}

private extension UIColor {
    func matches(_ other: UIColor, traits: UITraitCollection) -> Bool {
        let lhs = rgbaComponents(resolvedWith: traits)
        let rhs = other.rgbaComponents(resolvedWith: traits)
        return abs(lhs.red - rhs.red) < 0.001 &&
            abs(lhs.green - rhs.green) < 0.001 &&
            abs(lhs.blue - rhs.blue) < 0.001 &&
            abs(lhs.alpha - rhs.alpha) < 0.001
    }

    private func rgbaComponents(resolvedWith traits: UITraitCollection) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        let color = resolvedColor(with: traits)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        if color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return (red, green, blue, alpha)
        }
        return (1, 1, 1, 1)
    }
}

private struct ViewerSafeAreaBackgroundStyle {
    let layers: [ViewerSafeAreaBackgroundLayer]

    static func parse(_ value: String?, fallback: UIColor) -> ViewerSafeAreaBackgroundStyle {
        let parsedLayers = ViewerSafeAreaCSSParser.backgroundLayers(in: value ?? "")
            .compactMap(ViewerSafeAreaBackgroundLayer.parse)
        let fallbackLayer = ViewerSafeAreaBackgroundLayer.solid(fallback)
        return ViewerSafeAreaBackgroundStyle(layers: parsedLayers.isEmpty ? [fallbackLayer] : parsedLayers + [fallbackLayer])
    }

    func draw(
        in rect: CGRect,
        context: CGContext,
        viewportSize: CGSize,
        viewportYStart: CGFloat,
        traits: UITraitCollection
    ) {
        context.saveGState()
        context.clip(to: rect)
        for layer in layers.reversed() {
            layer.draw(
                in: rect,
                context: context,
                viewportSize: viewportSize,
                viewportYStart: viewportYStart,
                traits: traits
            )
        }
        context.restoreGState()
    }

    func color(at point: CGPoint, viewportSize: CGSize, traits: UITraitCollection) -> ViewerViewportColor {
        layers.reversed().reduce(ViewerViewportColor.clear) { result, layer in
            layer.color(at: point, viewportSize: viewportSize, traits: traits).over(result)
        }
    }
}

private enum ViewerSafeAreaBackgroundLayer {
    case solid(UIColor)
    case linear(ViewerSafeAreaLinearGradient)
    case radial(ViewerSafeAreaRadialGradient)

    static func parse(_ value: String) -> ViewerSafeAreaBackgroundLayer? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let function = ViewerSafeAreaCSSParser.firstGradientFunction(in: trimmed) {
            switch function.name {
            case "linear-gradient", "repeating-linear-gradient":
                return ViewerSafeAreaLinearGradient.parse(function.expression).map(Self.linear)
            case "radial-gradient", "repeating-radial-gradient":
                return ViewerSafeAreaRadialGradient.parse(function.expression).map(Self.radial)
            default:
                break
            }
        }

        if let token = ViewerSafeAreaCSSParser.firstColorToken(in: trimmed)?.value,
           let color = ViewerViewportCSSColor.parseColor(token) {
            return .solid(color)
        }
        return nil
    }

    func draw(
        in rect: CGRect,
        context: CGContext,
        viewportSize: CGSize,
        viewportYStart: CGFloat,
        traits: UITraitCollection
    ) {
        switch self {
        case .solid(let color):
            context.setFillColor(color.resolvedColor(with: traits).cgColor)
            context.fill(rect)
        case .linear(let gradient):
            gradient.draw(in: rect, context: context, viewportSize: viewportSize, viewportYStart: viewportYStart, traits: traits)
        case .radial(let gradient):
            gradient.draw(in: rect, context: context, viewportSize: viewportSize, viewportYStart: viewportYStart, traits: traits)
        }
    }

    func color(at point: CGPoint, viewportSize: CGSize, traits: UITraitCollection) -> ViewerViewportColor {
        switch self {
        case .solid(let color):
            return ViewerViewportColor(color: color.resolvedColor(with: traits))
        case .linear(let gradient):
            return gradient.color(at: point, viewportSize: viewportSize, traits: traits)
        case .radial(let gradient):
            return gradient.color(at: point, viewportSize: viewportSize, traits: traits)
        }
    }
}

private enum ViewerSafeAreaBackgroundTransition {
    static func draw(
        from topStyle: ViewerSafeAreaBackgroundStyle,
        to bottomStyle: ViewerSafeAreaBackgroundStyle,
        in rect: CGRect,
        viewportSize: CGSize,
        topViewportY: CGFloat,
        bottomViewportY: CGFloat,
        context: CGContext,
        traits: UITraitCollection
    ) {
        guard rect.width > 0, rect.height > 0 else { return }

        let rowCount = min(max(Int(ceil(rect.height / 2)), 24), 160)
        let columnCount = 24
        let locations = (0...columnCount).map { CGFloat($0) / CGFloat(columnCount) }
        for row in 0..<rowCount {
            let startY = rect.minY + CGFloat(row) / CGFloat(rowCount) * rect.height
            let endY = rect.minY + CGFloat(row + 1) / CGFloat(rowCount) * rect.height
            let progress = (CGFloat(row) + 0.5) / CGFloat(rowCount)
            let colors = locations.map { location in
                let x = location * viewportSize.width
                return ViewerViewportColor.interpolate(
                    topStyle.color(at: CGPoint(x: x, y: topViewportY), viewportSize: viewportSize, traits: traits),
                    bottomStyle.color(at: CGPoint(x: x, y: bottomViewportY), viewportSize: viewportSize, traits: traits),
                    progress: progress
                ).uiColor
            }
            ViewerSafeAreaGradientRenderer.drawHorizontalGradient(
                colors: colors,
                locations: locations,
                in: CGRect(x: rect.minX, y: startY, width: rect.width, height: endY - startY),
                context: context,
                traits: traits
            )
        }
    }
}

private struct ViewerSafeAreaLinearGradient {
    let direction: CGVector
    let stops: [ViewerSafeAreaGradientStop]

    static func parse(_ value: String) -> ViewerSafeAreaLinearGradient? {
        guard let arguments = ViewerSafeAreaCSSParser.gradientArguments(in: value) else {
            return nil
        }

        var components = ViewerSafeAreaCSSParser.topLevelComponents(in: arguments)
        var direction = CGVector(dx: 0, dy: 1)
        if let first = components.first,
           let parsedDirection = ViewerSafeAreaCSSParser.linearGradientDirection(in: first) {
            direction = parsedDirection
            components.removeFirst()
        }

        let stops = components.compactMap(ViewerSafeAreaGradientStop.parse)
        guard !stops.isEmpty else {
            return nil
        }
        return ViewerSafeAreaLinearGradient(direction: direction.normalized, stops: stops)
    }

    func draw(
        in rect: CGRect,
        context: CGContext,
        viewportSize: CGSize,
        viewportYStart: CGFloat,
        traits: UITraitCollection
    ) {
        let lineLength = gradientLineLength(in: viewportSize)
        let resolved = ViewerSafeAreaGradientStop.drawableStops(
            stops,
            referenceLength: lineLength,
            viewportSize: viewportSize,
            traits: traits
        )
        guard let gradient = ViewerSafeAreaGradientRenderer.gradient(colors: resolved.colors, locations: resolved.locations) else {
            context.setFillColor((resolved.colors.first ?? .white).cgColor)
            context.fill(rect)
            return
        }

        let center = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        let start = localPoint(
            CGPoint(x: center.x - direction.dx * lineLength / 2, y: center.y - direction.dy * lineLength / 2),
            in: rect,
            viewportYStart: viewportYStart
        )
        let end = localPoint(
            CGPoint(x: center.x + direction.dx * lineLength / 2, y: center.y + direction.dy * lineLength / 2),
            in: rect,
            viewportYStart: viewportYStart
        )
        context.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    func color(at point: CGPoint, viewportSize: CGSize, traits: UITraitCollection) -> ViewerViewportColor {
        let lineLength = gradientLineLength(in: viewportSize)
        let center = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        let projected = (point.x - center.x) * direction.dx + (point.y - center.y) * direction.dy
        let position = (projected + lineLength / 2) / max(lineLength, 1)
        let resolved = ViewerSafeAreaGradientStop.resolvedStops(
            stops,
            referenceLength: lineLength,
            viewportSize: viewportSize,
            traits: traits
        )
        return ViewerSafeAreaGradientStop.color(at: position, in: resolved)
    }

    private func gradientLineLength(in viewportSize: CGSize) -> CGFloat {
        max(abs(direction.dx) * viewportSize.width + abs(direction.dy) * viewportSize.height, 1)
    }

    private func localPoint(_ point: CGPoint, in rect: CGRect, viewportYStart: CGFloat) -> CGPoint {
        CGPoint(x: rect.minX + point.x, y: rect.minY + point.y - viewportYStart)
    }
}

private struct ViewerSafeAreaRadialGradient {
    let centerX: ViewerSafeAreaLengthExpression
    let centerY: ViewerSafeAreaLengthExpression
    let stops: [ViewerSafeAreaGradientStop]

    static func parse(_ value: String) -> ViewerSafeAreaRadialGradient? {
        guard let arguments = ViewerSafeAreaCSSParser.gradientArguments(in: value) else {
            return nil
        }

        var components = ViewerSafeAreaCSSParser.topLevelComponents(in: arguments)
        var centerX = ViewerSafeAreaLengthExpression.percent(0.5)
        var centerY = ViewerSafeAreaLengthExpression.percent(0.5)
        if let first = components.first,
           ViewerSafeAreaCSSParser.firstColorToken(in: first) == nil {
            let center = ViewerSafeAreaCSSParser.radialGradientCenter(in: first)
            centerX = center.x
            centerY = center.y
            components.removeFirst()
        }

        let stops = components.compactMap(ViewerSafeAreaGradientStop.parse)
        guard !stops.isEmpty else {
            return nil
        }
        return ViewerSafeAreaRadialGradient(centerX: centerX, centerY: centerY, stops: stops)
    }

    func draw(
        in rect: CGRect,
        context: CGContext,
        viewportSize: CGSize,
        viewportYStart: CGFloat,
        traits: UITraitCollection
    ) {
        let center = center(in: viewportSize)
        let radius = gradientRadius(center: center, viewportSize: viewportSize)
        let resolved = ViewerSafeAreaGradientStop.drawableStops(
            stops,
            referenceLength: radius,
            viewportSize: viewportSize,
            traits: traits
        )
        guard let gradient = ViewerSafeAreaGradientRenderer.gradient(colors: resolved.colors, locations: resolved.locations) else {
            return
        }

        let localCenter = CGPoint(x: rect.minX + center.x, y: rect.minY + center.y - viewportYStart)
        context.drawRadialGradient(
            gradient,
            startCenter: localCenter,
            startRadius: 0,
            endCenter: localCenter,
            endRadius: radius,
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }

    func color(at point: CGPoint, viewportSize: CGSize, traits: UITraitCollection) -> ViewerViewportColor {
        let center = center(in: viewportSize)
        let radius = gradientRadius(center: center, viewportSize: viewportSize)
        let distance = hypot(point.x - center.x, point.y - center.y)
        let resolved = ViewerSafeAreaGradientStop.resolvedStops(
            stops,
            referenceLength: radius,
            viewportSize: viewportSize,
            traits: traits
        )
        return ViewerSafeAreaGradientStop.color(at: distance / max(radius, 1), in: resolved)
    }

    private func center(in viewportSize: CGSize) -> CGPoint {
        CGPoint(
            x: centerX.value(viewportSize: viewportSize, referenceLength: viewportSize.width),
            y: centerY.value(viewportSize: viewportSize, referenceLength: viewportSize.height)
        )
    }

    private func gradientRadius(center: CGPoint, viewportSize: CGSize) -> CGFloat {
        [
            hypot(center.x, center.y),
            hypot(viewportSize.width - center.x, center.y),
            hypot(center.x, viewportSize.height - center.y),
            hypot(viewportSize.width - center.x, viewportSize.height - center.y)
        ].max() ?? max(max(viewportSize.width, viewportSize.height), 1)
    }
}

private struct ViewerSafeAreaGradientStop {
    let color: UIColor
    let position: ViewerSafeAreaLengthExpression?

    static func parse(_ value: String) -> ViewerSafeAreaGradientStop? {
        guard let token = ViewerSafeAreaCSSParser.firstColorToken(in: value),
              let color = ViewerViewportCSSColor.parseColor(token.value) else {
            return nil
        }

        let nsString = value as NSString
        let stopStart = token.range.location + token.range.length
        let stopText = nsString.substring(
            with: NSRange(location: stopStart, length: max(nsString.length - stopStart, 0))
        )
        return ViewerSafeAreaGradientStop(
            color: color,
            position: ViewerSafeAreaLengthExpression.parseFirst(in: stopText)
        )
    }

    static func resolvedStops(
        _ stops: [ViewerSafeAreaGradientStop],
        referenceLength: CGFloat,
        viewportSize: CGSize,
        traits: UITraitCollection
    ) -> [(location: CGFloat, color: ViewerViewportColor)] {
        let nonEmptyStops = stops.isEmpty ? [ViewerSafeAreaGradientStop(color: .white, position: .percent(0))] : stops
        var positions = nonEmptyStops.map {
            $0.position.map { expression in
                expression.value(viewportSize: viewportSize, referenceLength: referenceLength) / max(referenceLength, 1)
            }
        }

        if positions[0] == nil {
            positions[0] = 0
        }
        if positions[positions.count - 1] == nil {
            positions[positions.count - 1] = 1
        }

        var index = 0
        while index < positions.count {
            if positions[index] != nil {
                index += 1
                continue
            }

            let startIndex = max(index - 1, 0)
            var endIndex = index
            while endIndex < positions.count, positions[endIndex] == nil {
                endIndex += 1
            }

            let start = positions[startIndex] ?? 0
            let end = endIndex < positions.count ? (positions[endIndex] ?? start) : start
            let gap = max(endIndex - startIndex, 1)
            for fillIndex in index..<endIndex {
                positions[fillIndex] = start + (end - start) * CGFloat(fillIndex - startIndex) / CGFloat(gap)
            }
            index = endIndex
        }

        var resolvedPositions = positions.map { $0 ?? 0 }
        for index in resolvedPositions.indices.dropFirst() where resolvedPositions[index] < resolvedPositions[index - 1] {
            resolvedPositions[index] = resolvedPositions[index - 1]
        }

        return zip(resolvedPositions, nonEmptyStops).map { location, stop in
            (location, ViewerViewportColor(color: stop.color.resolvedColor(with: traits)))
        }
    }

    static func drawableStops(
        _ stops: [ViewerSafeAreaGradientStop],
        referenceLength: CGFloat,
        viewportSize: CGSize,
        traits: UITraitCollection
    ) -> (colors: [UIColor], locations: [CGFloat]) {
        let resolved = resolvedStops(
            stops,
            referenceLength: referenceLength,
            viewportSize: viewportSize,
            traits: traits
        )
        var locations = [CGFloat(0), CGFloat(1)]
        locations.append(contentsOf: resolved.map(\.location).filter { $0 > 0 && $0 < 1 })
        locations = uniqueSorted(locations)
        return (locations.map { color(at: $0, in: resolved).uiColor }, locations)
    }

    static func color(
        at location: CGFloat,
        in stops: [(location: CGFloat, color: ViewerViewportColor)]
    ) -> ViewerViewportColor {
        guard let first = stops.first else {
            return .clear
        }
        if location <= first.location {
            return first.color
        }
        guard let last = stops.last else {
            return first.color
        }
        if location >= last.location {
            return last.color
        }

        for index in 1..<stops.count {
            let previous = stops[index - 1]
            let current = stops[index]
            guard location <= current.location else {
                continue
            }
            return ViewerViewportColor.interpolate(
                previous.color,
                current.color,
                progress: (location - previous.location) / max(current.location - previous.location, 0.0001)
            )
        }
        return last.color
    }

    private static func uniqueSorted(_ values: [CGFloat]) -> [CGFloat] {
        values
            .sorted()
            .reduce(into: [CGFloat]()) { result, value in
                let clamped = min(max(value, 0), 1)
                if result.last.map({ abs($0 - clamped) > 0.001 }) ?? true {
                    result.append(clamped)
                }
            }
    }
}

private struct ViewerSafeAreaLengthExpression {
    var points: CGFloat
    var viewportWidth: CGFloat
    var viewportHeight: CGFloat
    var percent: CGFloat

    static func percent(_ value: CGFloat) -> ViewerSafeAreaLengthExpression {
        ViewerSafeAreaLengthExpression(points: 0, viewportWidth: 0, viewportHeight: 0, percent: value)
    }

    static func parseFirst(in value: String) -> ViewerSafeAreaLengthExpression? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("calc(") {
            return parse(trimmed)
        }

        let components = trimmed
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        for component in components {
            if let expression = parse(component) {
                return expression
            }
        }
        return parse(trimmed)
    }

    static func parse(_ value: String) -> ViewerSafeAreaLengthExpression? {
        var text = value
            .replacingOccurrences(of: "!important", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("calc("), text.hasSuffix(")") {
            text = String(text.dropFirst(5).dropLast())
        }

        let pattern = "([+-]?)\\s*([0-9]*\\.?[0-9]+)\\s*(vw|vh|%|px|pt|rem|em)?"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }

        let nsString = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        guard !matches.isEmpty else {
            return nil
        }

        var expression = ViewerSafeAreaLengthExpression(points: 0, viewportWidth: 0, viewportHeight: 0, percent: 0)
        for match in matches {
            let signText = match.range(at: 1).location == NSNotFound ? "" : nsString.substring(with: match.range(at: 1))
            let numberText = nsString.substring(with: match.range(at: 2))
            let unitText = match.range(at: 3).location == NSNotFound ? "" : nsString.substring(with: match.range(at: 3)).lowercased()
            let number = CGFloat(Double(numberText) ?? 0) * (signText == "-" ? -1 : 1)

            switch unitText {
            case "vw":
                expression.viewportWidth += number / 100
            case "vh":
                expression.viewportHeight += number / 100
            case "%":
                expression.percent += number / 100
            case "rem", "em":
                expression.points += number * 16
            default:
                expression.points += number
            }
        }
        return expression
    }

    func value(viewportSize: CGSize, referenceLength: CGFloat) -> CGFloat {
        points + viewportWidth * viewportSize.width + viewportHeight * viewportSize.height + percent * referenceLength
    }
}

private enum ViewerSafeAreaCSSParser {
    struct ColorToken: Equatable {
        let value: String
        let range: NSRange
    }

    struct GradientFunction {
        let name: String
        let expression: String
    }

    static func backgroundLayers(in value: String) -> [String] {
        topLevelComponents(in: value)
    }

    static func firstGradientFunction(in value: String) -> GradientFunction? {
        let pattern = "\\b((?:repeating-)?(?:linear|radial)-gradient)\\s*\\("
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }

        let nsString = value as NSString
        let range = NSRange(location: 0, length: nsString.length)
        guard let match = regex.firstMatch(in: value, options: [], range: range),
              let functionRange = balancedFunctionRange(startingAt: match.range.location, in: value) else {
            return nil
        }
        return GradientFunction(
            name: nsString.substring(with: match.range(at: 1)).lowercased(),
            expression: nsString.substring(with: functionRange)
        )
    }

    static func firstColorToken(in value: String) -> ColorToken? {
        let pattern = "#[0-9A-Fa-f]{3,8}\\b|rgba?\\s*\\([^)]+\\)|hsla?\\s*\\([^)]+\\)|\\b(?:black|white|transparent)\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }

        let nsString = value as NSString
        let range = NSRange(location: 0, length: nsString.length)
        guard let match = regex.firstMatch(in: value, options: [], range: range) else {
            return nil
        }
        return ColorToken(value: nsString.substring(with: match.range), range: match.range)
    }

    static func gradientArguments(in gradient: String) -> String? {
        guard let openParen = gradient.firstIndex(of: "("),
              let closeParen = gradient.lastIndex(of: ")"),
              openParen < closeParen else {
            return nil
        }
        return String(gradient[gradient.index(after: openParen)..<closeParen])
    }

    static func topLevelComponents(in value: String) -> [String] {
        var depth = 0
        var component = ""
        var components: [String] = []

        for character in value {
            if character == "(" {
                depth += 1
            } else if character == ")" {
                depth = max(depth - 1, 0)
            }

            if character == "," && depth == 0 {
                let trimmed = component.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    components.append(trimmed)
                }
                component = ""
            } else {
                component.append(character)
            }
        }

        let trimmed = component.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            components.append(trimmed)
        }
        return components
    }

    static func linearGradientDirection(in value: String) -> CGVector? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if firstColorToken(in: trimmed) != nil {
            return nil
        }

        if trimmed.hasPrefix("to ") {
            var dx: CGFloat = 0
            var dy: CGFloat = 0
            if trimmed.contains("left") {
                dx = -1
            } else if trimmed.contains("right") {
                dx = 1
            }
            if trimmed.contains("top") {
                dy = -1
            } else if trimmed.contains("bottom") {
                dy = 1
            }
            return CGVector(dx: dx, dy: dy).normalized
        }

        if trimmed.hasSuffix("deg"),
           let degrees = Double(String(trimmed.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)) {
            let radians = CGFloat(positiveRemainder(degrees, by: 360) * .pi / 180)
            return CGVector(dx: sin(radians), dy: -cos(radians)).normalized
        }
        return nil
    }

    static func radialGradientCenter(in value: String) -> (x: ViewerSafeAreaLengthExpression, y: ViewerSafeAreaLengthExpression) {
        let lowercased = value.lowercased()
        guard let range = lowercased.range(of: " at ") else {
            return (.percent(0.5), .percent(0.5))
        }

        let tokens = lowercased[range.upperBound...]
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard !tokens.isEmpty else {
            return (.percent(0.5), .percent(0.5))
        }

        if tokens.count == 1 {
            if let y = positionExpression(tokens[0], axis: .vertical) {
                return (.percent(0.5), y)
            }
            if let x = positionExpression(tokens[0], axis: .horizontal) {
                return (x, .percent(0.5))
            }
        }

        let x = positionExpression(tokens[0], axis: .horizontal) ?? .percent(0.5)
        let y = tokens.count > 1 ? (positionExpression(tokens[1], axis: .vertical) ?? .percent(0.5)) : .percent(0.5)
        return (x, y)
    }

    private enum PositionAxis {
        case horizontal
        case vertical
    }

    private static func positionExpression(_ value: String, axis: PositionAxis) -> ViewerSafeAreaLengthExpression? {
        switch value {
        case "left":
            return axis == .horizontal ? .percent(0) : nil
        case "right":
            return axis == .horizontal ? .percent(1) : nil
        case "top":
            return axis == .vertical ? .percent(0) : nil
        case "bottom":
            return axis == .vertical ? .percent(1) : nil
        case "center":
            return .percent(0.5)
        default:
            return ViewerSafeAreaLengthExpression.parse(value)
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

    private static func positiveRemainder(_ value: Double, by divisor: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: divisor)
        return remainder >= 0 ? remainder : remainder + divisor
    }
}

private enum ViewerSafeAreaGradientRenderer {
    static func drawHorizontalGradient(
        colors: [UIColor],
        locations: [CGFloat],
        in rect: CGRect,
        context: CGContext,
        traits: UITraitCollection
    ) {
        guard rect.width > 0, rect.height > 0 else { return }

        let resolvedColors = colors.map { $0.resolvedColor(with: traits) }
        guard resolvedColors.count > 1,
              let gradient = gradient(colors: resolvedColors, locations: locations) else {
            context.setFillColor((resolvedColors.first ?? .white).cgColor)
            context.fill(rect)
            return
        }

        context.saveGState()
        context.clip(to: rect)
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: rect.midY),
            end: CGPoint(x: rect.maxX, y: rect.midY),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
        context.restoreGState()
    }

    static func gradient(colors: [UIColor], locations: [CGFloat]) -> CGGradient? {
        var colors = colors
        var locations = locations
        if colors.count == 1 {
            colors = [colors[0], colors[0]]
            locations = [0, 1]
        }
        guard colors.count == locations.count, !colors.isEmpty else {
            return nil
        }
        return CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors.map(\.cgColor) as CFArray,
            locations: locations
        )
    }
}

private enum ViewerViewportCSSColor {
    static func colorTokens(in value: String) -> [String] {
        let pattern = "#[0-9A-Fa-f]{3,8}\\b|rgba?\\s*\\([^)]+\\)|\\b(?:black|white|transparent)\\b"
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

    static func parseColor(_ value: String) -> UIColor? {
        let trimmed = value
            .replacingOccurrences(of: "!important", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.caseInsensitiveCompare("transparent") == .orderedSame {
            return .clear
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
        return nil
    }

    private static func colorFromHex(_ value: String) -> UIColor? {
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

        guard let int = UInt32(expanded, radix: 16) else {
            return nil
        }
        return UIColor(
            red: CGFloat((int >> 16) & 0xFF) / 255,
            green: CGFloat((int >> 8) & 0xFF) / 255,
            blue: CGFloat(int & 0xFF) / 255,
            alpha: 1
        )
    }

    private static func colorFromRGB(_ value: String) -> UIColor? {
        guard let open = value.firstIndex(of: "("),
              let close = value.lastIndex(of: ")"),
              open < close else {
            return nil
        }

        let arguments = value[value.index(after: open)..<close]
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard arguments.count >= 3 else {
            return nil
        }

        return UIColor(
            red: rgbComponent(arguments[0]),
            green: rgbComponent(arguments[1]),
            blue: rgbComponent(arguments[2]),
            alpha: arguments.count >= 4 ? alphaComponent(arguments[3]) : 1
        )
    }

    private static func rgbComponent(_ value: String) -> CGFloat {
        if value.hasSuffix("%") {
            return percentageComponent(value)
        }
        return min(max((Double(value) ?? 0) / 255, 0), 1)
    }

    private static func alphaComponent(_ value: String) -> CGFloat {
        if value.hasSuffix("%") {
            return percentageComponent(value)
        }
        return min(max(Double(value) ?? 1, 0), 1)
    }

    private static func percentageComponent(_ value: String) -> CGFloat {
        min(max((Double(value.replacingOccurrences(of: "%", with: "")) ?? 0) / 100, 0), 1)
    }
}

private struct ViewerViewportColor {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat

    var uiColor: UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    static var clear: ViewerViewportColor {
        ViewerViewportColor(red: 0, green: 0, blue: 0, alpha: 0)
    }

    static func sample(_ colors: [UIColor], at position: CGFloat, traits: UITraitCollection) -> ViewerViewportColor {
        let resolvedColors = colors.isEmpty ? [.white] : colors.map { $0.resolvedColor(with: traits) }
        guard resolvedColors.count > 1 else {
            return ViewerViewportColor(color: resolvedColors[0])
        }

        let clampedPosition = min(max(position, 0), 1)
        let scaledPosition = clampedPosition * CGFloat(resolvedColors.count - 1)
        let lowerIndex = min(max(Int(floor(scaledPosition)), 0), resolvedColors.count - 1)
        let upperIndex = min(lowerIndex + 1, resolvedColors.count - 1)
        let localProgress = scaledPosition - CGFloat(lowerIndex)
        return interpolate(
            ViewerViewportColor(color: resolvedColors[lowerIndex]),
            ViewerViewportColor(color: resolvedColors[upperIndex]),
            progress: localProgress
        )
    }

    static func interpolate(
        _ start: ViewerViewportColor,
        _ end: ViewerViewportColor,
        progress: CGFloat
    ) -> ViewerViewportColor {
        let clampedProgress = min(max(progress, 0), 1)
        return ViewerViewportColor(
            red: start.red + (end.red - start.red) * clampedProgress,
            green: start.green + (end.green - start.green) * clampedProgress,
            blue: start.blue + (end.blue - start.blue) * clampedProgress,
            alpha: start.alpha + (end.alpha - start.alpha) * clampedProgress
        )
    }

    func over(_ background: ViewerViewportColor) -> ViewerViewportColor {
        let outputAlpha = alpha + background.alpha * (1 - alpha)
        guard outputAlpha > 0 else {
            return .clear
        }

        return ViewerViewportColor(
            red: (red * alpha + background.red * background.alpha * (1 - alpha)) / outputAlpha,
            green: (green * alpha + background.green * background.alpha * (1 - alpha)) / outputAlpha,
            blue: (blue * alpha + background.blue * background.alpha * (1 - alpha)) / outputAlpha,
            alpha: outputAlpha
        )
    }

    private init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(color: UIColor) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        if color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            self.red = red
            self.green = green
            self.blue = blue
            self.alpha = alpha
        } else {
            self.red = 1
            self.green = 1
            self.blue = 1
            self.alpha = 1
        }
    }
}

private extension CGVector {
    var normalized: CGVector {
        let length = hypot(dx, dy)
        guard length > 0 else {
            return CGVector(dx: 0, dy: 1)
        }
        return CGVector(dx: dx / length, dy: dy / length)
    }
}

private extension CGRect {
    func isApproximatelyEqual(to other: CGRect) -> Bool {
        abs(origin.x - other.origin.x) < 0.5 &&
            abs(origin.y - other.origin.y) < 0.5 &&
            abs(size.width - other.size.width) < 0.5 &&
            abs(size.height - other.size.height) < 0.5
    }
}
