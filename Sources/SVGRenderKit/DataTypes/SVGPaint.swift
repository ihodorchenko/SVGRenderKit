import UIKit

/// A paint value for fills and strokes.
public enum SVGPaint {
    /// No paint; the element is not filled or stroked.
    case none
    /// Use the current text color, resolved from the `color` property.
    case currentColor
    /// A solid color.
    case color(color: UIColor)
    /// A reference to a gradient or pattern via a functional IRI.
    case funcIRI(iri: SVGFuncIRI)
    /// A reference with a fallback paint, `fill="url(#grad) #fff"`: the reference wins,
    /// the fallback paints when it cannot be resolved (SVG 1.1 §11.2, B119-5). `indirect`
    /// because the fallback is itself an `SVGPaint`.
    indirect case funcIRIWithFallback(iri: SVGFuncIRI, fallback: SVGPaint)

    /// Parses a paint string (`none`, hex, `rgb`, `url(...)`, or a named color) into an `SVGPaint`.
    /// - parameter string: The paint string to parse.
    public static func get(string rawString: String) throws -> SVGPaint {
        // Presentation attributes may carry surrounding whitespace (`fill=" #fff "`).
        let string = rawString.trimmed
        let lowered = string.lowercased()
        if lowered == "none" {
            return (.none)
        } else if lowered == "currentcolor" {
            return .currentColor
        } else if string.hasPrefix("#") || lowered.hasPrefix("argb") || lowered.hasPrefix("rgb") || lowered.hasPrefix("hsl") {
            // An invalid colour makes the declaration invalid: it is ignored, not painted clear (B129).
            guard let color = SVGColors.parse(string: string) else {
                throw SVGError.parseError(text: "invalid color: \(string)")
            }
            return SVGPaint.color(color: color)
        } else if string.hasPrefix("url") {
            return try reference(in: string)
        } else if let hexCod = HTMLColors.colors[lowered] {
            return SVGPaint.color(color: SVGColors.getColor(string: hexCod))
        } else {
            throw SVGError.parseError(text: "SVGPaint not found prefixes in: \(string)")
        }
    }

    /// Parses `url(#ref)` and, when present, its fallback paint (`url(#ref) #fff`).
    private static func reference(in string: String) throws -> SVGPaint {
        guard let close = string.firstIndex(of: ")") else {
            throw SVGError.parseError(text: "SVGPaint not found prefixes in: \(string)")
        }
        let iri = try SVGFuncIRI.get(fullStr: String(string[...close]))
        let rest = SVGUtils.trimmed(string: String(string[string.index(after: close)...]))
        guard !rest.isEmpty else { return .funcIRI(iri: iri) }
        return .funcIRIWithFallback(iri: iri, fallback: try SVGPaint.get(string: rest))
    }
}
