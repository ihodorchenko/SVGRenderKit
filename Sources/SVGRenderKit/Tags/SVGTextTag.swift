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

    private static let scaleLock = NSLock()
    private static var _screenScale: CGFloat = 2
    /// Display scale used for text layers; set from the main thread before background rendering.
    static var screenScale: CGFloat {
        get { scaleLock.lock(); defer { scaleLock.unlock() }; return _screenScale }
        set { scaleLock.lock(); defer { scaleLock.unlock() }; _screenScale = newValue }
    }

    var x: CGFloat = 0
    var y: CGFloat = 0
    var textAnchor: String = "start"
    private(set) var tspans: [SVGTextSpan] = []

    /// Initializes a text element by parsing its `x` and `y` attributes.
    public required init(xmlElement: XMLElement, addDict: [String: String]? = nil, parent: SVGShapesContainer) throws {
        try super.init(xmlElement: xmlElement, addDict: addDict, parent: parent)

        if let str = attributeDict["x"] {
            if let f: Float = Float(str.trimmed) { x = CGFloat(f) } else {
                throw SVGError.parseError(text: "invalid convert 'x' to float '\(str)'")
            }
        }
        if let str = attributeDict["y"] {
            if let f: Float = Float(str.trimmed) { y = CGFloat(f) } else {
                throw SVGError.parseError(text: "invalid convert 'y' to float '\(str)'")
            }
        }
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

    /// Builds and returns a text layer positioned at the element's `x` and `y` coordinates.
    public override func createLayer(addStyle: SVGSourceStyleElement?, overrideElements: [String: SVGSourceStyleElement]?) throws -> CALayer {
        let container = CALayer()

        var sourceStyle: SVGSourceStyleElement = self.sourceStyle
        sourceStyle = parent.getStyle(forObject: self, overrideElements: overrideElements).combine(child: sourceStyle)
        if let addStyle = addStyle {
            sourceStyle = sourceStyle.combine(child: addStyle)
        }

        var textColor = UIColor.black
        if let fill = sourceStyle.fill, case .color(let color) = fill {
            textColor = color
        }
        let font = makeFont(from: sourceStyle)

        let mainText = xmlElement.text
        if !mainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            container.addSublayer(makeTextLayer(text: mainText, font: font, color: textColor, x: x, y: y))
        }

        for span in tspans {
            let spanX = span.x ?? (x + span.dx)
            let spanY = span.y ?? (y + span.dy)
            container.addSublayer(makeTextLayer(text: span.text, font: font, color: textColor, x: spanX, y: spanY))
        }

        return container
    }

    /// Builds a positioned `CATextLayer` for a single text run, applying `text-anchor` alignment.
    private func makeTextLayer(text: String, font: UIFont, color: UIColor, x: CGFloat, y: CGFloat) -> CATextLayer {
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
        switch textAnchor {
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

    /// Builds a `UIFont` from the resolved font-related style values.
    private func makeFont(from sourceStyle: SVGSourceStyleElement) -> UIFont {
        let size = sourceStyle.fontSize?.resolvedPx(relativeTo: 17.0) ?? 17.0

        // Prefer an explicitly named family; try each comma-separated candidate.
        if let family = sourceStyle.fontFamily {
            for name in family.split(separator: ",") {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if let font = UIFont(name: trimmed, size: size) {
                    return font
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
