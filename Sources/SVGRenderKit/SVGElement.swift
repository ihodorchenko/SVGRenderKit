import UIKit

/// Controls how the `viewBox` is fitted and aligned within the viewport.
struct SVGPreserveAspectRatio {
    enum Align: String {
        case none = "none"
        case xMinYMin = "xMinYMin"
        case xMidYMin = "xMidYMin"
        case xMaxYMin = "xMaxYMin"
        case xMinYMid = "xMinYMid"
        case xMidYMid = "xMidYMid"
        case xMaxYMid = "xMaxYMid"
        case xMinYMax = "xMinYMax"
        case xMidYMax = "xMidYMax"
        case xMaxYMax = "xMaxYMax"
    }

    enum MeetOrSlice: String {
        case meet = "meet"
        case slice = "slice"
    }

    var align: Align = .xMidYMid
    var meetOrSlice: MeetOrSlice = .meet

    /// Parses a `preserveAspectRatio` attribute value. Falls back to the
    /// default `xMidYMid meet` for missing or unrecognized input.
    static func get(string: String?) -> SVGPreserveAspectRatio {
        var result = SVGPreserveAspectRatio()
        guard let string = string, !string.isEmpty else { return result }
        var tokens = string.components(separatedBy: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ","))).filter { !$0.isEmpty }
        if tokens.first == "defer" {
            tokens.removeFirst()
        }
        for token in tokens {
            if let align = Align(rawValue: token) {
                result.align = align
            } else if let meetOrSlice = MeetOrSlice(rawValue: token) {
                result.meetOrSlice = meetOrSlice
            }
        }
        return result
    }

    /// Computes the scale and translation needed to fit `viewBox` into a
    /// container of `containerSize` per this preserveAspectRatio setting.
    func resolve(viewBox: CGRect, containerSize: CGSize) -> (scaleX: CGFloat, scaleY: CGFloat, translateX: CGFloat, translateY: CGFloat) {
        // A degenerate viewBox (zero width or height) would divide by zero and
        // produce NaN/infinite transforms. Degrade to an empty layout instead.
        guard viewBox.width > 0, viewBox.height > 0 else {
            return (0, 0, 0, 0)
        }

        if align == .none {
            return (containerSize.width / viewBox.width,
                    containerSize.height / viewBox.height,
                    0, 0)
        }

        let sx = containerSize.width / viewBox.width
        let sy = containerSize.height / viewBox.height
        let scale: CGFloat = (meetOrSlice == .meet) ? min(sx, sy) : max(sx, sy)
        let renderedWidth = viewBox.width * scale
        let renderedHeight = viewBox.height * scale

        let translateX: CGFloat
        switch align {
        case .xMinYMin, .xMinYMid, .xMinYMax:
            translateX = 0
        case .xMidYMin, .xMidYMid, .xMidYMax:
            translateX = (containerSize.width - renderedWidth) / 2
        case .xMaxYMin, .xMaxYMid, .xMaxYMax:
            translateX = containerSize.width - renderedWidth
        case .none:
            translateX = 0
        }

        let translateY: CGFloat
        switch align {
        case .xMinYMin, .xMidYMin, .xMaxYMin:
            translateY = 0
        case .xMinYMid, .xMidYMid, .xMaxYMid:
            translateY = (containerSize.height - renderedHeight) / 2
        case .xMinYMax, .xMidYMax, .xMaxYMax:
            translateY = containerSize.height - renderedHeight
        case .none:
            translateY = 0
        }

        return (scale, scale, translateX, translateY)
    }
}

/// Holds the parsed layout options (view box, width, and height) of an SVG document.
open class SVGOptions {
    var width: SVGLength = SVGLength.percent(value: 1)
    var height: SVGLength = SVGLength.percent(value: 1)
    var viewBox: CGRect

    var size: CGSize

    /// How the `viewBox` is fitted and aligned within the viewport.
    var preserveAspectRatio: SVGPreserveAspectRatio = SVGPreserveAspectRatio()

    /// The scale factor mapping `viewBox` units to the rendering container's points.
    /// Set by `SVGView` after parsing so paint servers (e.g. patterns) rasterize at
    /// the final output resolution instead of the device screen scale. Defaults to `1`.
    var renderScale: CGFloat = 1

    /// Set once a pattern tile has been rasterized from this document, so `SVGView` knows
    /// the result depends on `renderScale` and must be re-rendered when its size changes.
    var usesPatterns = false

    /// The `version` attribute of the root `<svg>` element (e.g. `"1.1"`).
    var version: String?
    /// The `baseProfile` attribute of the root `<svg>` element (e.g. `"tiny"`).
    var baseProfile: String?

    /// Initializes options by parsing the `viewBox`, `width`, `height`, `preserveAspectRatio`,
    /// `version`, and `baseProfile` attributes.
    /// - parameter attributeDict: The attributes of the root `svg` element.
    public init(attributeDict: [String : String]) throws {
        self.preserveAspectRatio = SVGPreserveAspectRatio.get(string: attributeDict["preserveAspectRatio"])
        self.version = attributeDict["version"]
        self.baseProfile = attributeDict["baseProfile"]

        var viewBox: CGRect?
        if let viewBoxStr = attributeDict["viewBox"] {
            let cleaned = viewBoxStr.replacingOccurrences(of: ",", with: " ")
            let arr: [String] = SVGUtils.split(string: cleaned, separator: " ")
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

        let ownStyle = self.ownStyle()
        if let display = ownStyle.display {
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
                let layer = try group.createLayer(addStyle: addStyle, overrideElements: overrideElements)
                if layer.sublayers?.count ?? 0 > 0 {
                    mainLayer.addSublayer(layer)
                }
            } else if let path = layerElement as? SVGShapeObject {
                let layer = try path.createLayer(addStyle: addStyle, overrideElements: overrideElements)
                mainLayer.addSublayer(layer)
            } else if let use = layerElement as? SVGUseTag {
                let layer = try use.createLayer(addStyle: addStyle, overrideElements: overrideElements)
                mainLayer.addSublayer(layer)
            } else if let image = layerElement as? SVGImage {
                let layer = try image.createLayer(addStyle: addStyle, overrideElements: overrideElements)
                mainLayer.addSublayer(layer)
            }
        }

        if let transform = transform {
            mainLayer.transform = transform
        }

        try ownStyle.applyGroupComposite(to: mainLayer, bbox: contentBounds, container: self, overrideElements: overrideElements)

        return mainLayer
    }
}



/// The top-level container for a parsed SVG document.
open class SVGRoot {
    private(set) var svgElement: SVGSVGTag!

    /// Document-wide `id` → object map (keys keep the `#` prefix), so a reference can
    /// resolve any element in the document, not only one on the ancestor chain or a
    /// direct child (B88). First definition wins, as in browsers.
    private var idMap: [String: SVGObject] = [:]

    /// Initializes the root from a single `svg` element.
    public init(xmlSvgElement: XMLElement) throws {
        self.svgElement = try SVGSVGTag(xmlElement: xmlSvgElement, addDict: nil, parent: self)
        buildIdMap()
    }

    /// Initializes the root from an array of XML elements, using the first element.
    public init(xmlSvgElements: [XMLElement]) throws {
        if xmlSvgElements.count < 1 {
            throw SVGError.parseError(text: "no 'svg' tag")
        }
        self.svgElement = try SVGSVGTag(xmlElement: xmlSvgElements[0], addDict: nil, parent: self)
        buildIdMap()
    }

    private func buildIdMap() {
        var map: [String: SVGObject] = [:]
        SVGRoot.collect(svgElement, into: &map)
        idMap = map
    }

    private static func collect(_ group: SVGGroupObject, into map: inout [String: SVGObject]) {
        for object in group.all.array {
            if let id = object.id, map[id] == nil {
                map[id] = object
            }
            if let nested = object as? SVGGroupObject {
                collect(nested, into: &map)
            }
        }
        for defs in group.defsList {
            collect(defs, into: &map)
        }
    }

    /// Builds and returns the root `CALayer` for the SVG document.
    /// - parameter overrideElements: Optional per-element style overrides.
    open func createLayer(overrideElements: [String: SVGSourceStyleElement]?) throws -> CALayer {
        return try svgElement.createLayer(overrideElements: overrideElements)
    }
}

extension SVGRoot: SVGGroupProtocol {
    /// Returns the clip path with the given `id` from anywhere in the document.
    public func getClipPath(byKey: String, fromParents: Bool) -> SVGClipPath? {
        return idMap[byKey] as? SVGClipPath
    }

    /// Returns the mask with the given `id` from anywhere in the document.
    public func getMask(byKey: String, fromParents: Bool) -> SVGMask? {
        return idMap[byKey] as? SVGMask
    }

    /// Returns the pattern with the given `id` from anywhere in the document.
    public func getPattern(byKey: String, fromParents: Bool) -> SVGPattern? {
        return idMap[byKey] as? SVGPattern
    }

    /// Returns the marker with the given `id` from anywhere in the document.
    public func getMarker(byKey: String, fromParents: Bool) -> SVGMarker? {
        return idMap[byKey] as? SVGMarker
    }

    /// Returns the filter with the given `id` from anywhere in the document.
    public func getFilter(byKey: String, fromParents: Bool) -> SVGFilter? {
        return idMap[byKey] as? SVGFilter
    }

    /// Returns the object with the given `id` from anywhere in the document.
    public func getObject(byKey: String, fromParents: Bool) -> SVGObject? {
        return idMap[byKey]
    }

    /// Returns the group with the given `id` from anywhere in the document.
    public func getG(byKey: String, fromParents: Bool) -> SVGGTag? {
        return idMap[byKey] as? SVGGTag
    }

    /// Returns the shape with the given `id` from anywhere in the document.
    public func getShape(byKey: String, fromParents: Bool) -> SVGShapeObject? {
        return idMap[byKey] as? SVGShapeObject
    }

    /// Returns the symbol with the given `id` from anywhere in the document.
    public func getSymbol(byKey: String, fromParents: Bool) -> SVGSymbol? {
        return idMap[byKey] as? SVGSymbol
    }

    /// Returns the linear gradient with the given `id` from anywhere in the document.
    public func getLinearGradient(byKey: String, fromParents: Bool) -> SVGLinearGradientTag? {
        return idMap[byKey] as? SVGLinearGradientTag
    }

    /// Returns the radial gradient with the given `id` from anywhere in the document.
    public func getRadialGradients(byKey: String, fromParents: Bool) -> SVGRadialGradientTag? {
        return idMap[byKey] as? SVGRadialGradientTag
    }

    /// Returns the default empty style for the given shape.
    public func getStyle(forObject: SVGShapeObject, overrideElements: [String: SVGSourceStyleElement]?) -> SVGSourceStyleElement {
        return SVGSourceStyleElement()
    }

    /// Returns the parsed layout options of the document.
    public func getSvgOptions() -> SVGOptions {
        return svgElement.getSvgOptions()
    }

    /// Returns the renderable with the given `id` from anywhere in the document.
    public func getRendering(byKey: String, fromParents: Bool) -> SVGRendering? {
        return idMap[byKey] as? SVGRendering
    }

    /// Returns the gradient with the given `id` from anywhere in the document.
    public func getGradient(byKey: String, fromParents: Bool) -> SVGBaseGradient? {
        return idMap[byKey] as? SVGBaseGradient
    }

    /// Returns the image with the given `id` from anywhere in the document.
    public func getImage(byKey: String, fromParents: Bool) -> SVGImage? {
        return idMap[byKey] as? SVGImage
    }
}
