import UIKit

/// An SVG radial gradient defined by a center point, radius, and color stops.
open class SVGRadialGradientTag: SVGBaseGradient {
    class override var key: String { get { return "radialGradient" }}

    var cx: CGFloat?
    var cy: CGFloat?
    var r: CGFloat?

    var startPoint: CGPoint {
        get {
            if let cx = cx, let cy = cy {
                return CGPoint(x: cx, y: cy)
            }
            return CGPoint.zero
        }
    }

    /// Returns whether the center and radius are set and the gradient can be rendered.
    public override func isEnable() -> Bool {
        var res: Bool = true
        if cx == nil || cy == nil || r == nil {
            res = false
        }
        return res
    }

    /// Builds a masked layer that draws this radial gradient.
    open override func getGradientLayer(maskLayer: CALayer, path: UIBezierPath, viewBox: CGRect) -> CALayer? {
        var colors: [CGColor] = []
        var locations: [CGFloat] = []

        stops.sort { (f, s) -> Bool in
            return f.offset < s.offset
        }
        for stop in stops {
            if stop.offset >= 0 {
                locations.append(CGFloat(stop.offset))
            } else {
                return nil
            }
            colors.append(stop.stop_color.cgColor)
        }

        if colors.count == locations.count && locations.count > 1 {
            let newLayer: CALayer = CALayer()
            newLayer.mask = maskLayer
            let gradLayer = RadialGradientLayer()
            if let cx = cx, let cy = cy, let r = r, viewBox.width > 1, viewBox.height > 1 {
                newLayer.frame = viewBox
                gradLayer.frame = viewBox
                gradLayer.mask = maskLayer
                gradLayer.anchorPoint = CGPoint(x: 0, y: 0)
                gradLayer.position = CGPoint(x: 0, y: 0)
                if cx > 1 || cy > 1 {
                    gradLayer.startPoint = CGPoint(x: cx/viewBox.width, y: cy/viewBox.height)
                } else {
                    gradLayer.startPoint = CGPoint(x: cx, y: cy)
                }
                gradLayer.radius = r
            }

            gradLayer.colors = colors
            gradLayer.locations = locations
            newLayer.addSublayer(gradLayer)
            return newLayer
        }
        return nil
    }

    /// Creates a radial gradient by parsing center, radius, href references, and color stops.
    public required init(xmlElement: XMLElement, addDict: [String: String]? = nil, parent: SVGGroupProtocol) throws {
        try super.init(xmlElement: xmlElement, addDict: addDict, parent: parent)

        let attributeDict: [String: String] = xmlElement.attributesDict()

        if let href = href {
            switch href {
            case .local(let key):
                if let hrefGradient: SVGRadialGradientTag = parent.getRadialGradients(byKey: key, fromParents: true) {
                    cx = hrefGradient.cx
                    cy = hrefGradient.cy
                    r = hrefGradient.r

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
                break
            }
        }

        if let str = attributeDict["cx"], let f: Float = Float(str.trimmed) {
            cx = CGFloat(f)
        } else {
            throw SVGError.parseError(text: "RadialGradient cx")
        }
        if let str = attributeDict["cy"], let f: Float = Float(str.trimmed) {
            cy = CGFloat(f)
        } else {
            throw SVGError.parseError(text: "RadialGradient cy")
        }
        if let str = attributeDict["r"], let f: Float = Float(str.trimmed) {
            r = CGFloat(f)
        } else {
            throw SVGError.parseError(text: "RadialGradient r")
        }

        try parseStops(childs: xmlElement.xmlChildren)
    }
}
