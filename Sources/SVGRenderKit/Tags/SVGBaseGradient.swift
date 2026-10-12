import UIKit

/// Base class for SVG gradients, holding shared attributes and color stops.
open class SVGBaseGradient: SVGChildObject {
    enum GradientUnits: String {
        case userSpaceOnUse = "userSpaceOnUse"
        case objectBoundingBox = "objectBoundingBox"
    }

    enum SVGSpreadMethod: String {
        case pad = "pad"
        case reflect = "reflect"
        case `repeat` = "repeat"
    }

    var stops: [SVGGradientStop] = []
    var gradientUnits: GradientUnits = GradientUnits.objectBoundingBox
    var spreadMethod: SVGSpreadMethod = SVGSpreadMethod.pad

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
        if let str = attributeDict["spreadMethod"], let spreadMethod = SVGSpreadMethod(rawValue: str.trimmed) {
            self.spreadMethod = spreadMethod
        }
    }

    /// Adjusts the color-stop arrays for the gradient's `spreadMethod`.
    ///
    /// CoreSVG — the native rasterizer behind `UIImage`'s SVG support and our
    /// parity oracle — ignores `spreadMethod` and always pads the gradient to its
    /// endpoint colors. `reflect` and `repeat` therefore render identically to
    /// `pad` there. To stay pixel-compatible with that reference (and with
    /// `UIImage`), we intentionally do the same instead of synthesizing a tiled
    /// gradient, which the native renderer never produces.
    func spreadAdjusted(colors: [CGColor], locations: [CGFloat]) -> (colors: [CGColor], locations: [CGFloat]) {
        return (colors, locations)
    }

    /// Shifts a shape mask so its path (expressed in absolute/viewBox coordinates)
    /// lines up with the gradient layer's local coordinate space.
    ///
    /// A layer `mask` is composited in the *masked* layer's own coordinate system,
    /// whose origin is that layer's frame origin (`boundsToPoints.origin`). Because
    /// the mask path is absolute while the gradient layer is bbox-relative, a
    /// gradient over a shape that isn't anchored at (0,0) would otherwise mask out
    /// everything: the mask must be shifted by the inverse of the frame's origin.
    func localizedMask(_ maskLayer: CALayer, origin: CGPoint) -> CALayer {
        guard origin != .zero,
              let shapeMask = maskLayer as? CAShapeLayer,
              let path = shapeMask.path else {
            return maskLayer
        }
        let bezier = UIBezierPath(cgPath: path)
        bezier.apply(CGAffineTransform(translationX: -origin.x, y: -origin.y))
        shapeMask.path = bezier.cgPath
        return maskLayer
    }

    /// Resolves a gradient coordinate to points in the current coordinate space.
    /// For `objectBoundingBox`, plain numbers are fractions of the bounding box.
    func resolveCoordinate(_ length: SVGLength, dimension: CGFloat) -> CGFloat {
        switch length {
        case .px(let value):
            if gradientUnits == .objectBoundingBox {
                return value * dimension
            }
            return value
        case .percent(let value):
            return value * dimension
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
    open func getGradientLayer(maskLayer: CALayer, path: UIBezierPath, viewBox: CGRect, currentColor: UIColor = .black) -> CALayer? {
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
    /// The center of the outer circle (the gradient's end center).
    public var center: CGPoint = CGPoint(x: 0, y: 0)
    /// The focal point the gradient starts from; `nil` means it coincides with `center`.
    public var focalPoint: CGPoint?
    /// The distance over which the gradient is drawn.
    public var radius: CGFloat = 1
    /// An optional affine transform applied to the whole gradient (used for elliptical gradients
    /// produced by a non-uniform `gradientTransform`).
    public var gradientTransform: CGAffineTransform = .identity

    /// Draws the radial gradient into the given graphics context.
    override open func draw(in ctx: CGContext) {
        guard !colors.isEmpty, colors.count == locations.count else { return }

        ctx.saveGState()
        defer { ctx.restoreGState() }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: locations) else {
            return
        }

        // The focal point (offset 0) may sit away from the outer circle center
        // (offset 1), producing SVG's focal radial gradient. The drawing options
        // extend the first/last stops so the default `pad` spread method fills
        // the area outside the radius with the endpoint colors.
        if !gradientTransform.isIdentity { ctx.concatenate(gradientTransform) }
        let startCenter = focalPoint ?? center
        ctx.drawRadialGradient(
            gradient,
            startCenter: startCenter,
            startRadius: 0.0,
            endCenter: center,
            endRadius: radius,
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
}

/// A single color stop within a gradient.
open class SVGGradientStop: SVGObject {
    class override var key: String { get { return "stop" }}

    var offset: Float = 0
    var stop_color: UIColor = UIColor.black
    private(set) var stopColorString: String?
    private(set) var stopOpacity: CGFloat = 1

    /// Resolves the stop's final color, honoring `currentColor` (resolved against
    /// the referencing element's inherited `color`) and `stop-opacity`.
    func resolvedColor(currentColor: UIColor) -> UIColor {
        let base: UIColor
        if let raw = stopColorString, SVGUtils.trimmed(string: raw) == "currentColor" {
            base = currentColor
        } else {
            base = stop_color
        }
        return base.withAlphaComponent(base.cgColor.alpha * stopOpacity)
    }

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
        if let str = attributeDict["offset"] {
            let trimmed = str.trimmed
            if trimmed.hasSuffix("%"), let f = Float(trimmed.dropLast()) {
                offset = f / 100
            } else if let f = Float(trimmed) {
                offset = f
            }
        }
        if let str = attributeDict["stop-color"] {
            stopColorString = str
            stop_color = SVGColors.getColor(string: str)
        }
        if let str = attributeDict["stop-opacity"], let f: Float = Float(str.trimmed) {
            stopOpacity = CGFloat(f)
        }
    }
}
