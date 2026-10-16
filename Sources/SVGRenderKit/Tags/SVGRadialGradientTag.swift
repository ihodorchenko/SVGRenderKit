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
    /// Focal radius (`fr`, SVG 2). Unspecified means the gradient starts at a point.
    var fr: SVGLength?

    /// Returns whether the gradient has at least one color stop and can be rendered.
    public override func isEnable() -> Bool {
        resolveHref()
        return stops.count >= 1
    }

    /// Builds a masked layer that draws this radial gradient.
    open override func getGradientLayer(maskLayer: CALayer, path: UIBezierPath, viewBox: CGRect, currentColor: UIColor = .black) -> CALayer? {
        getGradientLayer(maskLayer: maskLayer, path: path, boundingBox: nil, viewBox: viewBox, currentColor: currentColor)
    }

    override func getGradientLayer(maskLayer: CALayer, path: UIBezierPath, boundingBox: CGRect?, viewBox: CGRect, currentColor: UIColor) -> CALayer? {
        resolveHref()
        let (colors, locations) = renderStops(currentColor: currentColor)

        guard colors.count == locations.count, locations.count > 1 else { return nil }

        switch gradientUnits {
        case .objectBoundingBox:
            return boundingBoxLayer(path: path, boundingBox: boundingBox, maskLayer: maskLayer, colors: colors, locations: locations)
        case .userSpaceOnUse:
            return userSpaceLayer(viewBox: viewBox, maskLayer: maskLayer, colors: colors, locations: locations)
        }
    }

    /// `objectBoundingBox` radial gradient: the gradient is defined in the element's
    /// unit square and mapped onto the bounding box with an independent x and y scale,
    /// so a radius fraction `r` becomes the ellipse `r·w` by `r·h` — not a circle.
    /// `gradientTransform` applies in the unit square, before that mapping (SVG 1.1
    /// §13.2.2).
    private func boundingBoxLayer(path: UIBezierPath, boundingBox: CGRect?, maskLayer: CALayer, colors: [CGColor], locations: [CGFloat]) -> CALayer? {
        // The layer covers the path's bounds; the gradient itself resolves against the geometry's
        // box when one is given (a stroke, B135) — a degenerate box falls back to the layer's.
        let frame = path.bounds
        guard frame.width > 0, frame.height > 0 else { return nil }
        var bbox = frame
        if let box = boundingBox, box.width > 0, box.height > 0 { bbox = box }

        let center = CGPoint(x: unitFraction(cx), y: unitFraction(cy))
        // The focal point defaults to the center when fx/fy are not specified.
        let focal = CGPoint(x: unitFraction(fx ?? cx), y: unitFraction(fy ?? cy))
        let radius = unitFraction(r)
        let focalRadius = max(0, unitFraction(fr ?? .percent(value: 0)))
        // A negative radius disables the gradient (SVG 1.1).
        guard radius >= 0 else { return nil }

        var gradientToLocal = CGAffineTransform(scaleX: bbox.width, y: bbox.height)
        if let transform = transform {
            gradientToLocal = CATransform3DGetAffineTransform(transform).concatenating(gradientToLocal)
        }
        if bbox != frame {
            gradientToLocal = gradientToLocal.concatenating(CGAffineTransform(translationX: bbox.minX - frame.minX, y: bbox.minY - frame.minY))
        }
        return makeRadialLayer(frame: frame, maskLayer: maskLayer, center: center, focal: focal,
                               radius: radius, focalRadius: focalRadius, gradientTransform: gradientToLocal,
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
        func resolveRadius(_ length: SVGLength) -> CGFloat {
            switch length {
            case .px(let value): return value
            case .percent(let value): return value * diagonal
            }
        }
        let radius = resolveRadius(r)
        let focalRadius = max(0, resolveRadius(fr ?? .percent(value: 0)))
        // A negative radius disables the gradient (SVG 1.1).
        guard radius >= 0 else { return nil }

        // User-space coordinates are absolute while the layer's frame starts at the viewBox origin.
        let toLocal = CGAffineTransform(translationX: -viewBox.origin.x, y: -viewBox.origin.y)

        var finalCenter = center
        var finalFocal = focal
        var finalRadius = radius
        var finalFocalRadius = focalRadius
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
                let scale = sqrt(abs(affine.a * affine.d - affine.b * affine.c))
                finalRadius = radius * scale
                finalFocalRadius = focalRadius * scale
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
                               radius: finalRadius, focalRadius: finalFocalRadius,
                               gradientTransform: ellipticalTransform ?? .identity,
                               colors: colors, locations: locations)
    }

    /// Assembles the layer that draws a resolved radial gradient.
    private func makeRadialLayer(frame: CGRect, maskLayer: CALayer, center: CGPoint, focal: CGPoint,
                                 radius: CGFloat, focalRadius: CGFloat, gradientTransform: CGAffineTransform,
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
        gradLayer.focalRadius = focalRadius
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
        if let str = attributeDict["fr"] {
            fr = try SVGLength.get(string: str)
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
        if attributeDict["fr"] == nil { fr = source.fr }
    }
}
