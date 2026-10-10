import UIKit

/// A length value expressed in pixels or as a percentage.
public enum SVGLength {
    /// A length in pixels.
    case px(value: CGFloat)
    ///0...1
    case percent(value: CGFloat)

    internal static func get(string: String) throws -> SVGLength {
        let string = string.trimmed

        if string.hasSuffix("%") {
            if let f = Float(String(string.dropLast()).trimmed) {
                return .percent(value: CGFloat(f / 100.0))
            }
            return .px(value: 0)
        }

        // Absolute CSS length units, converted to pixels (1in = 96px).
        let unitFactors: [(unit: String, factor: CGFloat)] = [
            ("px", 1),
            ("pt", 96.0 / 72.0),
            ("pc", 96.0 / 6.0),
            ("in", 96.0),
            ("cm", 96.0 / 2.54),
            ("mm", 96.0 / 25.4),
        ]

        for (unit, factor) in unitFactors {
            if string.hasSuffix(unit) {
                if let f = Float(String(string.dropLast(unit.count)).trimmed) {
                    return .px(value: CGFloat(f) * factor)
                }
                return .px(value: 0)
            }
        }

        // A bare number is interpreted in SVG user units (pixels).
        if let f = Float(string) {
            return .px(value: CGFloat(f))
        }

        // Unsupported (relative) or malformed length — degrade gracefully instead
        // of failing the whole document.
        return .px(value: 0)
    }
}
