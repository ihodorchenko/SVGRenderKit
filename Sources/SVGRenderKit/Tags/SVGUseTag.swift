import UIKit

/// Resolves and renders an SVG `<use>` element referencing another element by URL.
open class SVGUseTag: SVGObject, SVGRendering {
    class override var key: String { get { return "use" }}

    var parent: SVGShapesContainer

    var sourceStyle: SVGSourceStyleElement?
    var transform: CATransform3D?

    var x: CGFloat = 0
    var y: CGFloat = 0

    /// Initializes a `<use>` tag by parsing its `href`, `x`, `y`, and `transform` attributes.
    public required init(xmlElement: XMLElement, addDict: [String: String]? = nil, parent: SVGShapesContainer) throws {
        self.parent = parent
        try super.init(xmlElement: xmlElement, addDict: addDict)

        let tsStyle: SVGSourceStyleElement = SVGSourceStyleElement()
        if let str = attributeDict["style"] {
            try tsStyle.set(styleStr: str, force: false)
        }
        try tsStyle.set(attributeDict: attributeDict)
        sourceStyle = tsStyle

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

        if let str = attributeDict["transform"] {
            transform = try SVGTransform.get(string: str)
        }

        if href == nil {
            throw SVGError.parseError(text: "invalid 'href' in use")
        }
    }

    /// Resolves the referenced element and returns its layer, applying any `x`, `y`, and transform offsets.
    public func createLayer(addStyle: SVGSourceStyleElement?, overrideElements: [String: SVGSourceStyleElement]?) throws -> CALayer {
        if let href = href {
            switch href {
            case .local(let key):
                if let rendering = parent.getRendering(byKey: key, fromParents: true) {
                    let layer = try rendering.createLayer(addStyle: sourceStyle, overrideElements: overrideElements)
                    var _transform: CATransform3D = CATransform3DIdentity
                    if let transform = transform {
                        _transform = transform
                    }
                    if x != 0 || y != 0 {
                        _transform = CATransform3DTranslate(_transform, x, y, 0)
                    }
                    if !CATransform3DIsIdentity(_transform) {
                        layer.transform = _transform
                    }
                    return layer
                } else {
                    throw SVGError.parseError(text: "object 'href' in use not found")
                }
            case .web:
                throw SVGError.parseError(text: "web 'href' in use not supported")
            }
        } else {
            throw SVGError.parseError(text: "not found 'href' in use")
        }
    }
}
