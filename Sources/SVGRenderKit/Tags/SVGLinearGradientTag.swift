import UIKit

/// An SVG linear gradient defined by two points and a list of color stops.
open class SVGLinearGradientTag: SVGBaseGradient {
    class override var key: String { get { return "linearGradient" }}

    var x1: SVGLength = SVGLength.percent(value: 0)
    var x2: SVGLength = SVGLength.percent(value: 1)
    var y1: SVGLength = SVGLength.percent(value: 0)
    var y2: SVGLength = SVGLength.percent(value: 0)

    /// Returns whether this gradient has at least one color stop and can be rendered.
    public override func isEnable() -> Bool {
        resolveHref()
        return stops.count >= 1
    }

    /// Builds a masked layer that draws this linear gradient along its axis.
    open override func getGradientLayer(maskLayer: CALayer, path: UIBezierPath, viewBox: CGRect, currentColor: UIColor = .black) -> CALayer? {
        resolveHref()
        var colors: [CGColor] = []
        var locations: [CGFloat] = []

        // Sort only when needed: the gradient is shared by cached trees, so an unconditional
        // in-place sort would both waste work and write shared state on every use.
        if !stops.isSortedByOffset {
            stops.sort { (f, s) -> Bool in
                return f.offset < s.offset
            }
        }
        for stop in stops {
            // SVG 1.1 clamps stop offsets to [0, 1] rather than failing the gradient.
            let offset = max(0, min(1, stop.offset))
            locations.append(CGFloat(offset))
            colors.append(stop.resolvedColor(currentColor: currentColor).cgColor)
        }
        // A single stop renders as a solid color; duplicate it so CAGradientLayer
        // has a valid two-stop gradient.
        if colors.count == 1 {
            colors.append(colors[0])
            locations.append(1)
        }
        let spread = spreadAdjusted(colors: colors, locations: locations)
        colors = spread.colors
        locations = spread.locations

        if colors.count == locations.count && locations.count > 1 {
            let newLayer: CALayer = CALayer()
            let boundsToPoints: CGRect
            switch self.gradientUnits {
            case .userSpaceOnUse:
                boundsToPoints = viewBox
                break
            case .objectBoundingBox:
                boundsToPoints = path.bounds
                break
            }
            let gradLayer = CAGradientLayer()
            newLayer.addSublayer(gradLayer)

            gradLayer.masksToBounds = false
            // The gradient is set up in `boundsToPoints` (viewBox for user-space,
            // path bounds for object-bounding-box), so guard on that resolved rect
            // — not on `viewBox`. A viewBox of 1x1 or smaller must still render.
            if boundsToPoints.width > 0, boundsToPoints.height > 0 {
                gradLayer.anchorPoint = CGPoint.zero
                gradLayer.position = CGPoint.zero
                gradLayer.mask = localizedMask(maskLayer, origin: boundsToPoints.origin)
                let x1: CGFloat = resolveCoordinate(self.x1, dimension: boundsToPoints.width)
                let x2: CGFloat = resolveCoordinate(self.x2, dimension: boundsToPoints.width)
                let y1: CGFloat = resolveCoordinate(self.y1, dimension: boundsToPoints.height)
                let y2: CGFloat = resolveCoordinate(self.y2, dimension: boundsToPoints.height)
                gradLayer.frame = boundsToPoints
                gradLayer.anchorPoint = CGPoint.zero

                var _startPoint = CGPoint(x: x1, y: y1)
                var _endPoint = CGPoint(x: x2, y: y2)
                if let transform = transform {
                    // Apply the full affine `gradientTransform` (translation, rotation,
                    // scale, and skew) to the gradient axis, not just rotation.
                    let affineTransform = CATransform3DGetAffineTransform(transform)
                    _startPoint = _startPoint.applying(affineTransform)
                    _endPoint = _endPoint.applying(affineTransform)
                }

                // User-space coordinates are absolute; the gradient layer's frame starts at the
                // viewBox origin, so make them relative to it (a non-zero viewBox origin shifted
                // the gradient before).
                if gradientUnits == .userSpaceOnUse {
                    _startPoint.x -= boundsToPoints.origin.x
                    _startPoint.y -= boundsToPoints.origin.y
                    _endPoint.x -= boundsToPoints.origin.x
                    _endPoint.y -= boundsToPoints.origin.y
                }

                let points = LinearGradientFixer.fixPoints(
                    start: CGPoint(x: _startPoint.x/boundsToPoints.width, y: _startPoint.y/boundsToPoints.height),
                    end: CGPoint(x: _endPoint.x/boundsToPoints.width, y: _endPoint.y/boundsToPoints.height),
                    bounds: boundsToPoints.size)
                let fStartPoint: CGPoint = points.0
                let fEndPoint: CGPoint = points.1

                gradLayer.startPoint = fStartPoint
                gradLayer.endPoint = fEndPoint
            }

            gradLayer.colors = colors
            gradLayer.locations = locations.map { NSNumber(value: $0) }

            return newLayer
        }
        return nil
    }

    /// Creates a linear gradient by parsing attributes and color stops.
    public required init(xmlElement: XMLElement, addDict: [String: String]? = nil, parent: SVGGroupProtocol) throws {
        try super.init(xmlElement: xmlElement, addDict: addDict, parent: parent)

        if let str = attributeDict["x1"] {
            x1 = try SVGLength.get(string: str)
        }
        if let str = attributeDict["x2"] {
            x2 = try SVGLength.get(string: str)
        }
        if let str = attributeDict["y1"] {
            y1 = try SVGLength.get(string: str)
        }
        if let str = attributeDict["y2"] {
            y2 = try SVGLength.get(string: str)
        }

        try parseStops(childs: xmlElement.xmlChildren)
        // Stops may be inherited later through `xlink:href`; only a gradient with
        // neither its own stops nor a reference is unusable.
        if stops.count < 1, href == nil {
            throw SVGError.parseError(text: "LinearGradient no stop's")
        }
    }

    /// Inherits the gradient axis from a referenced gradient when this one does not set it.
    override func inherit(from source: SVGBaseGradient) {
        guard let source = source as? SVGLinearGradientTag else { return }
        if attributeDict["x1"] == nil { x1 = source.x1 }
        if attributeDict["x2"] == nil { x2 = source.x2 }
        if attributeDict["y1"] == nil { y1 = source.y1 }
        if attributeDict["y2"] == nil { y2 = source.y2 }
    }
}

/// A CALayer that draws a linear gradient between a start and end point.
public class SVGLinearGradientLayer: CALayer {
    private(set) var startPoint: CGPoint = CGPoint.zero// {didSet{setNeedsDisplay()}}
    private(set) var endPoint: CGPoint = CGPoint.zero// {didSet{setNeedsDisplay()}}
    private(set) var colors: [CGColor] = []
    private(set) var locations: [CGFloat] = []

    /// Creates an empty linear gradient layer.
    required override public init() {
        super.init()
        backgroundColor = UIColor.blue.cgColor
        needsDisplayOnBoundsChange = true
    }

    /// Creates a linear gradient layer by decoding it from an archive.
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    /// Creates a linear gradient layer by copying another layer.
    required override public init(layer: Any) {
        super.init(layer: layer)
    }

    func set(startPoint: CGPoint, endPoint: CGPoint, colors: [CGColor], locations: [CGFloat]) {
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.colors = colors
        self.locations = locations
    }

    func update() {
        setNeedsDisplay()
        needsDisplay()
    }

    /// Draws the linear gradient into the given graphics context.
    public override func draw(in ctx: CGContext) {
        if colors.count != locations.count {
            return
        }
        ctx.saveGState()
        if let cgGradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors as CFArray, locations: locations) {
            ctx.drawLinearGradient(
                cgGradient, start: startPoint, end: endPoint,
                options: [.drawsAfterEndLocation, .drawsBeforeStartLocation])
        }
        ctx.restoreGState()
    }
    
}
