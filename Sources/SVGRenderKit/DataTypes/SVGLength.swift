import UIKit

/// A length value expressed in pixels or as a percentage.
public enum SVGLength {
    /// A length in pixels.
    case px(value: CGFloat)
    ///0...1
    case percent(value: CGFloat)

    /// Absolute CSS length units, converted to pixels (1in = 96px).
    private static let unitFactors: [(unit: String, factor: CGFloat)] = [
        ("px", 1),
        ("pt", 96.0 / 72.0),
        ("pc", 96.0 / 6.0),
        ("in", 96.0),
        ("cm", 96.0 / 2.54),
        ("mm", 96.0 / 25.4),
    ]

    internal static func get(string: String) throws -> SVGLength {
        let string = string.trimmed

        // Fast path: a bare number is the most common form.
        if let f = Double(string), f.isFinite {
            return .px(value: CGFloat(f))
        }

        if string.hasSuffix("%") {
            if let f = Double(String(string.dropLast()).trimmed), f.isFinite {
                return .percent(value: CGFloat(f / 100.0))
            }
            return .px(value: 0)
        }

        for (unit, factor) in Self.unitFactors {
            if string.hasSuffix(unit) {
                if let f = Double(String(string.dropLast(unit.count)).trimmed), f.isFinite {
                    return .px(value: CGFloat(f) * factor)
                }
                return .px(value: 0)
            }
        }

        // A bare number is interpreted in SVG user units (pixels).
        if let f = Double(string), f.isFinite {
            return .px(value: CGFloat(f))
        }

        // Unsupported (relative) or malformed length — degrade gracefully instead
        // of failing the whole document.
        return .px(value: 0)
    }
}
