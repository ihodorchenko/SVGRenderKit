import UIKit

/// A single text run (direct `<text>` content or a `<tspan>` child).
struct SVGTextSpan {
    var text: String
    /// Presentation attributes and inline `style` of a `<tspan>`; `nil` for a bare text node.
    var style: SVGSourceStyleElement?
    var x: CGFloat?
    var y: CGFloat?
    var dx: CGFloat = 0
    var dy: CGFloat = 0
}

/// A drawable shape that renders an SVG `<text>` element.
open class SVGTextTag: SVGShapeObject {
    class override var key: String { get { return "text" }}

    var x: CGFloat = 0
    var y: CGFloat = 0
    var textAnchor: String = "start"
    /// Text nodes and `<tspan>` children in document order.
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
        for node in xmlElement.children {
            if let textNode = node as? TextElement {
                tspans.append(SVGTextSpan(text: textNode.text, style: nil, x: nil, y: nil))
            } else if let child = node as? XMLElement, child.name == "tspan" {
                var span = SVGTextSpan(text: child.text, style: SVGTextTag.style(of: child), x: nil, y: nil)
                if let str = child.attribute(by: "x")?.text, let f = Float(str.trimmed) { span.x = CGFloat(f) }
                if let str = child.attribute(by: "y")?.text, let f = Float(str.trimmed) { span.y = CGFloat(f) }
                if let str = child.attribute(by: "dx")?.text, let f = Float(str.trimmed) { span.dx = CGFloat(f) }
                if let str = child.attribute(by: "dy")?.text, let f = Float(str.trimmed) { span.dy = CGFloat(f) }
                tspans.append(span)
            }
        }
    }

    /// A `<tspan>`'s own style: presentation attributes, then the inline `style` (which wins).
    private static func style(of element: XMLElement) -> SVGSourceStyleElement {
        let style = SVGSourceStyleElement()
        let attributes = element.attributesDict()
        try? style.set(attributeDict: attributes)
        if let inline = attributes["style"] { try? style.set(styleStr: inline) }
        return style
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

        // The glyph bitmap is rasterized at `renderScale`, so a resize must rebuild the layers.
        parent.getSvgOptions().usesMasks = true

        // Current text position: each run continues where the previous one ended, so a
        // `<tspan>` with only `dx`/`dy` follows the preceding text (start-anchored text only).
        var cursorX = x
        var cursorY = y
        let advances = anchor == "start"

        let preserveSpace = attributeDict["xml:space"] == "preserve"
        let texts = SVGTextTag.normalize(tspans.map { $0.text }, preserve: preserveSpace)
        for (span, text) in zip(tspans, texts) {
            guard !text.isEmpty else { continue }
            let runStyle = span.style.map { sourceStyle.combine(child: $0) } ?? sourceStyle
            let hasStroke = runStyle.hasStrokePaint
            // `fill="none"` hides the fill, but a stroked run must still be drawn.
            guard let color = textColor(of: runStyle) ?? (hasStroke ? .clear : nil) else { continue }
            let font = makeFont(from: runStyle)
            let runX = span.x ?? (cursorX + span.dx)
            let runY = span.y ?? (cursorY + span.dy)
            let layer = makeTextLayer(text: text, font: font, color: color, x: runX, y: runY, anchor: anchor, stroke: runStyle)
            // A whitespace-only run draws nothing: keep it out of the tree but still advance.
            if !text.allSatisfy({ $0.isWhitespace }) { container.addSublayer(layer) }
            cursorX = advances ? runX + layer.bounds.width : runX
            cursorY = runY
        }

        // `opacity`, `clip-path`, `mask` and `filter` composite the whole text (B136).
        let maskScale = (transform?.svgScaleFactor ?? 1) * ((parent as? SVGGroupObject)?.accumulatedScale() ?? 1)
        let bbox = (container.sublayers ?? []).reduce(CGRect.null) { $0.union($1.frame) }
        if sourceStyle.clipPath != nil || sourceStyle.mask != nil || sourceStyle.filter != nil {
            // A bare container has zero bounds, and a mask or filter renders into a buffer of
            // that size — everything would vanish. Cover the viewport and the text, keeping the
            // children's coordinates (bounds origin = layer position, anchor top-left).
            let area = bbox.isNull ? parent.getSvgOptions().viewBox : bbox.union(parent.getSvgOptions().viewBox)
            container.anchorPoint = .zero
            container.bounds = area
            container.position = area.origin
        }
        try sourceStyle.applyGroupComposite(to: container, bbox: bbox.isNull ? .zero : bbox, container: parent, overrideElements: overrideElements, maskScale: maskScale)

        return container
    }

    /// `fill`: none hides the text (returns `nil`), currentColor resolves through `color`.
    /// Gradients and patterns are not supported for text and degrade to the default black.
    private func textColor(of style: SVGSourceStyleElement) -> UIColor? {
        var textColor = UIColor.black
        switch style.fill {
        case .some(.none):
            return nil
        case .some(.currentColor):
            textColor = style.color ?? .black
        case .some(.color(let color)):
            textColor = color
        default:
            break
        }
        if let fillOpacity = style.fillOpacity {
            var alpha: CGFloat = 1
            textColor.getRed(nil, green: nil, blue: nil, alpha: &alpha)
            textColor = textColor.withAlphaComponent(alpha * min(max(fillOpacity, 0), 1))
        }
        return textColor
    }

    /// SVG's default `xml:space` handling over the whole element: newlines and tabs become
    /// spaces, a run of spaces collapses to one — also across run boundaries — and the
    /// text's leading and trailing space is dropped. `xml:space="preserve"` keeps the text
    /// as written (B106).
    private static func normalize(_ runs: [String], preserve: Bool) -> [String] {
        if preserve { return runs }
        var result: [String] = []
        var previousEndedWithSpace = true  // swallows the leading space of the text
        for run in runs {
            var out = ""
            for character in run {
                if character.isWhitespace {
                    if !previousEndedWithSpace { out.append(" "); previousEndedWithSpace = true }
                } else {
                    out.append(character)
                    previousEndedWithSpace = false
                }
            }
            result.append(out)
        }
        // Drop the trailing space of the whole text.
        if let last = result.lastIndex(where: { !$0.isEmpty }), result[last].hasSuffix(" ") {
            result[last].removeLast()
        }
        return result
    }

    /// Builds a positioned `CATextLayer` for a single text run, applying `text-anchor` alignment.
    private func makeTextLayer(text: String, font: UIFont, color: UIColor, x: CGFloat, y: CGFloat, anchor: String, stroke: SVGSourceStyleElement) -> CATextLayer {
        let textLayer = CATextLayer()
        let attributedString = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color
        ])
        textLayer.string = attributedString
        // Rasterize the glyphs at the output resolution. The document's `renderScale` tracks
        // that for both `SVGView` and `SVGRenderer`; a process-global screen scale does not
        // (B112).
        textLayer.contentsScale = max(1, parent.getSvgOptions().renderScale)

        // CATextLayer does not auto-size: with a zero frame it draws nothing.
        // Size it to the rendered text so the glyphs have a drawing area.
        let size = textLayer.preferredFrameSize()
        textLayer.frame = CGRect(origin: .zero, size: size)
        // Anchor at the top-left so the `transform` translation below places the
        // text origin (and its baseline) precisely, instead of its center.
        textLayer.anchorPoint = CGPoint(x: 0, y: 0)

        addStrokeLayer(to: textLayer, text: attributedString, ascender: font.ascender, style: stroke)

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

    /// `CATextLayer` cannot stroke, so a stroked run gets a sublayer carrying the glyph outlines
    /// (laid out by the same Core Text line, baseline `ascender` below the layer's top) on top
    /// of the fill. Width and dashes live in the layer's own space, so they scale with it.
    private func addStrokeLayer(to textLayer: CATextLayer, text: NSAttributedString, ascender: CGFloat, style: SVGSourceStyleElement) {
        guard style.hasStrokePaint else { return }
        let outline = CGMutablePath()
        let line = CTLineCreateWithAttributedString(text)
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let attributes = CTRunGetAttributes(run) as NSDictionary
            guard let runFont = attributes[kCTFontAttributeName as String] else { continue }
            let font = runFont as! CTFont
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            for (glyph, position) in zip(glyphs, positions) {
                guard let path = CTFontCreatePathForGlyph(font, glyph, nil) else { continue }
                outline.addPath(path, transform: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: position.x, ty: ascender - position.y))
            }
        }
        let strokeLayer = CAShapeLayer()
        guard style.applyTextStroke(to: strokeLayer, viewBox: parent.getSvgOptions().viewBox) else { return }
        strokeLayer.path = outline
        strokeLayer.frame = textLayer.bounds
        textLayer.addSublayer(strokeLayer)
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
