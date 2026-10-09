import UIKit

/// Holds the parsed layout options (view box, width, and height) of an SVG document.
open class SVGOptions {
    var width: SVGLength = SVGLength.percent(value: 1)
    var height: SVGLength = SVGLength.percent(value: 1)
    var viewBox: CGRect

    var size: CGSize

    /// Initializes options by parsing the `viewBox`, `width`, and `height` attributes.
    /// - parameter attributeDict: The attributes of the root `svg` element.
    public init(attributeDict: [String : String]) throws {
        var viewBox: CGRect?
        if let viewBoxStr = attributeDict["viewBox"] {
            let arr: [String] = SVGUtils.split(string: viewBoxStr, separator: " ")
            if arr.count == 4 {
                if let x = Double(arr[0]),
                    let y = Double(arr[1]),
                    let w = Double(arr[2]),
                    let h = Double(arr[3]) {
                    viewBox = CGRect(x: x, y: y, width: w, height: h)
                }
            }
        }
        var width: SVGLength?
        if let str = attributeDict["width"] {
            width = try SVGLength.get(string: str)
        }
        var height: SVGLength?
        if let str = attributeDict["height"] {
            height = try SVGLength.get(string: str)
        }

        if let viewBox = viewBox {
            self.viewBox = viewBox
            if let width = width, let height = height {
                self.width = width
                self.height = height

                self.size = CGSize.zero

                switch width {
                case .px(let value):
                    self.size.width = value
                case .percent(let value):
                    self.size.width = viewBox.width * value
                }
                switch height {
                case .px(let value):
                    self.size.height = value
                case .percent(let value):
                    self.size.height = viewBox.height * value
                }
            } else {
                self.width = SVGLength.px(value: viewBox.width)
                self.height = SVGLength.px(value: viewBox.height)
                self.size = CGSize(width: viewBox.width, height: viewBox.height)
            }
        } else {
            if let width = width, let height = height {
                var viewBox = CGRect.zero
                self.size = CGSize.zero

                switch width {
                case .px(let value):
                    viewBox.size.width = value
                    self.size.width = value
                case .percent(let value):
                   throw SVGError.parseError(text: "percent 'width' '\(value)' not supported")
                }
                switch height {
                case .px(let value):
                    viewBox.size.height = value
                    self.size.height = value
                case .percent(let value):
                    throw SVGError.parseError(text: "percent 'height' '\(value)' not supported")
                }
                self.width = width
                self.height = height
                self.viewBox = viewBox
            } else {
                throw SVGError.parseError(text: "invalid 'viewBox'")
            }
        }
    }
}

/// Represents the root `<svg>` element of an SVG document.
open class SVGSVGTag: SVGGroupObject {
    class override var key: String { get { return "svg" }}

    let options: SVGOptions

    /// Returns the parsed layout options for the SVG document.
    public override func getSvgOptions() -> SVGOptions {
        return options
    }



    /// Initializes the `<svg>` element by parsing its attributes and children.
    public required init(xmlElement: XMLElement, addDict: [String: String]? = nil, parent: SVGGroupProtocol) throws {
        var attributeDict: [String: String] = xmlElement.attributesDict()
        if let addDict = addDict {
            for elem in addDict {
                attributeDict[elem.key] = elem.value
            }
        }
        options = try SVGOptions(attributeDict: attributeDict)
        try super.init(xmlElement: xmlElement, addDict: addDict, parent: parent)


    }
}

extension SVGSVGTag: SVGRendering {
    /// Builds the root `CALayer` containing the layers of all child elements.
    public func createLayer(addStyle: SVGSourceStyleElement?, overrideElements: [String: SVGSourceStyleElement]?) throws -> CALayer {
        let mainLayer: CAShapeLayer = CAShapeLayer()


        if let sourceStyle = sourceStyle, let display = sourceStyle.display {
            switch display {
            case .inline:
                break
            case .block:
                break
            case .none:
                mainLayer.opacity = 0
                return mainLayer
            }
        }

        for layerElement in layerElements.array {
            if let group = layerElement as? SVGGTag {
                let layer = try group.createLayer(overrideElements: overrideElements)
                if layer.sublayers?.count ?? 0 > 0 {
                    mainLayer.addSublayer(layer)
                }
            } else if let path = layerElement as? SVGShapeObject {
                let layer = try path.createLayer(overrideElements: overrideElements)
                mainLayer.addSublayer(layer)
            }
        }

        if let transform = transform {
            mainLayer.transform = transform
        }

        return mainLayer
    }
}



/// The top-level container for a parsed SVG document.
open class SVGRoot {
    private(set) var svgElement: SVGSVGTag!

    /// Initializes the root from a single `svg` element.
    public init(xmlSvgElement: XMLElement) throws {
        self.svgElement = try SVGSVGTag(xmlElement: xmlSvgElement, addDict: nil, parent: self)
    }

    /// Initializes the root from an array of XML elements, using the first element.
    public init(xmlSvgElements: [XMLElement]) throws {
        if xmlSvgElements.count < 1 {
            throw SVGError.parseError(text: "no 'svg' tag")
        }
        self.svgElement = try SVGSVGTag(xmlElement: xmlSvgElements[0], addDict: nil, parent: self)
    }

    /// Builds and returns the root `CALayer` for the SVG document.
    /// - parameter overrideElements: Optional per-element style overrides.
    open func createLayer(overrideElements: [String: SVGSourceStyleElement]?) throws -> CALayer {
        return try svgElement.createLayer(overrideElements: overrideElements)
    }
}

extension SVGRoot: SVGGroupProtocol {
    /// Looks up a clip path by key. The root has no parent elements and returns `nil`.
    public func getClipPath(byKey: String, fromParents: Bool) -> SVGClipPath? {
        return nil
    }

    /// Looks up an object by key. The root has no parent elements and returns `nil`.
    public func getObject(byKey: String, fromParents: Bool) -> SVGObject? {
        return nil
    }

    /// Looks up a group (`<g>`) by key. The root has no parent elements and returns `nil`.
    public func getG(byKey: String, fromParents: Bool) -> SVGGTag? {
        return nil
    }

    /// Looks up a shape by key. The root has no parent elements and returns `nil`.
    public func getShape(byKey: String, fromParents: Bool) -> SVGShapeObject? {
        return nil
    }

    /// Looks up a linear gradient by key. The root has no parent elements and returns `nil`.
    public func getLinearGradient(byKey: String, fromParents: Bool) -> SVGLinearGradientTag? {
        return nil
    }

    /// Looks up a radial gradient by key. The root has no parent elements and returns `nil`.
    public func getRadialGradients(byKey: String, fromParents: Bool) -> SVGRadialGradientTag? {
        return nil
    }

    /// Returns the default empty style for the given shape.
    public func getStyle(forObject: SVGShapeObject, overrideElements: [String: SVGSourceStyleElement]?) -> SVGSourceStyleElement {
        return SVGSourceStyleElement()
    }

    /// Returns the parsed layout options of the document.
    public func getSvgOptions() -> SVGOptions {
        return svgElement.getSvgOptions()
    }

    /// Looks up a renderable element by key. The root has no parent elements and returns `nil`.
    public func getRendering(byKey: String, fromParents: Bool) -> SVGRendering? {
        return nil
    }

    /// Looks up a gradient by key. The root has no parent elements and returns `nil`.
    public func getGradient(byKey: String, fromParents: Bool) -> SVGBaseGradient? {
        return nil
    }

}
