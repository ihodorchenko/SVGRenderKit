import UIKit

/// A drawable shape that renders an SVG `<text>` element.
open class SVGTextTag: SVGShapeObject {
    class override var key: String { get { return "text" }}

    var x: CGFloat = 0
    var y: CGFloat = 0

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
    }

    /// Builds and returns a text layer positioned at the element's `x` and `y` coordinates.
    public override func createLayer(addStyle: SVGSourceStyleElement?, overrideElements: [String: SVGSourceStyleElement]?) throws -> CALayer {
        let textLayer = CATextLayer()

        // Resolve the effective style: inherited + element's own + overrides.
        var sourceStyle: SVGSourceStyleElement = self.sourceStyle
        sourceStyle = parent.getStyle(forObject: self, overrideElements: overrideElements).combine(child: sourceStyle)
        if let addStyle = addStyle {
            sourceStyle = sourceStyle.combine(child: addStyle)
        }

        // Resolve the text color from the resolved fill.
        var textColor = UIColor.black
        if let fill = sourceStyle.fill, case .color(let color) = fill {
            textColor = color
        }

        let attributedString = NSAttributedString(string: xmlElement.text, attributes: [
            .font: makeFont(from: sourceStyle),
            .foregroundColor: textColor
        ])

        textLayer.string = attributedString
        textLayer.contentsScale = UIScreen.main.scale

        var _transform: CATransform3D = CATransform3DIdentity
        if let transform = transform {
            _transform = transform
        }
        if x != 0 || y != 0 {
            _transform = CATransform3DTranslate(_transform, x, y, 0)
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
