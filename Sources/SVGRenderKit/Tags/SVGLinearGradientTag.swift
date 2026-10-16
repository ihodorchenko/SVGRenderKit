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
        getGradientLayer(maskLayer: maskLayer, path: path, boundingBox: nil, viewBox: viewBox, currentColor: currentColor)
    }

    override func getGradientLayer(maskLayer: CALayer, path: UIBezierPath, boundingBox: CGRect?, viewBox: CGRect, currentColor: UIColor) -> CALayer? {
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
            // The box the axis is resolved against, when it is not the layer's own frame (B135).
            let axisBox: CGRect? = {
                guard gradientUnits == .objectBoundingBox, let box = boundingBox,
                      box.width > 0, box.height > 0, box != boundsToPoints else { return nil }
                return box
            }()
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
                gradLayer.frame = boundsToPoints
                gradLayer.anchorPoint = CGPoint.zero

                // Work in the gradient's own coordinate system: the element's unit
                // square for objectBoundingBox, absolute user units for userSpaceOnUse.
                // `gradientTransform` is applied there — not to already-absolute points,
                // which put an objectBoundingBox transform in the wrong space (B93).
                var _startPoint: CGPoint
                var _endPoint: CGPoint
                switch gradientUnits {
                case .objectBoundingBox:
                    _startPoint = CGPoint(x: unitFraction(self.x1), y: unitFraction(self.y1))
                    _endPoint = CGPoint(x: unitFraction(self.x2), y: unitFraction(self.y2))
                case .userSpaceOnUse:
                    _startPoint = CGPoint(
                        x: resolveCoordinate(self.x1, dimension: boundsToPoints.width),
                        y: resolveCoordinate(self.y1, dimension: boundsToPoints.height))
                    _endPoint = CGPoint(
                        x: resolveCoordinate(self.x2, dimension: boundsToPoints.width),
                        y: resolveCoordinate(self.y2, dimension: boundsToPoints.height))
                }

                // A gradient carries its normal along with its vector (SVG 1.1 §13.2.1):
                // the gradient transform maps the gradient's level lines, and the colour at
                // `p` is the colour the untransformed gradient has at `T⁻¹p`. A
                // `CAGradientLayer` projects onto its axis perpendicularly, so the axis has
                // to run along those mapped level lines — the inverse transpose of `T`
                // applied to the gradient vector — instead of along the mapped endpoints:
                // under a skew or a non-uniform scale the mapped endpoints keep the
                // pre-transform direction and would paint differently sloped stripes
                // (B119-11).
                let gradientVector = CGPoint(x: _endPoint.x - _startPoint.x, y: _endPoint.y - _startPoint.y)

                if let transform = transform {
                    // Apply the full affine `gradientTransform` (translation, rotation,
                    // scale, and skew) to the gradient axis in its own space.
                    let affineTransform = CATransform3DGetAffineTransform(transform)
                    _startPoint = _startPoint.applying(affineTransform)
                    _endPoint = _endPoint.applying(affineTransform)

                    let vectorLengthSquared = gradientVector.x * gradientVector.x + gradientVector.y * gradientVector.y
                    let determinant = affineTransform.a * affineTransform.d - affineTransform.b * affineTransform.c
                    if vectorLengthSquared > 0, abs(determinant) > 1e-12 {
                        let inverse = affineTransform.inverted()
                        // The field's direction is the inverse *transpose* of `T` applied
                        // to the gradient vector: `∇t' = (T⁻¹)ᵀ d` for `t' = t(T⁻¹p)`.
                        var direction = CGPoint(
                            x: (inverse.a * gradientVector.x + inverse.b * gradientVector.y) / vectorLengthSquared,
                            y: (inverse.c * gradientVector.x + inverse.d * gradientVector.y) / vectorLengthSquared)
                        let directionLengthSquared = direction.x * direction.x + direction.y * direction.y
                        // Scaling the direction by `1/|h|²` puts the value 1 back on the
                        // mapped end point, as `CAGradientLayer` interpolates
                        // `(p − A)·(B − A)/|B − A|²`.
                        if directionLengthSquared > 0 {
                            direction.x /= directionLengthSquared
                            direction.y /= directionLengthSquared
                            _endPoint = CGPoint(x: _startPoint.x + direction.x, y: _startPoint.y + direction.y)
                        }
                    }
                }

                // User-space coordinates are absolute; the gradient layer's frame starts at
                // the viewBox origin, so make them relative to it (a non-zero viewBox origin
                // shifted the gradient before), then normalized for CAGradientLayer.
                if gradientUnits == .userSpaceOnUse {
                    _startPoint.x -= boundsToPoints.origin.x
                    _startPoint.y -= boundsToPoints.origin.y
                    _endPoint.x -= boundsToPoints.origin.x
                    _endPoint.y -= boundsToPoints.origin.y
                    _startPoint.x /= boundsToPoints.width
                    _startPoint.y /= boundsToPoints.height
                    _endPoint.x /= boundsToPoints.width
                    _endPoint.y /= boundsToPoints.height
                }

                let points = LinearGradientFixer.fixPoints(
                    start: _startPoint,
                    end: _endPoint,
                    bounds: (axisBox ?? boundsToPoints).size)
                var fStartPoint: CGPoint = points.0
                var fEndPoint: CGPoint = points.1

                // The axis above is expressed against the geometry box; the layer covers the
                // (larger) stroked outline, so re-express it against the layer's own frame.
                if let box = axisBox {
                    (fStartPoint, fEndPoint) = Self.remap(start: fStartPoint, end: fEndPoint, from: box, to: boundsToPoints)
                }

                gradLayer.startPoint = fStartPoint
                gradLayer.endPoint = fEndPoint
            }

            gradLayer.colors = colors
            gradLayer.locations = locations.map { NSNumber(value: $0) }

            return newLayer
        }
        return nil
    }

    /// Re-expresses a gradient axis given in `from`-relative unit coordinates in the unit
    /// coordinates of `to`. `CAGradientLayer` projects in its own unit space, so the *direction*
    /// is mapped through the transpose of the scale, not as two points: the colour field stays
    /// the same linear function of the absolute position.
    static func remap(start: CGPoint, end: CGPoint, from: CGRect, to: CGRect) -> (CGPoint, CGPoint) {
        let sx = to.width / from.width, sy = to.height / from.height
        func toFrame(_ p: CGPoint) -> CGPoint {
            CGPoint(x: (from.minX + p.x * from.width - to.minX) / to.width,
                    y: (from.minY + p.y * from.height - to.minY) / to.height)
        }
        let newStart = toFrame(start)
        let d = CGPoint(x: end.x - start.x, y: end.y - start.y)
        let lenSq = d.x * d.x + d.y * d.y
        guard lenSq > 0 else { return (newStart, toFrame(end)) }
        // ∇t' = S·d / |d|², S = to-size / from-size; the layer interpolates (p − A)·(B − A) / |B − A|², so B − A = g / |g|².
        let g = CGPoint(x: sx * d.x / lenSq, y: sy * d.y / lenSq)
        let gSq = g.x * g.x + g.y * g.y
        guard gSq > 0 else { return (newStart, toFrame(end)) }
        return (newStart, CGPoint(x: newStart.x + g.x / gSq, y: newStart.y + g.y / gSq))
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
