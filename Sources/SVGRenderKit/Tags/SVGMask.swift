import UIKit

/// Defines a luminance/alpha mask that is applied to an element via its `mask` property.
open class SVGMask: SVGChildObject {
    /// The coordinate system used for the mask's position and size.
    public enum MaskUnits: String {
        case userSpaceOnUse = "userSpaceOnUse"
        case objectBoundingBox = "objectBoundingBox"
    }

    /// How the mask content is interpreted.
    public enum MaskType: String {
        case luminance = "luminance"
        case alpha = "alpha"
    }

    class override var key: String { get { return "mask" }}

    var sourceStyle: SVGSourceStyleElement?
    var transform: CATransform3D?

    private(set) var all: SVGTags<SVGObject> = SVGTags<SVGObject>()
    private(set) var uses: SVGTags<SVGUseTag> = SVGTags<SVGUseTag>()
    private(set) var shapes: SVGTags<SVGShapeObject> = SVGTags<SVGShapeObject>()

    var maskUnits: MaskUnits = MaskUnits.objectBoundingBox
    var maskContentUnits: MaskUnits = MaskUnits.userSpaceOnUse
    var maskType: MaskType = MaskType.luminance

    /// Initializes a mask by parsing its attributes and child elements.
    public required init(xmlElement: XMLElement, addDict: [String: String]? = nil, parent: SVGGroupProtocol) throws {
        try super.init(xmlElement: xmlElement, addDict: addDict, parent: parent)

        let tsStyle: SVGSourceStyleElement = SVGSourceStyleElement()
        if let str = attributeDict["style"] {
            try tsStyle.set(styleStr: str, force: false)
        }
        try tsStyle.set(attributeDict: attributeDict)
        sourceStyle = tsStyle

        if let str = attributeDict["maskUnits"], let f = MaskUnits(rawValue: str) { maskUnits = f }
        if let str = attributeDict["maskContentUnits"], let f = MaskUnits(rawValue: str) { maskContentUnits = f }
        if let str = attributeDict["mask-type"], let f = MaskType(rawValue: str) { maskType = f }

        if let str = attributeDict["transform"] {
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
}

extension SVGMask {
    /// Adds `<use>` references to the mask.
    public func add(uses: [SVGUseTag]) throws {
        for use in uses {
            use.parent = self
            self.uses.add(item: use)
            self.all.add(item: use)
        }
    }

    /// Adds shapes to the mask.
    public func add(shapes: [SVGShapeObject]) throws {
        for shape in shapes {
            shape.parent = self
            self.shapes.add(item: shape)
            self.all.add(item: shape)
        }
    }
}

extension SVGMask: SVGRendering {
    /// Builds and returns a layer containing the mask's shapes and `<use>` references.
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

extension SVGMask: SVGShapesContainer {
    public func getClipPath(byKey: String, fromParents: Bool) -> SVGClipPath? {
        return nil
    }

    public func getMask(byKey: String, fromParents: Bool) -> SVGMask? {
        return nil
    }

    public func getPattern(byKey: String, fromParents: Bool) -> SVGPattern? {
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

    public func getSvgOptions() -> SVGOptions {
        return parent.getSvgOptions()
    }
}
