import UIKit
import QuartzCore

/// A CSS `filter: drop-shadow(<offset-x> <offset-y> <blur-radius>? <color>?)`.
///
/// The runtime renders one drop shadow with `CALayer`'s shadow (the same primitive the SVG
/// `feDropShadow`/`feGaussianBlur` path uses). A list of several shadows is out of scope: the
/// first one applies and the rest are logged by `SVGCSSDropShadow.parse`.
struct SVGCSSDropShadow: Equatable {
    /// Horizontal offset in user units.
    let dx: CGFloat
    /// Vertical offset in user units.
    let dy: CGFloat
    /// Blur radius in user units; `CALayer.shadowRadius` takes the CoreGraphics blur radius,
    /// which is about twice the Gaussian sigma — the same mapping CSS uses for its blur radius.
    let blur: CGFloat
    /// The raw color token; `nil` means `currentColor`.
    let color: String?

    /// Parses the whole `drop-shadow(...)` value (or throws on an unsupported/invalid one).
    static func parse(_ value: String) throws -> SVGCSSDropShadow {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        guard lower.hasPrefix("drop-shadow("), let open = text.firstIndex(of: "("),
              let close = text.lastIndex(of: ")"), open < close else {
            throw SVGError.content(text: "wrong filter: \(value)")
        }
        let shadowList = String(text[text.index(after: open)..<close])
        let shadows = splitShadowList(shadowList)
        if shadows.count > 1 {
            SVGLog.addSLog(errorStr: "skipped filter: a drop-shadow list is not supported, the first shadow is used")
        }
        guard let first = shadows.first else {
            throw SVGError.content(text: "wrong filter: \(value)")
        }
        let tokens = splitTokens(first)
        guard tokens.count >= 2,
              let dx = length(tokens[0]), let dy = length(tokens[1]) else {
            throw SVGError.content(text: "wrong filter: \(value)")
        }
        var blur: CGFloat = 0
        var color: String?
        var index = 2
        if tokens.count > index, let parsedBlur = length(tokens[index]) {
            blur = parsedBlur
            index += 1
        }
        if tokens.count > index {
            let colorText = tokens[index...].joined(separator: " ")
            guard SVGColors.parse(string: colorText) != nil else {
                throw SVGError.content(text: "wrong drop-shadow color: \(colorText)")
            }
            color = colorText
        }
        return SVGCSSDropShadow(dx: dx, dy: dy, blur: max(0, blur), color: color)
    }

    /// Applies the shadow to the layer that renders the element (or the group's content).
    func apply(to layer: CALayer, currentColor: UIColor) {
        let resolved: UIColor
        if let color = color {
            resolved = SVGColors.parse(string: color) ?? currentColor
        } else {
            resolved = currentColor
        }
        layer.shadowColor = resolved.cgColor
        layer.shadowOffset = CGSize(width: dx, height: dy)
        layer.shadowRadius = blur
        layer.shadowOpacity = 1
    }

    // MARK: - Parsing helpers

    /// Splits a comma-separated shadow list at top level (`rgba(…)` commas stay inside the color).
    private static func splitShadowList(_ value: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        for character in value {
            if character == "(" { depth += 1 } else if character == ")" { depth = max(0, depth - 1) }
            if character == ",", depth == 0 {
                parts.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        parts.append(current)
        return parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Splits a shadow value into tokens at top-level whitespace (a `rgb(…)` color stays one token).
    private static func splitTokens(_ value: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var depth = 0
        for character in value {
            if character == "(" { depth += 1 } else if character == ")" { depth = max(0, depth - 1) }
            if character.isWhitespace, depth == 0 {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    /// A CSS length for an offset/blur: `px` or a unitless number (percentages are not valid here).
    private static func length(_ token: String) -> CGFloat? {
        var value = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasSuffix("px") { value = String(value.dropLast(2)) }
        return Double(value).map { CGFloat($0) }
    }
}
