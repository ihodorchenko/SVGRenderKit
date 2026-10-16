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

        // Unsupported (relative) or malformed length — degrade gracefully instead
        // of failing the whole document.
        return .px(value: 0)
    }

    /// Parses a root `width`/`height`: a number, a percentage or an absolute unit. Anything
    /// else — a relative unit (`em`, `rem`, …), `auto`, garbage — is `nil`, so the caller can
    /// fall back to the `viewBox` instead of collapsing to a zero size (B128).
    internal static func getSupported(string: String) -> SVGLength? {
        let trimmed = string.trimmed
        if let f = Double(trimmed), f.isFinite { return .px(value: CGFloat(f)) }
        if trimmed.hasSuffix("%") {
            guard let f = Double(String(trimmed.dropLast()).trimmed), f.isFinite else { return nil }
            return .percent(value: CGFloat(f / 100.0))
        }
        for (unit, factor) in unitFactors where trimmed.hasSuffix(unit) {
            guard let f = Double(String(trimmed.dropLast(unit.count)).trimmed), f.isFinite else { return nil }
            return .px(value: CGFloat(f) * factor)
        }
        return nil
    }
}
