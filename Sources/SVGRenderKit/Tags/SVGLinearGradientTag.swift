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
        var res: Bool = true
        if stops.count < 1 {
            res = false
        }
        return res
    }

    /// Builds a masked layer that draws this linear gradient along its axis.
    open override func getGradientLayer(maskLayer: CALayer, path: UIBezierPath, viewBox: CGRect) -> CALayer? {
        var colors: [CGColor] = []
        var locations: [NSNumber] = []

        stops.sort { (f, s) -> Bool in
            return f.offset < s.offset
        }
        for stop in stops {
            if stop.offset >= 0 {
                locations.append(NSNumber(value: Float(stop.offset)))
            } else {
                return nil
            }
            colors.append(stop.stop_color.cgColor)
        }

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
            if viewBox.width > 1, viewBox.height > 1 {
                gradLayer.anchorPoint = CGPoint.zero
                gradLayer.position = CGPoint.zero
                gradLayer.mask = maskLayer
                let x1: CGFloat
                let x2: CGFloat
                let y1: CGFloat
                let y2: CGFloat
                switch self.x1 {
                case .px(let value):
                    x1 = value
                case .percent(let value):
                    x1 = value * boundsToPoints.width
                }
                switch self.x2 {
                case .px(let value):
                    x2 = value
                case .percent(let value):
                    x2 = value * boundsToPoints.width
                }
                switch self.y1 {
                case .px(let value):
                    y1 = value
                case .percent(let value):
                    y1 = value * boundsToPoints.height
                }
                switch self.y2 {
                case .px(let value):
                    y2 = value
                case .percent(let value):
                    y2 = value * boundsToPoints.height
                }
                gradLayer.frame = boundsToPoints
                gradLayer.anchorPoint = CGPoint.zero

                var _startPoint = CGPoint(x: x1, y: y1)
                var _endPoint = CGPoint(x: x2, y: y2)
                var finalBoundsToPoints = boundsToPoints
                if let transform = transform {
                    let originDegree: CGFloat = atan2(y2 - y1, x2 - x1)
                    let affineTransform = CATransform3DGetAffineTransform(transform)
                    let tempStartPoint = _startPoint.applying(affineTransform)
                    let tempEndPoint = _endPoint.applying(affineTransform)

                    finalBoundsToPoints = finalBoundsToPoints.applying(affineTransform)

                    let transformedDegree: CGFloat = atan2(tempEndPoint.y - tempStartPoint.y, tempEndPoint.x - tempStartPoint.x)
                    let affineTransformRotate = affineTransform.rotated(by: (originDegree - transformedDegree))
                    _startPoint = _startPoint.applying(affineTransformRotate)
                    _endPoint = _endPoint.applying(affineTransformRotate)

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
            gradLayer.locations = locations

            return newLayer
        }
        return nil
    }

    /// Creates a linear gradient by parsing attributes, href references, and color stops.
    public required init(xmlElement: XMLElement, addDict: [String: String]? = nil, parent: SVGGroupProtocol) throws {
        try super.init(xmlElement: xmlElement, addDict: addDict, parent: parent)

        if let href = href {
            switch href {
            case .local(let key):
                if let hrefGradient: SVGLinearGradientTag = parent.getLinearGradient(byKey: key, fromParents: true) {
                    x1 = hrefGradient.x1
                    x2 = hrefGradient.x2
                    y1 = hrefGradient.y1
                    y2 = hrefGradient.y2

                    stops = hrefGradient.stops
                    if let hrefTransform = hrefGradient.transform, let selfTransform = transform {
                        transform = CATransform3DConcat(hrefTransform, selfTransform)
                    } else if let hrefTransform = hrefGradient.transform {
                        self.transform = hrefTransform
                    }
                    gradientUnits = hrefGradient.gradientUnits
                }
                break
            case .web:
                throw SVGError.parseError(text: "web href not supported")
            }
        }

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
        if stops.count < 1 {
            throw SVGError.parseError(text: "LinearGradient no stop's")
        }
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

    }
    
}
