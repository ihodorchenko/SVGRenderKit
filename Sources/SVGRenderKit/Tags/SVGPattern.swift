import UIKit

/// A `<pattern>` paint server: a tiled fill defined by a rectangle and its content.
open class SVGPattern: SVGChildObject {
    /// The coordinate system used for the pattern tile's `x`/`y`/`width`/`height`.
    public enum PatternUnits: String {
        case userSpaceOnUse = "userSpaceOnUse"
        case objectBoundingBox = "objectBoundingBox"
    }

    class override var key: String { get { return "pattern" }}

    var sourceStyle: SVGSourceStyleElement?
    var transform: CATransform3D?

    private(set) var all: SVGTags<SVGObject> = SVGTags<SVGObject>()
    private(set) var uses: SVGTags<SVGUseTag> = SVGTags<SVGUseTag>()
    private(set) var shapes: SVGTags<SVGShapeObject> = SVGTags<SVGShapeObject>()

    var patternUnits: PatternUnits = PatternUnits.objectBoundingBox
    var patternContentUnits: PatternUnits = PatternUnits.userSpaceOnUse
    var x: SVGLength = SVGLength.px(value: 0)
    var y: SVGLength = SVGLength.px(value: 0)
    var width: SVGLength = SVGLength.px(value: 0)
    var height: SVGLength = SVGLength.px(value: 0)

    /// Initializes a pattern by parsing its geometry attributes and child elements.
    public required init(xmlElement: XMLElement, addDict: [String: String]? = nil, parent: SVGGroupProtocol) throws {
        try super.init(xmlElement: xmlElement, addDict: addDict, parent: parent)

        let tsStyle: SVGSourceStyleElement = SVGSourceStyleElement()
        if let str = attributeDict["style"] {
            try tsStyle.set(styleStr: str, force: false)
        }
        try tsStyle.set(attributeDict: attributeDict)
        sourceStyle = tsStyle

        if let str = attributeDict["patternUnits"], let f = PatternUnits(rawValue: str) { patternUnits = f }
        if let str = attributeDict["patternContentUnits"], let f = PatternUnits(rawValue: str) { patternContentUnits = f }
        if let str = attributeDict["x"] { x = try SVGLength.get(string: str) }
        if let str = attributeDict["y"] { y = try SVGLength.get(string: str) }
        if let str = attributeDict["width"] { width = try SVGLength.get(string: str) }
        if let str = attributeDict["height"] { height = try SVGLength.get(string: str) }
        if let str = attributeDict["patternTransform"] {
            transform = try SVGTransform.get(string: str)
        }

        for children in xmlElement.xmlChildren {
            try parse(children: children)
        }
    }

    internal func parse(children: XMLElement) throws {
        switch children.name {
        case SVGUseTag.key:
            let use: SVGUseTag = try SVGUseTag(xmlElement: children, parent: self)
            try self.add(uses: [use])
        default:
            if let shapeTag = try SVGShapeObject.create(xml: children, parent: self) {
                try self.add(shapes: [shapeTag])
            }
        }
    }

    /// Renders the pattern content into a tile image, or `nil` if the tile has no size.
    /// `patternUnits`/`patternContentUnits` control how the tile and its content are
    /// mapped onto the element's bounding box.
    func tileImage(bbox: CGRect, viewBox: CGRect) -> UIImage? {
        let region = tileRegion(bbox: bbox, viewBox: viewBox)
        guard region.width > 0, region.height > 0 else { return nil }
        let size = region.size
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = max(1, getSvgOptions().renderScale)
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            if let layer = try? createLayer(overrideElements: nil) {
                let cg = context.cgContext
                if patternContentUnits == .objectBoundingBox {
                    cg.translateBy(x: bbox.origin.x - region.origin.x, y: bbox.origin.y - region.origin.y)
                    cg.scaleBy(x: bbox.width, y: bbox.height)
                } else {
                    cg.translateBy(x: -region.origin.x, y: -region.origin.y)
                }
                layer.render(in: cg)
            }
        }
    }

    private func resolveLength(_ length: SVGLength, bboxDimension: CGFloat, viewBoxDimension: CGFloat) -> CGFloat {
        switch patternUnits {
        case .objectBoundingBox:
            switch length {
            case .px(let value): return value * bboxDimension
            case .percent(let value): return value * bboxDimension
            }
        case .userSpaceOnUse:
            switch length {
            case .px(let value): return value
            case .percent(let value): return value * viewBoxDimension
            }
        }
    }

    private func tileRegion(bbox: CGRect, viewBox: CGRect) -> CGRect {
        let rx = resolveLength(x, bboxDimension: bbox.width, viewBoxDimension: viewBox.width)
        let ry = resolveLength(y, bboxDimension: bbox.height, viewBoxDimension: viewBox.height)
        let rw = resolveLength(width, bboxDimension: bbox.width, viewBoxDimension: viewBox.width)
        let rh = resolveLength(height, bboxDimension: bbox.height, viewBoxDimension: viewBox.height)
        switch patternUnits {
        case .objectBoundingBox:
            return CGRect(x: bbox.origin.x + rx, y: bbox.origin.y + ry, width: rw, height: rh)
        case .userSpaceOnUse:
            return CGRect(x: rx, y: ry, width: rw, height: rh)
        }
    }
}

extension SVGPattern {
    /// Adds `<use>` references to the pattern.
    public func add(uses: [SVGUseTag]) throws {
        for use in uses {
            use.parent = self
            self.uses.add(item: use)
            self.all.add(item: use)
        }
    }

    /// Adds shapes to the pattern.
    public func add(shapes: [SVGShapeObject]) throws {
        for shape in shapes {
            shape.parent = self
            self.shapes.add(item: shape)
            self.all.add(item: shape)
        }
    }
}

extension SVGPattern: SVGRendering {
    /// Builds a layer containing the pattern's shapes and `<use>` references.
    public func createLayer(addStyle: SVGSourceStyleElement?, overrideElements: [String: SVGSourceStyleElement]?) throws -> CALayer {
        let mainLayer: CAShapeLayer = CAShapeLayer()

        for use in uses.array {
            let layer = try use.createLayer(overrideElements: overrideElements)
            mainLayer.addSublayer(layer)
        }

        for path in shapes.array {
            let layer = try path.createLayer(overrideElements: overrideElements)
            mainLayer.addSublayer(layer)
        }

        if let transform = transform {
            mainLayer.transform = transform
        }

        return mainLayer
    }
}

extension SVGPattern: SVGShapesContainer {
    public func getClipPath(byKey: String, fromParents: Bool) -> SVGClipPath? {
        return nil
    }

    public func getMask(byKey: String, fromParents: Bool) -> SVGMask? {
        return nil
    }

    public func getPattern(byKey: String, fromParents: Bool) -> SVGPattern? {
        return nil
    }

    public func getMarker(byKey: String, fromParents: Bool) -> SVGMarker? {
        return nil
    }

    public func getFilter(byKey: String, fromParents: Bool) -> SVGFilter? {
        return nil
    }

    public func getRendering(byKey: String, fromParents: Bool) -> SVGRendering? {
        return parent.getRendering(byKey: byKey, fromParents: true)
    }

    public func getGradient(byKey: String, fromParents: Bool) -> SVGBaseGradient? {
        return parent.getGradient(byKey: byKey, fromParents: true)
    }

    public func getStyle(forObject: SVGShapeObject, overrideElements: [String: SVGSourceStyleElement]?) -> SVGSourceStyleElement {
        var style: SVGSourceStyleElement = parent.getStyle(forObject: forObject, overrideElements: overrideElements)
        if let selfStyle = self.sourceStyle {
            style = style.combine(child: selfStyle)
        }
        return style
    }

    public func selectorStyle(forObject: SVGShapeObject) -> SVGSourceStyleElement {
        return parent.selectorStyle(forObject: forObject)
    }

    public func getSvgOptions() -> SVGOptions {
        return parent.getSvgOptions()
    }
}
