import UIKit

/// A paint value for fills and strokes.
public enum SVGPaint {
    /// No paint; the element is not filled or stroked.
    case none
    /// Use the current text color. Not supported.
    case currentColor //not supported
    /// A solid color.
    case color(color: UIColor)
    /// A reference to a gradient or pattern via a functional IRI.
    case funcIRI(iri: SVGFuncIRI)

    /// Parses a paint string (`none`, hex, `rgb`, `url(...)`, or a named color) into an `SVGPaint`.
    /// - parameter string: The paint string to parse.
    public static func get(string: String) throws -> SVGPaint {
        if string == "none" {
            return (.none)
        } else if string.hasPrefix("#") {
            return SVGPaint.color(color: SVGColors.getColor(string: string))
        } else if string.hasPrefix("rgb") {
            return SVGPaint.color(color: SVGColors.getColor(string: string))
        } else if string.hasPrefix("url") {
            let iri = try SVGFuncIRI.get(fullStr: string)
            return SVGPaint.funcIRI(iri: iri)
        } else if let hexCod = HTMLColors.colors[string] {
            return SVGPaint.color(color: SVGColors.getColor(string: hexCod))
        } else {
            throw SVGError.parseError(text: "SVGPaint not found prefixes in: \(string)")
        }
    }
}
