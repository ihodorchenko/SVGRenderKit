import UIKit

/// Base class for drawable SVG shapes that own a `UIBezierPath` and can render it to a layer.
open class SVGShapeObject: SVGObject, SVGRendering {
    var sourceStyle: SVGSourceStyleElement!
    var parent: SVGShapesContainer

    var transform: CATransform3D?
    
    var path: UIBezierPath = UIBezierPath()

    weak var lastLayer: CALayer?

    /// Initializes a shape object from an XML element and its parent shapes container.
    public required init(xmlElement: XMLElement, addDict: [String: String]? = nil, parent: SVGShapesContainer) throws {
        self.parent = parent
        try super.init(xmlElement: xmlElement, addDict: addDict)

        let sourceStyle: SVGSourceStyleElement = SVGSourceStyleElement()
        if let str = attributeDict["style"] {
            try sourceStyle.set(styleStr: str, force: false)
        }
        try sourceStyle.set(attributeDict: attributeDict)

        self.sourceStyle = sourceStyle

        if let str = attributeDict["transform"] {
            transform = try SVGTransform.get(string: str)
        }
    }

    /// Builds and returns the `CALayer` that renders this shape's path with the combined styles applied.
    public func createLayer(addStyle: SVGSourceStyleElement?, overrideElements: [String: SVGSourceStyleElement]?) throws -> CALayer {
        let mainLayer: CAShapeLayer = CAShapeLayer()
        let pathLayer: CAShapeLayer = CAShapeLayer()
        pathLayer.path = self.path.cgPath
        mainLayer.addSublayer(pathLayer)

        var sourceStyle: SVGSourceStyleElement = self.sourceStyle
        let parentSourceStyle = parent.getStyle(forObject: self, overrideElements: overrideElements)
        sourceStyle = parentSourceStyle.combine(child: sourceStyle)

        if let addStyle = addStyle {
            sourceStyle = sourceStyle.combine(child: addStyle)
        }
        if let overrideElements = overrideElements {
            if let tagElem = overrideElements[self.key] {
                sourceStyle = sourceStyle.combine(child: tagElem)
            }
            if let classStr = self.classStr, let idElem = overrideElements[classStr] {
                sourceStyle = sourceStyle.combine(child: idElem)
            }
            if let id = self.id, let idElem = overrideElements[id] {
                sourceStyle = sourceStyle.combine(child: idElem)
            }
        }

        try sourceStyle.styling(mainLayer: mainLayer, pathLayer: pathLayer, path: path, group: parent, overrideElements: overrideElements)

        if let transform = transform {
            mainLayer.transform = transform
        }

        self.lastLayer = mainLayer
        return mainLayer
    }

    class func create(xml: XMLElement, parent: SVGShapesContainer) throws -> SVGShapeObject? {
        switch xml.name {
        case SVGPath.key:
            return try SVGPath(xmlElement: xml, parent: parent)
        case SVGShapeRect.key:
            return try SVGShapeRect(xmlElement: xml, parent: parent)
        case SVGShapeCircle.key:
            return try SVGShapeCircle(xmlElement: xml, parent: parent)
        case SVGShapeEllipse.key:
            return try SVGShapeEllipse(xmlElement: xml, parent: parent)
        case SVGShapeLine.key:
            return try SVGShapeLine(xmlElement: xml, parent: parent)
        case SVGShapePolyline.key:
            return try SVGShapePolyline(xmlElement: xml, parent: parent)
        case SVGShapePolygon.key:
            return try SVGShapePolygon(xmlElement: xml, parent: parent)
        case SVGTextTag.key:
            return try SVGTextTag(xmlElement: xml, parent: parent)
        default:
            return nil
        }
    }

    internal func getSvgOptions() -> SVGOptions? {
        return parent.getSvgOptions()
    }

    func getGradient(byKey: String, fromParents: Bool) -> SVGBaseGradient? {
        return parent.getGradient(byKey: byKey, fromParents: true)
    }
}

/// A drawable shape that renders an SVG `<path>` element's `d` attribute.
open class SVGPath: SVGShapeObject {
    class override var key: String { get { return "path" }}
    
    enum SVGClipRule: String {
        case nonzero = "nonzero"
        case evenodd = "evenodd"
    }

    enum DisplayType: String {
        case inline = "inline"
        case none = "none"
    }

    /// Initializes a path by parsing its `d` attribute into a `UIBezierPath`.
    public required init(xmlElement: XMLElement, addDict: [String: String]? = nil, parent: SVGShapesContainer) throws {
        try super.init(xmlElement: xmlElement, addDict: addDict, parent: parent)

        if let str = attributeDict["d"] {
            let result = SVGParseString.parseSVGPath(pathString: str)
            if let svgError = result.error {
                throw svgError
            } else if let bezierPath = result.path {
                self.path = bezierPath
            }
        }
    }
}
