import UIKit

/// A `<marker>` element: a reusable glyph attached to the start/mid/end of a path.
open class SVGMarker: SVGChildObject {
    /// The coordinate system used for the marker's size.
    public enum MarkerUnits: String {
        case strokeWidth = "strokeWidth"
        case userSpaceOnUse = "userSpaceOnUse"
    }

    class override var key: String { get { return "marker" }}

    var sourceStyle: SVGSourceStyleElement?

    private(set) var all: SVGTags<SVGObject> = SVGTags<SVGObject>()
    private(set) var uses: SVGTags<SVGUseTag> = SVGTags<SVGUseTag>()
    private(set) var shapes: SVGTags<SVGShapeObject> = SVGTags<SVGShapeObject>()

    var markerWidth: CGFloat = 3
    var markerHeight: CGFloat = 3
    var markerUnits: MarkerUnits = MarkerUnits.strokeWidth
    var refX: CGFloat = 0
    var refY: CGFloat = 0
    var orient: String = "0"

    /// Initializes a marker by parsing its geometry attributes and child elements.
    public required init(xmlElement: XMLElement, addDict: [String: String]? = nil, parent: SVGGroupProtocol) throws {
        try super.init(xmlElement: xmlElement, addDict: addDict, parent: parent)

        let tsStyle: SVGSourceStyleElement = SVGSourceStyleElement()
        if let str = attributeDict["style"] {
            try tsStyle.set(styleStr: str, force: false)
        }
        try tsStyle.set(attributeDict: attributeDict)
        sourceStyle = tsStyle

        if let str = attributeDict["markerWidth"], let f = Float(str.trimmed) { markerWidth = CGFloat(f) }
        if let str = attributeDict["markerHeight"], let f = Float(str.trimmed) { markerHeight = CGFloat(f) }
        if let str = attributeDict["markerUnits"], let f = MarkerUnits(rawValue: str) { markerUnits = f }
        if let str = attributeDict["refX"], let f = Float(str.trimmed) { refX = CGFloat(f) }
        if let str = attributeDict["refY"], let f = Float(str.trimmed) { refY = CGFloat(f) }
        if let str = attributeDict["orient"] { orient = str.trimmed }

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

extension SVGMarker {
    /// Adds `<use>` references to the marker.
    public func add(uses: [SVGUseTag]) throws {
        for use in uses {
            use.parent = self
            self.uses.add(item: use)
            self.all.add(item: use)
        }
    }

    /// Adds shapes to the marker.
    public func add(shapes: [SVGShapeObject]) throws {
        for shape in shapes {
            shape.parent = self
            self.shapes.add(item: shape)
            self.all.add(item: shape)
        }
    }
}

extension SVGMarker: SVGRendering {
    /// Builds a layer containing the marker's shapes and `<use>` references.
    public func createLayer(addStyle: SVGSourceStyleElement?, overrideElements: [String: SVGSourceStyleElement]?) throws -> CALayer {
        let mainLayer: CALayer = CALayer()

        for use in uses.array {
            let layer = try use.createLayer(overrideElements: overrideElements)
            mainLayer.addSublayer(layer)
        }

        for path in shapes.array {
            let layer = try path.createLayer(overrideElements: overrideElements)
            mainLayer.addSublayer(layer)
        }

        return mainLayer
    }
}

extension SVGMarker: SVGShapesContainer {
    public func getClipPath(byKey: String, fromParents: Bool) -> SVGClipPath? { return nil }
    public func getMask(byKey: String, fromParents: Bool) -> SVGMask? { return nil }
    public func getPattern(byKey: String, fromParents: Bool) -> SVGPattern? { return nil }
    public func getMarker(byKey: String, fromParents: Bool) -> SVGMarker? { return nil }

    public func getFilter(byKey: String, fromParents: Bool) -> SVGFilter? { return nil }

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
