import UIKit

/// The fill rule used to determine which areas of a shape are filled.
public enum SVGFillRuleType: String, Sendable {
    /// Fill the interior using the non-zero winding rule.
    case nonzero = "nonzero"
    /// Fill the interior using the even-odd rule.
    case evenodd = "evenodd"
    /// Inherit the fill rule from the parent element.
    case inherit = "inherit"

    static let `default`: SVGFillRuleType = SVGFillRuleType.nonzero
}

/// The clip rule used to determine which areas of a clipping path are applied.
public enum SVGClipRuleType: String, Sendable {
    /// Clip using the non-zero winding rule.
    case nonzero = "nonzero"
    /// Clip using the even-odd rule.
    case evenodd = "evenodd"
    /// Inherit the clip rule from the parent element.
    case inherit = "inherit"

    static let `default`: SVGClipRuleType = SVGClipRuleType.nonzero
}

/// The style of text rendering for an SVG text element.
public enum SVGFontStyle: String, Sendable {
    /// Render text normally.
    case normal = "normal"
    /// Render text in italics.
    case italic = "italic"
    /// Render text with an oblique (slanted) style.
    case oblique = "oblique"

    static let `default`: SVGFontStyle = SVGFontStyle.normal
}

/// How an element is displayed within the document.
public enum SVGDisplaytype: String, Sendable {
    /// Display the element inline.
    case inline = "inline"
    /// Display the element as a block.
    case block = "block"
    /// Hide the element entirely.
    case none = "none"

    static let `default`: SVGDisplaytype = SVGDisplaytype.inline
}

/// Whether an element is rendered (`visibility` property).
public enum SVGVisibility: String, Sendable {
    /// Render the element normally.
    case visible = "visible"
    /// Hide the element while keeping layout space.
    case hidden = "hidden"
    /// Collapse the element (treated as hidden for non-table elements).
    case collapse = "collapse"

    static let `default`: SVGVisibility = SVGVisibility.visible
}

/// The shape of the end caps of an SVG stroke.
public enum SVGLineCap: String, Sendable {
    /// The stroke ends exactly at the path endpoint (no cap).
    case butt = "butt"
    /// A semicircular cap extends beyond the endpoint.
    case round = "round"
    /// A square cap extends beyond the endpoint.
    case square = "square"
}

/// The shape used to join two stroke segments.
public enum SVGLineJoin: String, Sendable {
    /// A sharp (mitered) corner.
    case miter = "miter"
    /// A rounded corner.
    case round = "round"
    /// A beveled (flattened) corner.
    case bevel = "bevel"
}




