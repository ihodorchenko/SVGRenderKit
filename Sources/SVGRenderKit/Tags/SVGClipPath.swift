import UIKit

/// Defines a clipping region that restricts rendering to the shapes and references it contains.
open class SVGClipPath: SVGChildObject {
    /// Specifies the coordinate system used to interpret the clip path's contents.
    public enum ClipPathUnits: String {
        /// Coordinates are interpreted in the current user coordinate system.
        case userSpaceOnUse = "userSpaceOnUse"
        /// Coordinates are interpreted relative to the bounding box of the clipped element.
        case objectBoundingBox = "objectBoundingBox"
    }
    class override var key: String { get { return "clipPath" }}

    var sourceStyle: SVGSourceStyleElement?
    var transform: CATransform3D?

    private(set) var all: SVGTags<SVGObject> = SVGTags<SVGObject>()
    private(set) var uses: SVGTags<SVGUseTag> = SVGTags<SVGUseTag>()
    private(set) var shapes: SVGTags<SVGShapeObject> = SVGTags<SVGShapeObject>()

    var clipPathUnits: ClipPathUnits = ClipPathUnits.userSpaceOnUse

    /// Initializes a clip path by parsing its `clipPathUnits`, `transform`, and child elements.
    public required init(xmlElement: XMLElement, addDict: [String: String]? = nil, parent: SVGGroupProtocol) throws {
        try super.init(xmlElement: xmlElement, addDict: addDict, parent: parent)

        let tsStyle: SVGSourceStyleElement = SVGSourceStyleElement()
        if let str = attributeDict["style"] {
            try tsStyle.set(styleStr: str, force: false)
        }
        try tsStyle.set(attributeDict: attributeDict)
        sourceStyle = tsStyle

        if let str = attributeDict["clipPathUnits"] {
            if let f: ClipPathUnits = ClipPathUnits.init(rawValue: str) { clipPathUnits = f } else {
                throw SVGError.parseError(text: "invalid convert 'clipPathUnits' to ClipPathUnits enum '\(str)'")
            }
        }

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
            break
        default:
            if let shapeTag = try SVGShapeObject.create(xml: children, parent: self) {
                try self.add(shapes: [shapeTag])
            }
            break
        }
    }
}

extension SVGClipPath {
    /// Adds `<use>` references to the clip path.
    public func add(uses: [SVGUseTag]) throws {
        for use in uses {
            use.parent = self
            self.uses.add(item: use)
            self.all.add(item: use)
        }
    }

    /// Adds shapes to the clip path.
    public func add(shapes: [SVGShapeObject]) throws {
        for shape in shapes {
            shape.parent = self
            self.shapes.add(item: shape)
            self.all.add(item: shape)
        }
    }

}

extension SVGClipPath: SVGRendering {
    /// Builds and returns a layer containing the clip path's shapes and `<use>` references.
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

extension SVGClipPath: SVGShapesContainer {
    /// Returns `nil`, since a clip path does not define nested clip paths.
    public func getClipPath(byKey: String, fromParents: Bool) -> SVGClipPath? {
        return nil
    }

    /// Resolves a renderable object by key from the parent container.
    public func getRendering(byKey: String, fromParents: Bool) -> SVGRendering? {
        return parent.getRendering(byKey: byKey, fromParents: true)
    }

    /// Resolves a gradient by key from the parent container.
    public func getGradient(byKey: String, fromParents: Bool) -> SVGBaseGradient? {
        return parent.getGradient(byKey: byKey, fromParents: true)
    }

    /// Returns the parent's style combined with the clip path's own style for the given shape.
    public func getStyle(forObject: SVGShapeObject, overrideElements: [String: SVGSourceStyleElement]?) -> SVGSourceStyleElement {
        var style: SVGSourceStyleElement = parent.getStyle(forObject: forObject, overrideElements: overrideElements)
        if let selfStyle = self.sourceStyle {
            style = style.combine(child: selfStyle)
        }
        return style
    }

    /// Returns the SVG options from the parent container.
    public func getSvgOptions() -> SVGOptions {
        return parent.getSvgOptions()
    }
}
