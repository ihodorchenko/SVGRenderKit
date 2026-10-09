import UIKit

/// A functional IRI reference, such as a `url(...)` paint or clip-path reference.
public enum SVGFuncIRI {
    /// A reference to a locally defined element, identified by its key.
    case local(key: String)
    /// A reference to an external URL. Not supported.
    case web(url: String)//not support

    /// Parses a full `url(...)` string into an `SVGFuncIRI`.
    /// - parameter str: The full `url(...)` string to parse.
    public static func get(fullStr str: String) throws -> SVGFuncIRI {
        if str.hasPrefix("url") {
            var str = str.replacingOccurrences(of: "url", with: "")
            str = str.replacingOccurrences(of: "(", with: "")
            str = str.replacingOccurrences(of: ")", with: "")
            str = str.trimmed
            return try get(content: str)
        } else {
            throw SVGError.parseError(text: "SVGIRI not has prefix 'url': \(str)")
        }
    }

    /// Parses the inner content of a `url(...)` reference into an `SVGFuncIRI`.
    /// - parameter str: The content between the parentheses of a `url(...)` reference.
    public static func get(content str: String) throws -> SVGFuncIRI {
        let str = str.trimmed
        if str.hasPrefix("#") || str.hasPrefix(".") {
            return SVGFuncIRI.local(key: str)
        } else {
            throw SVGError.parseError(text: "SVGIRI not support this type: \(str)")
        }
    }
}
