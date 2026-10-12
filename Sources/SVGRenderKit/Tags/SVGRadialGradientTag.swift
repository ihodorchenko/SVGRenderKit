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
    /// Focal x; defaults to `cx` when unspecified.
    var fx: SVGLength?
    /// Focal y; defaults to `cy` when unspecified.
    var fy: SVGLength?

    /// Returns whether the gradient has at least one color stop and can be rendered.
    public override func isEnable() -> Bool {
        return stops.count >= 1
    }

    /// Builds a masked layer that draws this radial gradient.
    open override func getGradientLayer(maskLayer: CALayer, path: UIBezierPath, viewBox: CGRect, currentColor: UIColor = .black) -> CALayer? {
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

        // The focal point defaults to the center when fx/fy are not specified.
        let focal = CGPoint(
            x: resolveCoordinate(fx ?? cx, dimension: boundsToPoints.width),
            y: resolveCoordinate(fy ?? cy, dimension: boundsToPoints.height))

        // SVG normalizes radial radius against the diagonal of the viewport.
        let diagonal = hypot(boundsToPoints.width, boundsToPoints.height) / sqrt(2)
        let radius: CGFloat
        switch r {
        case .px(let value):
            radius = (gradientUnits == .objectBoundingBox) ? value * diagonal : value
        case .percent(let value):
            radius = value * diagonal
        }
        // A negative radius disables the gradient (SVG 1.1).
        guard radius >= 0 else { return nil }

        // User-space coordinates are absolute while the layer's frame starts at the viewBox origin.
        let origin: CGPoint = gradientUnits == .userSpaceOnUse ? boundsToPoints.origin : .zero
        let toLocal = CGAffineTransform(translationX: -origin.x, y: -origin.y)

        var finalCenter = center
        var finalFocal = focal
        var finalRadius = radius
        var ellipticalTransform: CGAffineTransform?
        if let transform = transform {
            let affine = CATransform3DGetAffineTransform(transform)
            // Similarity transforms (translate/rotate/uniform scale) keep the gradient circular,
            // so they are folded into center/focal/radius. Anything else (non-uniform scale or
            // skew) makes it elliptical, which is drawn by transforming the context instead.
            let isSimilarity = abs(affine.a * affine.c + affine.b * affine.d) < 1e-6
                && abs((affine.a * affine.a + affine.b * affine.b) - (affine.c * affine.c + affine.d * affine.d)) < 1e-6
            if isSimilarity {
                finalCenter = center.applying(affine)
                finalFocal = focal.applying(affine)
                finalRadius = radius * sqrt(abs(affine.a * affine.d - affine.b * affine.c))
            } else {
                ellipticalTransform = affine.concatenating(toLocal)
            }
        }
        if ellipticalTransform == nil {
            finalCenter = finalCenter.applying(toLocal)
            finalFocal = finalFocal.applying(toLocal)
        } else {
            finalCenter = center
            finalFocal = focal
        }

        let newLayer: CALayer = CALayer()
        let gradLayer = RadialGradientLayer()
        newLayer.frame = boundsToPoints
        gradLayer.frame = boundsToPoints
        gradLayer.mask = localizedMask(maskLayer, origin: boundsToPoints.origin)
        gradLayer.anchorPoint = CGPoint(x: 0, y: 0)
        gradLayer.position = CGPoint(x: 0, y: 0)
        gradLayer.center = finalCenter
        gradLayer.focalPoint = finalFocal
        gradLayer.radius = finalRadius
        if let ellipticalTransform = ellipticalTransform {
            gradLayer.gradientTransform = ellipticalTransform
        }

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
                    fx = hrefGradient.fx
                    fy = hrefGradient.fy

                    stops = hrefGradient.stops
                    // Attributes explicitly set on the referencing gradient take
                    // precedence over the referenced (href) gradient; only inherit
                    // when the referencing element leaves them unset (SVG 1.1 §13.2.4).
                    if attributeDict["gradientTransform"] == nil {
                        transform = hrefGradient.transform
                    }
                    if attributeDict["gradientUnits"] == nil {
                        gradientUnits = hrefGradient.gradientUnits
                    }
                    if attributeDict["spreadMethod"] == nil {
                        spreadMethod = hrefGradient.spreadMethod
                    }
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
        if let str = attributeDict["fx"] {
            fx = try SVGLength.get(string: str)
        }
        if let str = attributeDict["fy"] {
            fy = try SVGLength.get(string: str)
        }

        try parseStops(childs: xmlElement.xmlChildren)
    }
}
