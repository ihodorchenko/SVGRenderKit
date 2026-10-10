import UIKit

/// An SVG radial gradient defined by a center point, radius, and color stops.
open class SVGRadialGradientTag: SVGBaseGradient {
    class override var key: String { get { return "radialGradient" }}

    /// Center x, defaults to 50%.
    var cx: SVGLength = SVGLength.percent(value: 0.5)
    /// Center y, defaults to 50%.
    var cy: SVGLength = SVGLength.percent(value: 0.5)
    /// Radius, defaults to 50%.
    var r: SVGLength = SVGLength.percent(value: 0.5)

    /// Returns whether the gradient has at least one color stop and can be rendered.
    public override func isEnable() -> Bool {
        return stops.count >= 1
    }

    /// Builds a masked layer that draws this radial gradient.
    open override func getGradientLayer(maskLayer: CALayer, path: UIBezierPath, viewBox: CGRect, currentColor: UIColor = .black) -> CALayer? {
        var colors: [CGColor] = []
        var locations: [CGFloat] = []

        stops.sort { (f, s) -> Bool in
            return f.offset < s.offset
        }
        for stop in stops {
            // SVG 1.1 clamps stop offsets to [0, 1] rather than failing the gradient.
            let offset = max(0, min(1, stop.offset))
            locations.append(CGFloat(offset))
            colors.append(stop.resolvedColor(currentColor: currentColor).cgColor)
        }
        // A single stop renders as a solid color; duplicate it so the gradient
        // layer has a valid two-stop gradient.
        if colors.count == 1 {
            colors.append(colors[0])
            locations.append(1)
        }
        let spread = spreadAdjusted(colors: colors, locations: locations)
        colors = spread.colors
        locations = spread.locations

        guard colors.count == locations.count, locations.count > 1 else { return nil }

        let boundsToPoints: CGRect
        switch gradientUnits {
        case .userSpaceOnUse:
            boundsToPoints = viewBox
        case .objectBoundingBox:
            boundsToPoints = path.bounds
        }
        guard boundsToPoints.width > 0, boundsToPoints.height > 0 else { return nil }

        let center = CGPoint(
            x: resolveCoordinate(cx, dimension: boundsToPoints.width),
            y: resolveCoordinate(cy, dimension: boundsToPoints.height))

        // SVG normalizes radial radius against the diagonal of the viewport.
        let diagonal = hypot(boundsToPoints.width, boundsToPoints.height) / sqrt(2)
        let radius: CGFloat
        switch r {
        case .px(let value):
            radius = (gradientUnits == .objectBoundingBox) ? value * diagonal : value
        case .percent(let value):
            radius = value * diagonal
        }

        var finalCenter = center
        var finalRadius = radius
        if let transform = transform {
            let affine = CATransform3DGetAffineTransform(transform)
            finalCenter = center.applying(affine)
            // Scale the radius by the transform's geometric-mean scale factor.
            let scale = sqrt(abs(affine.a * affine.d - affine.b * affine.c))
            finalRadius = radius * scale
        }

        let newLayer: CALayer = CALayer()
        newLayer.mask = maskLayer
        let gradLayer = RadialGradientLayer()
        newLayer.frame = boundsToPoints
        gradLayer.frame = boundsToPoints
        gradLayer.mask = localizedMask(maskLayer, origin: boundsToPoints.origin)
        gradLayer.anchorPoint = CGPoint(x: 0, y: 0)
        gradLayer.position = CGPoint(x: 0, y: 0)
        gradLayer.startPoint = finalCenter
        gradLayer.radius = finalRadius

        gradLayer.colors = colors
        gradLayer.locations = locations
        newLayer.addSublayer(gradLayer)
        return newLayer
    }

    /// Creates a radial gradient by parsing center/radius, href references, and color stops.
    public required init(xmlElement: XMLElement, addDict: [String: String]? = nil, parent: SVGGroupProtocol) throws {
        try super.init(xmlElement: xmlElement, addDict: addDict, parent: parent)

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
                    spreadMethod = hrefGradient.spreadMethod
                }
            case .web:
                break
            }
        }

        if let str = attributeDict["cx"] {
            cx = try SVGLength.get(string: str)
        }
        if let str = attributeDict["cy"] {
            cy = try SVGLength.get(string: str)
        }
        if let str = attributeDict["r"] {
            r = try SVGLength.get(string: str)
        }

        try parseStops(childs: xmlElement.xmlChildren)
    }
}
