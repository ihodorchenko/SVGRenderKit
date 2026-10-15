import UIKit

/// A single text run (direct `<text>` content or a `<tspan>` child).
struct SVGTextSpan {
    var text: String
    var x: CGFloat?
    var y: CGFloat?
    var dx: CGFloat = 0
    var dy: CGFloat = 0
}

/// A drawable shape that renders an SVG `<text>` element.
open class SVGTextTag: SVGShapeObject {
    class override var key: String { get { return "text" }}

    private static let screenScaleBox = LockedBox<CGFloat>(2)
    /// Display scale used for text layers; set from the main thread before background rendering.
    static var screenScale: CGFloat {
        get { screenScaleBox.value }
        set { screenScaleBox.value = newValue }
    }

    var x: CGFloat = 0
    var y: CGFloat = 0
    var textAnchor: String = "start"
    private(set) var tspans: [SVGTextSpan] = []

    /// Initializes a text element by parsing its `x` and `y` attributes.
    public required init(xmlElement: XMLElement, addDict: [String: String]? = nil, parent: SVGShapesContainer) throws {
        try super.init(xmlElement: xmlElement, addDict: addDict, parent: parent)

        // `x`/`y` are length lists in SVG; only the first value is honored (per-glyph
        // positioning is out of scope) and malformed values degrade to 0, not a thrown error.
        if let str = attributeDict["x"] { x = SVGTextTag.firstLength(str) }
        if let str = attributeDict["y"] { y = SVGTextTag.firstLength(str) }
        if let str = attributeDict["text-anchor"] {
            textAnchor = str.trimmed
        }
        for child in xmlElement.xmlChildren where child.name == "tspan" {
            var span = SVGTextSpan(text: child.text, x: nil, y: nil)
            if let str = child.attribute(by: "x")?.text, let f = Float(str.trimmed) { span.x = CGFloat(f) }
            if let str = child.attribute(by: "y")?.text, let f = Float(str.trimmed) { span.y = CGFloat(f) }
            if let str = child.attribute(by: "dx")?.text, let f = Float(str.trimmed) { span.dx = CGFloat(f) }
            if let str = child.attribute(by: "dy")?.text, let f = Float(str.trimmed) { span.dy = CGFloat(f) }
            tspans.append(span)
        }
    }

    private static func firstLength(_ list: String) -> CGFloat {
        let first = list.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\n" || $0 == "\t" }).first
        guard let first = first, let length = try? SVGLength.get(string: String(first)) else { return 0 }
        switch length {
        case .px(let value): return value
        case .percent: return 0
        }
    }

    /// Builds and returns a text layer positioned at the element's `x` and `y` coordinates.
    public override func createLayer(addStyle: SVGSourceStyleElement?, overrideElements: [String: SVGSourceStyleElement]?) throws -> CALayer {
        let container = CALayer()

        var sourceStyle: SVGSourceStyleElement = resolvedStyle(overrideElements: overrideElements)
        if let addStyle = addStyle {
            sourceStyle = sourceStyle.combine(child: addStyle)
        }

        // Text honours `display`/`visibility` like any other element (B106).
        if sourceStyle.display == SVGDisplaytype.none { return container }
        if sourceStyle.visibility == .hidden || sourceStyle.visibility == .collapse { return container }
        // `text-anchor` may come from a presentation attribute, an inline `style` or a
        // `<style>` rule; the resolved style wins (B106).
        let anchor = sourceStyle.textAnchor ?? textAnchor

        // `fill`: none hides the text, currentColor resolves through `color`. Gradients and
        // patterns are not supported for text and degrade to the default black.
        var textColor = UIColor.black
        switch sourceStyle.fill {
        case .some(.none):
            return container
        case .some(.currentColor):
            textColor = sourceStyle.color ?? .black
        case .some(.color(let color)):
            textColor = color
        default:
            break
        }
        if let fillOpacity = sourceStyle.fillOpacity {
            var alpha: CGFloat = 1
            textColor.getRed(nil, green: nil, blue: nil, alpha: &alpha)
            textColor = textColor.withAlphaComponent(alpha * min(max(fillOpacity, 0), 1))
        }
        if let opacity = sourceStyle.opacity {
            container.opacity = opacity
        }
        let font = makeFont(from: sourceStyle)

        // Current text position: each run continues where the previous one ended, so a
        // `<tspan>` with only `dx`/`dy` follows the preceding text (start-anchored text only).
        var cursorX = x
        var cursorY = y
        let advances = anchor == "start"

        let preserveSpace = attributeDict["xml:space"] == "preserve"
        let mainText = SVGTextTag.normalize(xmlElement.text, preserve: preserveSpace)
        if !mainText.isEmpty {
            let layer = makeTextLayer(text: mainText, font: font, color: textColor, x: x, y: y, anchor: anchor)
            container.addSublayer(layer)
            if advances { cursorX += layer.bounds.width }
        }

        for span in tspans {
            let spanText = SVGTextTag.normalize(span.text, preserve: preserveSpace)
            guard !spanText.isEmpty else { continue }
            let spanX = span.x ?? (cursorX + span.dx)
            let spanY = span.y ?? (cursorY + span.dy)
            let layer = makeTextLayer(text: spanText, font: font, color: textColor, x: spanX, y: spanY, anchor: anchor)
            container.addSublayer(layer)
            cursorX = advances ? spanX + layer.bounds.width : spanX
            cursorY = spanY
        }

        return container
    }

    /// Collapses whitespace runs to a single space and trims (SVG's default `xml:space`
    /// handling). `xml:space="preserve"` keeps the text as written (B106).
    private static func normalize(_ text: String, preserve: Bool) -> String {
        if preserve { return text }
        return text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Builds a positioned `CATextLayer` for a single text run, applying `text-anchor` alignment.
    private func makeTextLayer(text: String, font: UIFont, color: UIColor, x: CGFloat, y: CGFloat, anchor: String) -> CATextLayer {
        let textLayer = CATextLayer()
        let attributedString = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color
        ])
        textLayer.string = attributedString
        textLayer.contentsScale = SVGTextTag.screenScale

        // CATextLayer does not auto-size: with a zero frame it draws nothing.
        // Size it to the rendered text so the glyphs have a drawing area.
        let size = textLayer.preferredFrameSize()
        textLayer.frame = CGRect(origin: .zero, size: size)
        // Anchor at the top-left so the `transform` translation below places the
        // text origin (and its baseline) precisely, instead of its center.
        textLayer.anchorPoint = CGPoint(x: 0, y: 0)

        var offsetX: CGFloat = 0
        switch anchor {
        case "middle":
            offsetX = -size.width / 2
        case "end":
            offsetX = -size.width
        default:
            offsetX = 0
        }

        var _transform: CATransform3D = CATransform3DIdentity
        if let transform = transform {
            _transform = transform
        }
        let px = x + offsetX
        // SVG `y` is the text baseline; CATextLayer's top edge sits one ascent
        // above the baseline, so shift up accordingly.
        let py = y - font.ascender
        if px != 0 || py != 0 {
            _transform = CATransform3DTranslate(_transform, px, py, 0)
        }
        if !CATransform3DIsIdentity(_transform) {
            textLayer.transform = _transform
        }

        return textLayer
    }

    private struct FontKey: Hashable {
        let family: String?
        let size: CGFloat
        let weight: Float?
        let style: SVGFontStyle?
    }

    private static let fontCache = SVGBoundedCache<FontKey, UIFont>(limit: 64)

    /// Resolves the font for the style, reusing fonts across text nodes: font lookup by name and
    /// descriptor is comparatively expensive and repeats identically for every run.
    private func makeFont(from sourceStyle: SVGSourceStyleElement) -> UIFont {
        let key = FontKey(
            family: sourceStyle.fontFamily,
            size: sourceStyle.fontSize?.resolvedPx(relativeTo: 16.0) ?? 16.0,
            weight: sourceStyle.fontWeight,
            style: sourceStyle.fontStyle)
        return Self.fontCache.value(for: key) { buildFont(from: sourceStyle) } ?? buildFont(from: sourceStyle)
    }

    /// Builds a `UIFont` from the resolved font-related style values.
    private func buildFont(from sourceStyle: SVGSourceStyleElement) -> UIFont {
        // SVG's default `font-size` is the `medium` keyword, i.e. 16px (not 17).
        let size = sourceStyle.fontSize?.resolvedPx(relativeTo: 16.0) ?? 16.0

        // Prefer an explicitly named family; try each comma-separated candidate.
        // Candidates may be quoted (`'Helvetica', sans-serif`), so drop the quotes (B106).
        if let family = sourceStyle.fontFamily {
            for name in family.split(separator: ",") {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if !trimmed.isEmpty, let font = UIFont(name: trimmed, size: size) {
                    return applyingWeightAndStyle(to: font, from: sourceStyle, size: size)
                }
            }
        }

        var font = UIFont.systemFont(ofSize: size, weight: weight(from: sourceStyle.fontWeight))

        if let fontStyle = sourceStyle.fontStyle, fontStyle != .normal {
            if let descriptor = font.fontDescriptor.withSymbolicTraits(.traitItalic) {
                font = UIFont(descriptor: descriptor, size: size)
            }
        }
        return font
    }

    /// `UIFont(name:size:)` ignores `font-weight`/`font-style`, so apply them to the
    /// named family's descriptor (B106).
    private func applyingWeightAndStyle(to font: UIFont, from sourceStyle: SVGSourceStyleElement, size: CGFloat) -> UIFont {
        var traits: UIFontDescriptor.SymbolicTraits = []
        if let fontWeight = sourceStyle.fontWeight, fontWeight >= 600 { traits.insert(.traitBold) }
        if let fontStyle = sourceStyle.fontStyle, fontStyle != .normal { traits.insert(.traitItalic) }
        guard !traits.isEmpty, let descriptor = font.fontDescriptor.withSymbolicTraits(traits) else { return font }
        return UIFont(descriptor: descriptor, size: size)
    }

    /// Maps an SVG `font-weight` value to a `UIFont.Weight`.
    private func weight(from fontWeight: Float?) -> UIFont.Weight {
        guard let fontWeight = fontWeight else { return .regular }
        switch Int(fontWeight) {
        case ..<150: return .ultraLight
        case ..<250: return .thin
        case ..<350: return .light
        case ..<450: return .regular
        case ..<550: return .medium
        case ..<650: return .semibold
        case ..<750: return .bold
        case ..<850: return .heavy
        default: return .black
        }
    }
}
