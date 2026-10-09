import UIKit

/// Base class for SVG gradients, holding shared attributes and color stops.
open class SVGBaseGradient: SVGChildObject {
    enum GradientUnits: String {
        case userSpaceOnUse = "userSpaceOnUse"
        case objectBoundingBox = "objectBoundingBox"
    }

    var stops: [SVGGradientStop] = []
    var gradientUnits: GradientUnits = GradientUnits.userSpaceOnUse

    var transform: CATransform3D?

    /// Returns whether this gradient can be rendered. The base implementation returns false.
    public func isEnable() -> Bool {
        return false
    }

    /// Creates a gradient by parsing shared attributes from the given XML element.
    public required init(xmlElement: XMLElement, addDict: [String: String]? = nil, parent: SVGGroupProtocol) throws {
        try super.init(xmlElement: xmlElement, addDict: addDict, parent: parent)
        if let transformStr = attributeDict["gradientTransform"] {
            do {
                transform = try SVGTransform.get(string: transformStr.trimmed)
            } catch {
                // A malformed gradientTransform must not fail the whole parse.
                SVGLog.addSLog(errorStr: "Invalid gradientTransform '\(transformStr)': \(error.localizedDescription)")
            }
        }
        if let str = attributeDict["gradientUnits"], let gradientUnits = GradientUnits(rawValue: str.trimmed) {
            self.gradientUnits = gradientUnits
        }
    }

    internal func parseStops(childs: [XMLElement]) throws {
        var stops: [SVGGradientStop] = []
        for child in childs {
            if child.name == "stop" {
                let stop: SVGGradientStop = try SVGGradientStop(xmlElement: child)
                stops.append(stop)
            }
        }
        if stops.count > 0 {
            self.stops = stops
        }
    }

    /// Returns the layer that renders this gradient, or nil if it cannot be built.
    open func getGradientLayer(maskLayer: CALayer, path: UIBezierPath, viewBox: CGRect) -> CALayer? {
        return nil
    }
}

/// A CALayer that draws a radial gradient from its start point outward to its radius.
open class RadialGradientLayer: CALayer {

    /// Creates an empty radial gradient layer.
    required override public init() {
        super.init()
        needsDisplayOnBoundsChange = true
    }

    /// Creates a radial gradient layer by decoding it from an archive.
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    /// Creates a radial gradient layer by copying another layer.
    required override public init(layer: Any) {
        super.init(layer: layer)
    }

    var colors = [UIColor.red.cgColor, UIColor.blue.cgColor]
    /// The color-stop locations, expressed as fractions of the gradient radius.
    public var locations: [CGFloat] = [0, 1]
    /// The center point from which the gradient radiates.
    public var startPoint: CGPoint = CGPoint(x: 0, y: 0)
    /// The distance over which the gradient is drawn.
    public var radius: CGFloat = 1

    /// Draws the radial gradient into the given graphics context.
    override open func draw(in ctx: CGContext) {
        guard !colors.isEmpty, colors.count == locations.count else { return }

        ctx.saveGState()
        defer { ctx.restoreGState() }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: locations) else {
            return
        }

        let center = startPoint
        ctx.drawRadialGradient(
            gradient,
            startCenter: center,
            startRadius: 0.0,
            endCenter: center,
            endRadius: radius,
            options: CGGradientDrawingOptions(rawValue: 0))
    }
}

/// A single color stop within a gradient.
open class SVGGradientStop: SVGObject {
    class override var key: String { get { return "stop" }}

    var offset: Float = 0
    var stop_color: UIColor = UIColor.black

    /// Creates a gradient stop by parsing stop attributes from the given XML element.
    public override init(xmlElement: XMLElement, addDict: [String: String]? = nil) throws {
        try super.init(xmlElement: xmlElement, addDict: addDict)

        if let str = attributeDict["style"] {
            try set(styleStr: str)
        }
        try set(attributeDict: attributeDict)
    }

    func set(styleStr: String, force: Bool = false) throws {
        let params: [String] = SVGUtils.split(string: styleStr, separator: ";")

        var paramsDict: [String : String] = [:]
        for param in params {
            let arr = SVGUtils.split(string: param, separator: ":")
            if arr.count == 2 {
                let key = SVGUtils.trimmed(string: arr[0]).lowercased()
                let value = SVGUtils.trimmed(string: arr[1])
                if paramsDict[key] == nil || force {
                    paramsDict[key] = value
                }
            }
        }
        try set(attributeDict: paramsDict)
    }

    func set(attributeDict: [String: String]) throws {
        if let str = attributeDict["offset"], let f: Float = Float(str.trimmed) {
            offset = f
        }
        if let str = attributeDict["stop-color"] {
            stop_color = SVGColors.getColor(string: str)
        }
        if let str = attributeDict["stop-opacity"], let f: Float = Float(str.trimmed) {
            stop_color = stop_color.withAlphaComponent(CGFloat(f))
        }
    }
}
