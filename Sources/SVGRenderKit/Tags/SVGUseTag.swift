import UIKit

/// Resolves and renders an SVG `<use>` element referencing another element by URL.
open class SVGUseTag: SVGObject, SVGRendering {
    class override var key: String { get { return "use" }}

    /// The owning parent. `unowned`: the parent owns this `<use>` and always outlives it.
    unowned var parent: SVGShapesContainer

    var sourceStyle: SVGSourceStyleElement?
    var transform: CATransform3D?

    var x: CGFloat = 0
    var y: CGFloat = 0
    var width: CGFloat?
    var height: CGFloat?

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
        if let str = attributeDict["width"], let f = Float(str.trimmed) {
            width = CGFloat(f)
        }
        if let str = attributeDict["height"], let f = Float(str.trimmed) {
            height = CGFloat(f)
        }

        if let str = attributeDict["transform"] {
            transform = try SVGTransform.get(string: str)
        }

        if href == nil {
            throw SVGError.parseError(text: "invalid 'href' in use")
        }
    }

    /// Bounds of the referenced content, offset by `x`/`y` (transforms are ignored, like `contentBounds`).
    var contentBounds: CGRect? {
        guard case .local(let key)? = href,
              let rendering = parent.getRendering(byKey: key, fromParents: true) else { return nil }
        let bounds: CGRect
        if let shape = rendering as? SVGShapeObject {
            bounds = shape.path.bounds
        } else if let group = rendering as? SVGGroupObject {
            bounds = group.contentBounds
        } else if let image = rendering as? SVGImage {
            bounds = image.frame(viewBox: parent.getSvgOptions().viewBox)
        } else {
            return nil
        }
        guard !bounds.isNull, !bounds.isEmpty else { return nil }
        return bounds.offsetBy(dx: x, dy: y)
    }

    private static let activeKey = "SVGRenderKit.SVGUseTag.active"

    /// Resolves the referenced element and returns its layer, applying any `x`, `y`, and transform offsets.
    public func createLayer(addStyle: SVGSourceStyleElement?, overrideElements: [String: SVGSourceStyleElement]?) throws -> CALayer {
        if let href = href {
            switch href {
            case .local(let key):
                if let rendering = parent.getRendering(byKey: key, fromParents: true) {
                    // Guard against reference cycles (`<g id="a"><use href="#a"/></g>`).
                    // Tracked per thread: a cached tree may render on several threads at once.
                    let marker = ObjectIdentifier(self)
                    let threadDict = Thread.current.threadDictionary
                    var active = (threadDict[SVGUseTag.activeKey] as? Set<ObjectIdentifier>) ?? []
                    guard !active.contains(marker) else {
                        throw SVGError.parseError(text: "circular reference in use '\(key)'")
                    }
                    active.insert(marker)
                    threadDict[SVGUseTag.activeKey] = active
                    defer {
                        active.remove(marker)
                        threadDict[SVGUseTag.activeKey] = active
                    }
                    let layer = try rendering.createLayer(addStyle: sourceStyle, overrideElements: overrideElements)
                    var _transform: CATransform3D = CATransform3DIdentity

                    if let symbol = rendering as? SVGSymbol, let viewBox = symbol.viewBox {
                        let containerSize = CGSize(width: width ?? viewBox.width, height: height ?? viewBox.height)
                        let resolved = symbol.preserveAspectRatio.resolve(viewBox: viewBox, containerSize: containerSize)
                        // CATransform3D helpers *pre*-multiply: the last call is applied to the point
                        // first. Desired mapping: translate(center) · scale · translate(-origin), so
                        // the centering shift is in container space and must not be scaled.
                        _transform = CATransform3DTranslate(_transform, resolved.translateX, resolved.translateY, 0)
                        _transform = CATransform3DScale(_transform, resolved.scaleX, resolved.scaleY, 1)
                        _transform = CATransform3DTranslate(_transform, -viewBox.origin.x, -viewBox.origin.y, 0)
                    }

                    if let transform = transform {
                        _transform = CATransform3DConcat(transform, _transform)
                    }
                    // `x`/`y` on `<use>` is a translate applied in the *parent*
                    // coordinate space, i.e. after the element's own transform.
                    // CATransform3DConcat(a,b) == a·b, so we post-multiply here.
                    if x != 0 || y != 0 {
                        _transform = CATransform3DConcat(_transform, CATransform3DMakeTranslation(x, y, 0))
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
