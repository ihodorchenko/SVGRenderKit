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
        resolveHref()
        return stops.count >= 1
    }

    /// Builds a masked layer that draws this radial gradient.
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

        switch gradientUnits {
        case .objectBoundingBox:
            return boundingBoxLayer(path: path, maskLayer: maskLayer, colors: colors, locations: locations)
        case .userSpaceOnUse:
            return userSpaceLayer(viewBox: viewBox, maskLayer: maskLayer, colors: colors, locations: locations)
        }
    }

    /// `objectBoundingBox` radial gradient: the gradient is defined in the element's
    /// unit square and mapped onto the bounding box with an independent x and y scale,
    /// so a radius fraction `r` becomes the ellipse `r·w` by `r·h` — not a circle.
    /// `gradientTransform` applies in the unit square, before that mapping (SVG 1.1
    /// §13.2.2).
    private func boundingBoxLayer(path: UIBezierPath, maskLayer: CALayer, colors: [CGColor], locations: [CGFloat]) -> CALayer? {
        let bbox = path.bounds
        guard bbox.width > 0, bbox.height > 0 else { return nil }

        let center = CGPoint(x: unitFraction(cx), y: unitFraction(cy))
        // The focal point defaults to the center when fx/fy are not specified.
        let focal = CGPoint(x: unitFraction(fx ?? cx), y: unitFraction(fy ?? cy))
        let radius = unitFraction(r)
        // A negative radius disables the gradient (SVG 1.1).
        guard radius >= 0 else { return nil }

        var gradientToLocal = CGAffineTransform(scaleX: bbox.width, y: bbox.height)
        if let transform = transform {
            gradientToLocal = CATransform3DGetAffineTransform(transform).concatenating(gradientToLocal)
        }
        return makeRadialLayer(frame: bbox, maskLayer: maskLayer, center: center, focal: focal,
                               radius: radius, gradientTransform: gradientToLocal,
                               colors: colors, locations: locations)
    }

    /// `userSpaceOnUse` radial gradient: coordinates are absolute and the radius is a
    /// plain length (a percentage is relative to the viewport's normalised diagonal).
    private func userSpaceLayer(viewBox: CGRect, maskLayer: CALayer, colors: [CGColor], locations: [CGFloat]) -> CALayer? {
        guard viewBox.width > 0, viewBox.height > 0 else { return nil }

        let center = CGPoint(
            x: resolveCoordinate(cx, dimension: viewBox.width),
            y: resolveCoordinate(cy, dimension: viewBox.height))
        let focal = CGPoint(
            x: resolveCoordinate(fx ?? cx, dimension: viewBox.width),
            y: resolveCoordinate(fy ?? cy, dimension: viewBox.height))

        // SVG normalizes a percentage radial radius against the viewport diagonal.
        let diagonal = hypot(viewBox.width, viewBox.height) / sqrt(2)
        let radius: CGFloat
        switch r {
        case .px(let value): radius = value
        case .percent(let value): radius = value * diagonal
        }
        // A negative radius disables the gradient (SVG 1.1).
        guard radius >= 0 else { return nil }

        // User-space coordinates are absolute while the layer's frame starts at the viewBox origin.
        let toLocal = CGAffineTransform(translationX: -viewBox.origin.x, y: -viewBox.origin.y)

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

        return makeRadialLayer(frame: viewBox, maskLayer: maskLayer, center: finalCenter, focal: finalFocal,
                               radius: finalRadius, gradientTransform: ellipticalTransform ?? .identity,
                               colors: colors, locations: locations)
    }

    /// Assembles the layer that draws a resolved radial gradient.
    private func makeRadialLayer(frame: CGRect, maskLayer: CALayer, center: CGPoint, focal: CGPoint,
                                 radius: CGFloat, gradientTransform: CGAffineTransform,
                                 colors: [CGColor], locations: [CGFloat]) -> CALayer {
        let newLayer: CALayer = CALayer()
        let gradLayer = RadialGradientLayer()
        newLayer.frame = frame
        gradLayer.frame = frame
        gradLayer.mask = localizedMask(maskLayer, origin: frame.origin)
        gradLayer.anchorPoint = CGPoint(x: 0, y: 0)
        gradLayer.position = CGPoint(x: 0, y: 0)
        gradLayer.center = center
        gradLayer.focalPoint = focal
        gradLayer.radius = radius
        gradLayer.gradientTransform = gradientTransform
        gradLayer.colors = colors
        gradLayer.locations = locations
        newLayer.addSublayer(gradLayer)
        return newLayer
    }

    /// Creates a radial gradient by parsing center/radius and color stops.
    public required init(xmlElement: XMLElement, addDict: [String: String]? = nil, parent: SVGGroupProtocol) throws {
        try super.init(xmlElement: xmlElement, addDict: addDict, parent: parent)

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

    /// Inherits the center/radius from a referenced gradient when this one does not set them.
    override func inherit(from source: SVGBaseGradient) {
        guard let source = source as? SVGRadialGradientTag else { return }
        if attributeDict["cx"] == nil { cx = source.cx }
        if attributeDict["cy"] == nil { cy = source.cy }
        if attributeDict["r"] == nil { r = source.r }
        if attributeDict["fx"] == nil { fx = source.fx }
        if attributeDict["fy"] == nil { fy = source.fy }
    }
}
