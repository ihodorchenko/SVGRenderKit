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
        let trimmed = str.trimmed
        // `url(` (case-insensitive, optional space before the parenthesis), up to the closing `)`.
        guard trimmed.lowercased().hasPrefix("url"),
              let open = trimmed.firstIndex(of: "("),
              trimmed[trimmed.index(trimmed.startIndex, offsetBy: 3)..<open].allSatisfy({ $0.isWhitespace }),
              let close = trimmed.lastIndex(of: ")"), open < close else {
            throw SVGError.parseError(text: "SVGIRI not has prefix 'url': \(str)")
        }
        return try get(content: String(trimmed[trimmed.index(after: open)..<close]))
    }

    /// Parses the inner content of a `url(...)` reference into an `SVGFuncIRI`.
    /// - parameter str: The content between the parentheses of a `url(...)` reference.
    public static func get(content str: String) throws -> SVGFuncIRI {
        var str = str.trimmed
        str = str.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
        str = str.trimmed
        if str.hasPrefix("#") || str.hasPrefix(".") {
            return SVGFuncIRI.local(key: str)
        } else {
            throw SVGError.parseError(text: "SVGIRI not support this type: \(str)")
        }
    }
}
