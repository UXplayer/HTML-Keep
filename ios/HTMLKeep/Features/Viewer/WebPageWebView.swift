import SwiftUI
import CryptoKit
import UIKit
import WebKit

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

    private func drawTransitionGradient(
        from topColors: [UIColor],
        to bottomColors: [UIColor],
        in rect: CGRect,
        context: CGContext
    ) {
        guard rect.height > 0 else { return }

        let scale = window?.screen.scale ?? UIScreen.main.scale
        let rowCount = max(Int(ceil(rect.height * scale)), 1)
        for row in 0..<rowCount {
            let startY = rect.minY + CGFloat(row) / CGFloat(rowCount) * rect.height
            let endY = rect.minY + CGFloat(row + 1) / CGFloat(rowCount) * rect.height
            let progress = (CGFloat(row) + 0.5) / CGFloat(rowCount)
            let leftColor = ViewerViewportColor.interpolate(
                ViewerViewportColor.sample(topColors, at: 0, traits: traitCollection),
                ViewerViewportColor.sample(bottomColors, at: 0, traits: traitCollection),
                progress: progress
            )
            let rightColor = ViewerViewportColor.interpolate(
                ViewerViewportColor.sample(topColors, at: 1, traits: traitCollection),
                ViewerViewportColor.sample(bottomColors, at: 1, traits: traitCollection),
                progress: progress
            )
            drawHorizontalGradient(
                colors: [leftColor.uiColor, rightColor.uiColor],
                in: CGRect(x: rect.minX, y: startY, width: rect.width, height: endY - startY),
                context: context
            )
        }
    }

    private func drawHorizontalGradient(colors: [UIColor], in rect: CGRect, context: CGContext) {
        guard rect.width > 0, rect.height > 0 else { return }

        let resolvedColors = normalizedColors(colors).map { $0.resolvedColor(with: traitCollection) }
        guard resolvedColors.count > 1 else {
            context.setFillColor((resolvedColors.first ?? .white).cgColor)
            context.fill(rect)
            return
        }

        let locations = resolvedColors.indices.map { CGFloat($0) / CGFloat(resolvedColors.count - 1) }
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: resolvedColors.map(\.cgColor) as CFArray,
            locations: locations
        ) else {
            context.setFillColor(resolvedColors[0].cgColor)
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

    private func normalizedColors(_ colors: [UIColor]) -> [UIColor] {
        let nonEmptyColors = colors.isEmpty ? [.white] : colors
        return nonEmptyColors.count == 1 ? [nonEmptyColors[0], nonEmptyColors[0]] : nonEmptyColors
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

private struct ViewerViewportBackgroundStyle {
    let colors: [UIColor]

    static func parse(_ value: String?, fallback: UIColor) -> ViewerViewportBackgroundStyle {
        let colors = ViewerViewportCSSColor.colorTokens(in: value ?? "")
            .compactMap(ViewerViewportCSSColor.parseColor)
        return ViewerViewportBackgroundStyle(colors: colors.isEmpty ? [fallback] : colors)
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

struct WebPageWebView: UIViewRepresentable {
    let page: WebPage
    let entryURL: URL
    let entryHTML: String?
    let readAccessURL: URL
    let reloadToken: UUID
    let onLoadStateChange: (ViewerLoadState) -> Void
    let onRequestDismiss: () -> Void
    let onRuntimeStorageChange: () -> Void
    let onLocalFileNavigation: (URL) -> Void
    let onScrollOffsetChange: (CGFloat) -> Void
    let onTopOverlayPreferenceChange: (Bool) -> Void
    let viewportBackground: ViewerViewportBackground

    private static let scrollMetricsMessageName = "htmlAnywhereScrollMetrics"
    private static let topOverlayPreferenceMessageName = "htmlAnywhereTopOverlayPreference"

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.ignoresViewportScaleLimits = false
        configuration.websiteDataStore = WebPageRuntimeStorage.websiteDataStore(for: page)

        // 在文档开始阶段锁定浏览级缩放，不接管网页自己的 Safe Area 布局。
        let script = #"""
        (function() {
            var viewportRequirements = [
                'width=device-width',
                'initial-scale=1.0',
                'minimum-scale=1.0',
                'maximum-scale=1.0',
                'user-scalable=no'
            ];

            function lockedViewportContent(content) {
                var nextContent = content || '';
                viewportRequirements.forEach(function(requirement) {
                    var key = requirement.split('=')[0];
                    var hasValue = new RegExp('(^|,)\\s*' + key + '\\s*=', 'i');
                    var hasBareKey = new RegExp('(^|,)\\s*' + key + '\\s*($|,)', 'i');
                    if (hasValue.test(nextContent)) {
                        nextContent = nextContent.replace(
                            new RegExp('(^|,)\\s*' + key + '\\s*=\\s*[^,]*', 'i'),
                            '$1 ' + requirement
                        );
                    } else if (hasBareKey.test(nextContent)) {
                        nextContent = nextContent.replace(
                            new RegExp('(^|,)\\s*' + key + '\\s*($|,)', 'i'),
                            '$1 ' + requirement + '$2'
                        );
                    } else {
                        nextContent += (nextContent.trim().length > 0 ? ', ' : '') + requirement;
                    }
                });
                return nextContent.replace(/^,\s*/, '').trim();
            }

            function ensureLockedViewport() {
                var head = document.head || document.getElementsByTagName('head')[0];
                if (!head) {
                    return false;
                }

                var meta = head.querySelector('meta[name="viewport"]');
                if (!meta) {
                    meta = document.createElement('meta');
                    meta.name = 'viewport';
                    head.insertBefore(meta, head.firstChild);
                }

                var nextContent = lockedViewportContent(meta.content);
                if (meta.content !== nextContent) {
                    meta.content = nextContent;
                }
                return true;
            }

            function observeViewportChanges() {
                var head = document.head || document.getElementsByTagName('head')[0];
                if (!head || typeof MutationObserver === 'undefined') {
                    return;
                }

                var observer = new MutationObserver(function() {
                    ensureLockedViewport();
                });
                observer.observe(head, {
                    childList: true,
                    subtree: true,
                    attributes: true,
                    attributeFilter: ['content', 'name']
                });
            }

            if (ensureLockedViewport()) {
                observeViewportChanges();
            } else {
                document.addEventListener('DOMContentLoaded', function() {
                    ensureLockedViewport();
                    observeViewportChanges();
                }, { once: true });
            }
        })();
        """#
        let userScript = WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        configuration.userContentController.addUserScript(userScript)
        configuration.userContentController.add(
            context.coordinator,
            name: WebPageRuntimeStorage.localStorageMessageName
        )
        configuration.userContentController.add(
            context.coordinator,
            name: Self.scrollMetricsMessageName
        )
        configuration.userContentController.add(
            context.coordinator,
            name: Self.topOverlayPreferenceMessageName
        )

        let scrollMetricsScript = WKUserScript(
            source: Self.scrollMetricsScript(messageName: Self.scrollMetricsMessageName),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        configuration.userContentController.addUserScript(scrollMetricsScript)

        let runtimeStorageScript = WKUserScript(
            source: Self.runtimeStorageScript(projectFolderURL: readAccessURL),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        configuration.userContentController.addUserScript(runtimeStorageScript)

        let topOverlayPreferenceScript = WKUserScript(
            source: Self.topOverlayPreferenceScript(messageName: Self.topOverlayPreferenceMessageName),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        configuration.userContentController.addUserScript(topOverlayPreferenceScript)

        let webView = ViewerWKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.applyViewportBackground(viewportBackground)
        webView.scrollView.alwaysBounceVertical = true
        webView.scrollView.delegate = context.coordinator
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        configureNonZoomingWebView(webView)
        context.coordinator.attachBrowserSmartZoomFallback(to: webView)
        webView.applyViewportInsetsIfNeeded(force: true)

        load(in: webView)
        return webView
    }

    private static func runtimeStorageScript(projectFolderURL: URL) -> String {
        let bootstrap = WebPageRuntimeStorage.localStorageBootstrapState(in: projectFolderURL)
        let itemsData = (try? JSONSerialization.data(withJSONObject: bootstrap.items, options: [.sortedKeys])) ?? Data("{}".utf8)
        let itemsJSON = String(data: itemsData, encoding: .utf8) ?? "{}"
        let hasSnapshot = bootstrap.hasSnapshot ? "true" : "false"
        let snapshotVersion = Self.javascriptSingleQuotedEscaped(Self.sha256HexDigest(for: itemsData))
        let messageName = WebPageRuntimeStorage.localStorageMessageName

        return #"""
        (function() {
            if (window.__htmlAnywhereRuntimeStorageInstalled) {
                return;
            }
            window.__htmlAnywhereRuntimeStorageInstalled = true;

            var hasSnapshot = \#(hasSnapshot);
            var initialItems = \#(itemsJSON);
            var snapshotVersion = '\#(snapshotVersion)';
            var sessionSnapshotKey = '__htmlAnywhereLocalStorageSnapshotVersion';

            function restoreLocalStorage() {
                try {
                    if (!hasSnapshot || sessionStorage.getItem(sessionSnapshotKey) === snapshotVersion) {
                        return;
                    }
                    if (hasSnapshot) {
                        localStorage.clear();
                    }
                    Object.keys(initialItems || {}).forEach(function(key) {
                        var value = initialItems[key];
                        if (typeof value === 'string' && localStorage.getItem(key) !== value) {
                            localStorage.setItem(key, value);
                        }
                    });
                    sessionStorage.setItem(sessionSnapshotKey, snapshotVersion);
                } catch (error) {}
            }

            function collectLocalStorage() {
                try {
                    var items = {};
                    for (var index = 0; index < localStorage.length; index += 1) {
                        var key = localStorage.key(index);
                        if (key !== null) {
                            items[key] = localStorage.getItem(key) || '';
                        }
                    }
                    window.webkit.messageHandlers.\#(messageName).postMessage({ items: items });
                } catch (error) {}
            }

            var captureTimer = null;
            function scheduleCapture() {
                if (captureTimer !== null) {
                    clearTimeout(captureTimer);
                }
                captureTimer = setTimeout(function() {
                    captureTimer = null;
                    collectLocalStorage();
                }, 250);
            }

            window.__htmlAnywhereCaptureLocalStorage = collectLocalStorage;
            restoreLocalStorage();

            try {
                var originalSetItem = Storage.prototype.setItem;
                var originalRemoveItem = Storage.prototype.removeItem;
                var originalClear = Storage.prototype.clear;

                Storage.prototype.setItem = function() {
                    var result = originalSetItem.apply(this, arguments);
                    if (this === window.localStorage) {
                        scheduleCapture();
                    }
                    return result;
                };

                Storage.prototype.removeItem = function() {
                    var result = originalRemoveItem.apply(this, arguments);
                    if (this === window.localStorage) {
                        scheduleCapture();
                    }
                    return result;
                };

                Storage.prototype.clear = function() {
                    var result = originalClear.apply(this, arguments);
                    if (this === window.localStorage) {
                        scheduleCapture();
                    }
                    return result;
                };
            } catch (error) {}

            window.addEventListener('pagehide', collectLocalStorage);
            document.addEventListener('visibilitychange', function() {
                if (document.visibilityState === 'hidden') {
                    collectLocalStorage();
                }
            });
            setTimeout(collectLocalStorage, 0);
        })();
        """#
    }

    private static func scrollMetricsScript(messageName: String) -> String {
        let messageName = javascriptSingleQuotedEscaped(messageName)

        return #"""
        (function() {
            if (window.__htmlAnywhereScrollMetricsInstalled) {
                return;
            }
            window.__htmlAnywhereScrollMetricsInstalled = true;

            var messageName = '\#(messageName)';
            var animationFrame = null;
            var lastScrollableElement = null;

            function internalScrollableElement(target) {
                if (!target || target === window || target === document || target.nodeType !== 1) {
                    return null;
                }

                var rootScroller = document.scrollingElement || document.documentElement || document.body;
                if (target === rootScroller || target === document.documentElement || target === document.body) {
                    return null;
                }

                var canScrollVertically = target.scrollHeight > target.clientHeight + 1;
                return canScrollVertically && typeof target.scrollTop === 'number' ? target : null;
            }

            function postScrollMetrics() {
                animationFrame = null;
                var element = internalScrollableElement(lastScrollableElement);
                if (!element) {
                    lastScrollableElement = null;
                    return;
                }
                var offsetY = Math.max(Number(element.scrollTop) || 0, 0);
                try {
                    var handlers = window.webkit && window.webkit.messageHandlers;
                    if (handlers && handlers[messageName]) {
                        handlers[messageName].postMessage({ offsetY: offsetY });
                    }
                } catch (error) {}
            }

            function scheduleScrollMetrics(event) {
                var element = event && event.target ? internalScrollableElement(event.target) : null;
                if (!element) {
                    return;
                }
                lastScrollableElement = element;
                if (animationFrame !== null) {
                    return;
                }
                if (typeof window.requestAnimationFrame === 'function') {
                    animationFrame = window.requestAnimationFrame(postScrollMetrics);
                } else {
                    animationFrame = window.setTimeout(postScrollMetrics, 16);
                }
            }

            window.addEventListener('scroll', scheduleScrollMetrics, true);
            document.addEventListener('scroll', scheduleScrollMetrics, true);
        })();
        """#
    }

    private static func topOverlayPreferenceScript(messageName: String) -> String {
        let messageName = javascriptSingleQuotedEscaped(messageName)

        return #"""
        (function() {
            if (window.__htmlAnywhereTopOverlayPreferenceInstalled) {
                return;
            }
            window.__htmlAnywhereTopOverlayPreferenceInstalled = true;

            var messageName = '\#(messageName)';
            var lastPreference = null;
            var pendingTimer = null;

            function numericTop(value) {
                if (!value || value === 'auto') {
                    return null;
                }
                var number = Number.parseFloat(value);
                return Number.isFinite(number) ? number : null;
            }

            function visiblePinnedElement(element, style) {
                if (!element || element === document.documentElement || element === document.body) {
                    return false;
                }
                if (style.display === 'none' || style.visibility === 'hidden' || style.opacity === '0') {
                    return false;
                }

                var rect = element.getBoundingClientRect();
                if (rect.width < 24 || rect.height < 16) {
                    return false;
                }

                var viewportWidth = window.innerWidth || document.documentElement.clientWidth || 0;
                if (viewportWidth > 0 && rect.width < Math.min(viewportWidth * 0.35, 240)) {
                    return false;
                }

                return true;
            }

            function hasTopPinnedElement() {
                if (!document.body || typeof window.getComputedStyle !== 'function') {
                    return false;
                }

                var elements = document.body.getElementsByTagName('*');
                for (var index = 0; index < elements.length; index += 1) {
                    var element = elements[index];
                    var style = window.getComputedStyle(element);
                    var position = style.position;
                    if (position !== 'sticky' && position !== '-webkit-sticky' && position !== 'fixed') {
                        continue;
                    }

                    var top = numericTop(style.top);
                    if (top === null || top > 1) {
                        continue;
                    }

                    if (visiblePinnedElement(element, style)) {
                        return true;
                    }
                }

                return false;
            }

            function postPreference(force) {
                pendingTimer = null;
                var nextPreference = hasTopPinnedElement();
                if (!force && nextPreference === lastPreference) {
                    return;
                }
                lastPreference = nextPreference;
                try {
                    var handlers = window.webkit && window.webkit.messageHandlers;
                    if (handlers && handlers[messageName]) {
                        handlers[messageName].postMessage({ prefersTopSafeArea: nextPreference });
                    }
                } catch (error) {}
            }

            function schedulePreferencePost(force) {
                if (pendingTimer !== null) {
                    window.clearTimeout(pendingTimer);
                }
                pendingTimer = window.setTimeout(function() {
                    postPreference(force);
                }, 80);
            }

            schedulePreferencePost(true);
            window.setTimeout(function() { schedulePreferencePost(false); }, 300);
            window.setTimeout(function() { schedulePreferencePost(false); }, 1000);
            window.addEventListener('load', function() { schedulePreferencePost(false); }, { once: true });
            window.addEventListener('resize', function() { schedulePreferencePost(false); });

            if (typeof MutationObserver !== 'undefined') {
                var observer = new MutationObserver(function() {
                    schedulePreferencePost(false);
                });
                observer.observe(document.documentElement, {
                    childList: true,
                    subtree: true,
                    attributes: true,
                    attributeFilter: ['class', 'style', 'hidden']
                });
            }
        })();
        """#
    }

    private static func sha256HexDigest(for data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func javascriptSingleQuotedEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }

    private func configureNonZoomingWebView(_ webView: WKWebView) {
        let scrollView = webView.scrollView
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 1
        scrollView.zoomScale = 1
        scrollView.bouncesZoom = false
        scrollView.pinchGestureRecognizer?.isEnabled = false
        scrollView.scrollsToTop = false
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onLoadStateChange = onLoadStateChange
        context.coordinator.onRequestDismiss = onRequestDismiss
        context.coordinator.onRuntimeStorageChange = onRuntimeStorageChange
        context.coordinator.onLocalFileNavigation = onLocalFileNavigation
        context.coordinator.onScrollOffsetChange = onScrollOffsetChange
        context.coordinator.onTopOverlayPreferenceChange = onTopOverlayPreferenceChange
        context.coordinator.projectFolderURL = readAccessURL
        context.coordinator.virtualEntryURL = entryHTML == nil ? nil : entryURL
        if let viewerWebView = webView as? ViewerWKWebView {
            viewerWebView.applyViewportBackground(viewportBackground)
            viewerWebView.applyViewportInsetsIfNeeded()
        }
        if context.coordinator.loadedEntryURL != entryURL || context.coordinator.reloadToken != reloadToken {
            load(in: webView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onLoadStateChange: onLoadStateChange,
            onRequestDismiss: onRequestDismiss,
            onRuntimeStorageChange: onRuntimeStorageChange,
            onLocalFileNavigation: onLocalFileNavigation,
            onScrollOffsetChange: onScrollOffsetChange,
            onTopOverlayPreferenceChange: onTopOverlayPreferenceChange,
            projectFolderURL: readAccessURL
        )
    }

    private func load(in webView: WKWebView) {
        if let coordinator = webView.navigationDelegate as? Coordinator {
            coordinator.loadedEntryURL = entryURL
            coordinator.reloadToken = reloadToken
            coordinator.projectFolderURL = readAccessURL
            coordinator.virtualEntryURL = entryHTML == nil ? nil : entryURL
        }
        if let entryHTML {
            webView.loadHTMLString(entryHTML, baseURL: readAccessURL)
        } else {
            webView.loadFileURL(entryURL, allowingReadAccessTo: readAccessURL)
        }
    }

    private final class ViewerWKWebView: WKWebView {
        private let viewportBackgroundView = ViewerViewportBackgroundView()

        func applyViewportBackground(_ background: ViewerViewportBackground) {
            isOpaque = false
            backgroundColor = .clear
            scrollView.isOpaque = false
            scrollView.backgroundColor = .clear
            viewportBackgroundView.background = background
            if viewportBackgroundView.superview == nil {
                insertSubview(viewportBackgroundView, at: 0)
                sendSubviewToBack(viewportBackgroundView)
            }
            if !viewportBackgroundView.frame.isApproximatelyEqual(to: bounds) {
                viewportBackgroundView.frame = bounds
            }
        }

        func applyViewportInsetsIfNeeded(force: Bool = false) {
            let topInset = max(safeAreaInsets.top, 0)
            let scrollView = self.scrollView
            let previousInset = scrollView.contentInset
            let insetDidChange = abs(previousInset.top - topInset) > 0.5 || abs(previousInset.bottom) > 0.5
            guard force || insetDidChange else {
                return
            }

            let wasAtAdjustedTop = scrollView.contentOffset.y <= -previousInset.top + 1
            let wasAtUnadjustedTop = abs(previousInset.top - topInset) < 0.5 && abs(scrollView.contentOffset.y) < 1 && topInset > 0
            let normalizedOffsetY = max(scrollView.contentOffset.y + previousInset.top, 0)

            var nextInset = previousInset
            nextInset.top = topInset
            nextInset.bottom = 0
            scrollView.contentInset = nextInset
            let previousIndicatorInsets = scrollView.verticalScrollIndicatorInsets
            scrollView.verticalScrollIndicatorInsets = UIEdgeInsets(
                top: topInset,
                left: previousIndicatorInsets.left,
                bottom: 0,
                right: previousIndicatorInsets.right
            )

            let shouldKeepAtTop = wasAtAdjustedTop || wasAtUnadjustedTop
            let nextOffsetY = shouldKeepAtTop ? -topInset : normalizedOffsetY - topInset
            if abs(scrollView.contentOffset.y - nextOffsetY) > 0.5 {
                scrollView.setContentOffset(
                    CGPoint(x: scrollView.contentOffset.x, y: nextOffsetY),
                    animated: false
                )
            }
        }

        func alignContentOffsetToTopInsetIfNeeded() {
            let topInset = scrollView.contentInset.top
            guard topInset > 0,
                  abs(scrollView.contentOffset.y) < 1,
                  !scrollView.isTracking,
                  !scrollView.isDragging,
                  !scrollView.isDecelerating else {
                return
            }

            scrollView.setContentOffset(
                CGPoint(x: scrollView.contentOffset.x, y: -topInset),
                animated: false
            )
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            applyViewportInsetsIfNeeded(force: true)
        }

        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()
            applyViewportInsetsIfNeeded(force: true)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            if !viewportBackgroundView.frame.isApproximatelyEqual(to: bounds) {
                viewportBackgroundView.frame = bounds
            }
            sendSubviewToBack(viewportBackgroundView)
            applyViewportInsetsIfNeeded()
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var loadedEntryURL: URL?
        var reloadToken: UUID?
        var onLoadStateChange: (ViewerLoadState) -> Void
        var onRequestDismiss: () -> Void
        var onRuntimeStorageChange: () -> Void
        var onLocalFileNavigation: (URL) -> Void
        var onScrollOffsetChange: (CGFloat) -> Void
        var onTopOverlayPreferenceChange: (Bool) -> Void
        var projectFolderURL: URL
        var virtualEntryURL: URL?
        private weak var webView: WKWebView?
        private var doubleTapObserver: UITapGestureRecognizer?
        private var lastStableContentOffset: CGPoint = .zero
        private var browserTapSuppressionDeadline: CFTimeInterval = 0
        private var browserTapSuppressionOffset: CGPoint?
        private var manualFileLoadURL: URL?

        init(
            onLoadStateChange: @escaping (ViewerLoadState) -> Void,
            onRequestDismiss: @escaping () -> Void,
            onRuntimeStorageChange: @escaping () -> Void,
            onLocalFileNavigation: @escaping (URL) -> Void,
            onScrollOffsetChange: @escaping (CGFloat) -> Void,
            onTopOverlayPreferenceChange: @escaping (Bool) -> Void,
            projectFolderURL: URL
        ) {
            self.onLoadStateChange = onLoadStateChange
            self.onRequestDismiss = onRequestDismiss
            self.onRuntimeStorageChange = onRuntimeStorageChange
            self.onLocalFileNavigation = onLocalFileNavigation
            self.onScrollOffsetChange = onScrollOffsetChange
            self.onTopOverlayPreferenceChange = onTopOverlayPreferenceChange
            self.projectFolderURL = projectFolderURL
        }

        func attachBrowserSmartZoomFallback(to webView: WKWebView) {
            self.webView = webView
            lastStableContentOffset = webView.scrollView.contentOffset
            onScrollOffsetChange(normalizedTopScrollOffset(for: webView.scrollView))

            guard doubleTapObserver == nil else {
                return
            }

            // Fallback only: public WebKit viewport controls should prevent zoom first. This observer
            // does not cancel HTML touches; it only restores native smart-zoom offset drift.
            let observer = UITapGestureRecognizer(target: self, action: #selector(handleBrowserDoubleTap(_:)))
            observer.numberOfTapsRequired = 2
            observer.cancelsTouchesInView = false
            observer.delaysTouchesBegan = false
            observer.delaysTouchesEnded = false
            observer.delegate = self
            webView.addGestureRecognizer(observer)
            doubleTapObserver = observer
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            loadedEntryURL = virtualEntryURL ?? manualFileLoadURL ?? webView.url
            onLoadStateChange(.loading)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let finishedEntryURL = virtualEntryURL ?? manualFileLoadURL ?? webView.url
            loadedEntryURL = finishedEntryURL
            manualFileLoadURL = nil
            if let viewerWebView = webView as? ViewerWKWebView {
                viewerWebView.applyViewportInsetsIfNeeded(force: true)
                viewerWebView.alignContentOffsetToTopInsetIfNeeded()
            }
            webView.scrollView.zoomScale = 1
            lastStableContentOffset = webView.scrollView.contentOffset
            onScrollOffsetChange(normalizedTopScrollOffset(for: webView.scrollView))
            webView.evaluateJavaScript("window.__htmlAnywhereCaptureLocalStorage && window.__htmlAnywhereCaptureLocalStorage();")
            if let navigatedURL = finishedEntryURL ?? webView.url {
                onLocalFileNavigation(navigatedURL)
            }
            onLoadStateChange(.loaded)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.targetFrame?.isMainFrame != false,
                  let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            guard url.isFileURL else {
                if Self.shouldOpenExternally(url) {
                    decisionHandler(.cancel)
                    UIApplication.shared.open(url)
                } else {
                    decisionHandler(.allow)
                }
                return
            }

            guard Self.isDescendant(url, of: projectFolderURL) else {
                decisionHandler(.cancel)
                return
            }

            if url.path == webView.url?.path, url.fragment != nil {
                decisionHandler(.allow)
                return
            }

            guard let target = Self.localHTMLNavigationTarget(for: url, in: projectFolderURL) else {
                decisionHandler(.allow)
                return
            }

            if manualFileLoadURL?.standardizedFileURL.path == target.entryURL.standardizedFileURL.path {
                decisionHandler(.allow)
                return
            }

            manualFileLoadURL = target.entryURL.standardizedFileURL
            loadedEntryURL = target.entryURL
            decisionHandler(.cancel)
            onLocalFileNavigation(target.entryURL)
            DispatchQueue.main.async { [weak self, weak webView] in
                guard let self, let webView else {
                    return
                }
                guard self.manualFileLoadURL?.path == target.entryURL.standardizedFileURL.path else {
                    return
                }
                webView.loadFileURL(target.loadURL, allowingReadAccessTo: self.projectFolderURL)
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == WebPageWebView.scrollMetricsMessageName {
                if let body = message.body as? [String: Any],
                   let offsetY = body["offsetY"] as? NSNumber {
                    onScrollOffsetChange(max(CGFloat(truncating: offsetY), 0))
                }
                return
            }

            if message.name == WebPageWebView.topOverlayPreferenceMessageName {
                guard let body = message.body as? [String: Any] else {
                    return
                }

                if let prefersTopSafeArea = body["prefersTopSafeArea"] as? Bool {
                    onTopOverlayPreferenceChange(prefersTopSafeArea)
                } else if let prefersTopSafeArea = body["prefersTopSafeArea"] as? NSNumber {
                    onTopOverlayPreferenceChange(prefersTopSafeArea.boolValue)
                }
                return
            }

            guard message.name == WebPageRuntimeStorage.localStorageMessageName,
                  let body = message.body as? [String: Any],
                  let rawItems = body["items"] as? [String: Any] else {
                return
            }

            var items: [String: String] = [:]
            for (key, value) in rawItems {
                if let value = value as? String {
                    items[key] = value
                } else if let value = value as? CustomStringConvertible {
                    items[key] = value.description
                }
            }

            let bootstrapState = WebPageRuntimeStorage.localStorageBootstrapState(in: projectFolderURL)
            guard !items.isEmpty || bootstrapState.hasSnapshot else {
                return
            }
            if WebPageRuntimeStorage.saveLocalStorageItems(items, in: projectFolderURL) {
                onRuntimeStorageChange()
            }
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            nil
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            onScrollOffsetChange(normalizedTopScrollOffset(for: scrollView))

            guard !restoreBrowserTapOffsetIfNeeded(in: scrollView) else {
                return
            }

            if scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating {
                lastStableContentOffset = scrollView.contentOffset
            } else if browserTapSuppressionOffset == nil {
                lastStableContentOffset = scrollView.contentOffset
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            gestureRecognizer === doubleTapObserver
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            gestureRecognizer === doubleTapObserver
        }

        @objc private func handleBrowserDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let scrollView = webView?.scrollView else {
                return
            }

            browserTapSuppressionOffset = lastStableContentOffset
            browserTapSuppressionDeadline = CACurrentMediaTime() + 0.45
            restoreBrowserTapOffset(in: scrollView)

            [0.02, 0.08, 0.18, 0.32].forEach { delay in
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak scrollView] in
                    guard let self, let scrollView else {
                        return
                    }
                    self.restoreBrowserTapOffsetIfNeeded(in: scrollView)
                }
            }
        }

        @discardableResult
        private func restoreBrowserTapOffsetIfNeeded(in scrollView: UIScrollView) -> Bool {
            guard
                browserTapSuppressionDeadline > CACurrentMediaTime(),
                browserTapSuppressionOffset != nil,
                !scrollView.isTracking,
                !scrollView.isDragging,
                !scrollView.isDecelerating
            else {
                if browserTapSuppressionDeadline <= CACurrentMediaTime() {
                    browserTapSuppressionOffset = nil
                }
                return false
            }

            restoreBrowserTapOffset(in: scrollView)
            return true
        }

        private func restoreBrowserTapOffset(in scrollView: UIScrollView) {
            guard let targetOffset = browserTapSuppressionOffset else {
                return
            }

            scrollView.setZoomScale(1, animated: false)
            if scrollView.contentOffset != targetOffset {
                scrollView.setContentOffset(targetOffset, animated: false)
            }
        }

        private static func isHTMLFileURL(_ url: URL) -> Bool {
            let fileExtension = url.pathExtension.lowercased()
            return fileExtension == "html" || fileExtension == "htm"
        }

        private struct LocalHTMLNavigationTarget {
            var entryURL: URL
            var loadURL: URL
        }

        private static let directoryEntryHTMLFileNames = [
            "index.html",
            "index.htm",
            "default.html",
            "default.htm"
        ]

        private static func localHTMLNavigationTarget(
            for url: URL,
            in projectFolderURL: URL,
            fileManager: FileManager = .default
        ) -> LocalHTMLNavigationTarget? {
            let fileSystemURL = fileSystemURL(for: url)
            if isHTMLFileURL(fileSystemURL) {
                return LocalHTMLNavigationTarget(
                    entryURL: fileSystemURL,
                    loadURL: fileURL(fileSystemURL, carryingNavigationStateFrom: url)
                )
            }

            guard let directoryEntryURL = directoryEntryHTMLURL(
                for: fileSystemURL,
                in: projectFolderURL,
                fileManager: fileManager
            ) else {
                return nil
            }

            return LocalHTMLNavigationTarget(
                entryURL: directoryEntryURL,
                loadURL: fileURL(directoryEntryURL, carryingNavigationStateFrom: url)
            )
        }

        private static func fileSystemURL(for url: URL) -> URL {
            URL(fileURLWithPath: url.path, isDirectory: url.hasDirectoryPath).standardizedFileURL
        }

        private static func fileURL(_ fileURL: URL, carryingNavigationStateFrom navigationURL: URL) -> URL {
            guard var components = URLComponents(url: fileURL, resolvingAgainstBaseURL: false),
                  let navigationComponents = URLComponents(url: navigationURL, resolvingAgainstBaseURL: false) else {
                return fileURL
            }

            components.query = navigationComponents.query
            components.fragment = navigationComponents.fragment
            return components.url ?? fileURL
        }

        private static func directoryEntryHTMLURL(
            for url: URL,
            in projectFolderURL: URL,
            fileManager: FileManager
        ) -> URL? {
            let isExistingDirectory = isExistingDirectory(url, fileManager: fileManager)
            guard isExistingDirectory || url.hasDirectoryPath || url.pathExtension.isEmpty else {
                return nil
            }

            for fileName in directoryEntryHTMLFileNames {
                let candidateURL = url.appendingPathComponent(fileName, isDirectory: false).standardizedFileURL
                guard isDescendant(candidateURL, of: projectFolderURL),
                      isExistingRegularFile(candidateURL, fileManager: fileManager) else {
                    continue
                }
                return candidateURL
            }

            return nil
        }

        private static func isExistingDirectory(_ url: URL, fileManager: FileManager) -> Bool {
            var isDirectory = ObjCBool(false)
            return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }

        private static func isExistingRegularFile(_ url: URL, fileManager: FileManager) -> Bool {
            var isDirectory = ObjCBool(false)
            return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
        }

        private static func isDescendant(_ url: URL, of rootURL: URL) -> Bool {
            let rootPath = rootURL.standardizedFileURL.path
            let candidatePath = url.standardizedFileURL.path
            return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
        }

        private static func shouldOpenExternally(_ url: URL) -> Bool {
            guard let scheme = url.scheme?.lowercased() else {
                return false
            }

            let webKitInternalSchemes: Set<String> = [
                "about",
                "blob",
                "data",
                "javascript"
            ]
            return !webKitInternalSchemes.contains(scheme)
        }

        private func normalizedTopScrollOffset(for scrollView: UIScrollView) -> CGFloat {
            max(scrollView.contentOffset.y + scrollView.adjustedContentInset.top, 0)
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            manualFileLoadURL = nil
            onLoadStateChange(.failed(error.localizedDescription))
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            manualFileLoadURL = nil
            onLoadStateChange(.failed(error.localizedDescription))
        }
    }
}
