import UIKit

/// The fill rule used to determine which areas of a shape are filled.
public enum SVGFillRuleType: String {
    /// Fill the interior using the non-zero winding rule.
    case nonzero = "nonzero"
    /// Fill the interior using the even-odd rule.
    case evenodd = "evenodd"
    /// Inherit the fill rule from the parent element.
    case inherit = "inherit"

    static var `default`: SVGFillRuleType = SVGFillRuleType.nonzero
}

/// The clip rule used to determine which areas of a clipping path are applied.
public enum SVGClipRuleType: String {
    /// Clip using the non-zero winding rule.
    case nonzero = "nonzero"
    /// Clip using the even-odd rule.
    case evenodd = "evenodd"
    /// Inherit the clip rule from the parent element.
    case inherit = "inherit"

    static var `default`: SVGClipRuleType = SVGClipRuleType.nonzero
}

/// The style of text rendering for an SVG text element.
public enum SVGFontStyle: String {
    /// Render text normally.
    case normal = "normal"
    /// Render text in italics.
    case italic = "italic"
    /// Render text with an oblique (slanted) style.
    case oblique = "oblique"

    static var `default`: SVGFontStyle = SVGFontStyle.normal
}

/// How an element is displayed within the document.
public enum SVGDisplaytype: String {
    /// Display the element inline.
    case inline = "inline"
    /// Display the element as a block.
    case block = "block"
    /// Hide the element entirely.
    case none = "none"

    static var `default`: SVGDisplaytype = SVGDisplaytype.inline
}

/// The shape of the end caps of an SVG stroke.
public enum SVGLineCap: String {
    /// The stroke ends exactly at the path endpoint (no cap).
    case butt = "butt"
    /// A semicircular cap extends beyond the endpoint.
    case round = "round"
    /// A square cap extends beyond the endpoint.
    case square = "square"
}

/// The shape used to join two stroke segments.
public enum SVGLineJoin: String {
    /// A sharp (mitered) corner.
    case miter = "miter"
    /// A rounded corner.
    case round = "round"
    /// A beveled (flattened) corner.
    case bevel = "bevel"
}




