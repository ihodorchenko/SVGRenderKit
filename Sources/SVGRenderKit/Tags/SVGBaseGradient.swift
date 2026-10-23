import UIKit

/// Base class for SVG gradients, holding shared attributes and color stops.
class SVGBaseGradient: SVGChildObject {
    /// The coordinate system of the gradient geometry (`gradientUnits`).
    enum GradientUnits: String {
        case userSpaceOnUse = "userSpaceOnUse"
        case objectBoundingBox = "objectBoundingBox"
    }

    /// How the gradient fills beyond its end points (`spreadMethod`).
    enum SVGSpreadMethod: String {
        case pad = "pad"
        case reflect = "reflect"
        case `repeat` = "repeat"
    }

    /// The colour stops, in document order.
    var stops: [SVGGradientStop] = []
    /// The `gradientUnits` attribute (default `objectBoundingBox`).
    var gradientUnits: GradientUnits = GradientUnits.objectBoundingBox
    /// The `spreadMethod` attribute (default `pad`).
    var spreadMethod: SVGSpreadMethod = SVGSpreadMethod.pad

    /// The parsed `gradientTransform`, or `nil` when absent.
    var transform: CATransform3D?

    /// Returns whether this gradient can be rendered. The base implementation returns false.
    func isEnable() -> Bool {
        return false
    }

    /// Creates a gradient by parsing shared attributes from the given XML element.
    required init(xmlElement: XMLElement, addDict: [String: String]? = nil, parent: SVGGroupProtocol) throws {
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

    /// The sorted, clamped colour stops of this gradient, ready for a gradient layer, with the
    /// `spreadMethod` adjustment applied (shared by the linear and radial gradients).
    func renderStops(currentColor: UIColor) -> (colors: [CGColor], locations: [CGFloat]) {
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
        // A single stop renders as a solid color; duplicate it so the gradient layer has a
        // valid two-stop gradient.
        if colors.count == 1 {
            colors.append(colors[0])
            locations.append(1)
        }
        return spreadAdjusted(colors: colors, locations: locations)
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

    /// A length in object-bounding-box units, where the gradient lives in the
    /// element's unit square: both a percentage and a plain number are a fraction
    /// of the box (the unit square's normalised diagonal is 1).
    func unitFraction(_ length: SVGLength) -> CGFloat {
        switch length {
        case .px(let value): return value
        case .percent(let value): return value
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

    /// Whether `xlink:href` inheritance has already been resolved.
    private var hrefResolved = false

    /// Resolves `xlink:href` inheritance lazily (SVG 1.1 §13.2.4). It runs at render time
    /// so a gradient may reference one defined later in the document (a forward reference)
    /// or one of the other gradient type, neither of which worked when this was resolved
    /// eagerly during parsing. Idempotent; a href cycle stops at the first repeat.
    ///
    /// Not synchronised, on purpose: it mutates the (cached, shared) tree, and every path that builds
    /// layers — `SVGView` loads and `SVGRenderer` — runs on the single serial `SVGWorkQueue.shared`,
    /// which also guards `SVGOptions.renderScale` and friends. Calling `SVGParser.getLayer` for one
    /// document from several threads yourself is outside that contract (B124 b).
    func resolveHref() {
        guard !hrefResolved, case .local(let key)? = href else { return }
        hrefResolved = true
        guard let source = parent.getGradient(byKey: key, fromParents: true) else { return }
        guard SVGInputLimits.enterHref() else {
            SVGLog.addSLog(errorStr: "skipped gradient href: the chain is longer than \(SVGInputLimits.maxHrefChainDepth)")
            return
        }
        defer { SVGInputLimits.exitHref() }
        source.resolveHref()
        if stops.isEmpty { stops = source.stops }
        if attributeDict["gradientTransform"] == nil, transform == nil { transform = source.transform }
        if attributeDict["gradientUnits"] == nil { gradientUnits = source.gradientUnits }
        if attributeDict["spreadMethod"] == nil { spreadMethod = source.spreadMethod }
        inherit(from: source)
    }

    /// Copies geometry attributes this gradient does not set itself from the referenced
    /// gradient. Overridden by the concrete gradient types.
    func inherit(from source: SVGBaseGradient) {}

    /// Returns the layer that renders this gradient, or nil if it cannot be built.
    func getGradientLayer(maskLayer: CALayer, path: UIBezierPath, viewBox: CGRect, currentColor: UIColor = .black) -> CALayer? {
        return nil
    }

    /// Like `getGradientLayer(maskLayer:path:viewBox:currentColor:)`, but `path` only supplies the
    /// area the gradient layer covers (the stroked outline for a stroke) while `boundingBox` is the
    /// box an `objectBoundingBox` gradient resolves against — the geometry without its stroke
    /// (SVG 1.1 §13.2, B135). The built-in gradients override this; a subclass that only overrides
    /// the public method keeps resolving against `path`.
    func getGradientLayer(maskLayer: CALayer, path: UIBezierPath, boundingBox: CGRect?, viewBox: CGRect, currentColor: UIColor) -> CALayer? {
        getGradientLayer(maskLayer: maskLayer, path: path, viewBox: viewBox, currentColor: currentColor)
    }
}

/// A CALayer that draws a radial gradient from its start point outward to its radius.
class RadialGradientLayer: CALayer {

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
    var locations: [CGFloat] = [0, 1]
    /// The center of the outer circle (the gradient's end center).
    var center: CGPoint = CGPoint(x: 0, y: 0)
    /// The focal point the gradient starts from; `nil` means it coincides with `center`.
    var focalPoint: CGPoint?
    /// The radius of the focal circle (`fr`, SVG 2). Zero means the gradient starts at a
    /// single point, which is what a document without `fr` asks for.
    var focalRadius: CGFloat = 0
    /// The distance over which the gradient is drawn.
    var radius: CGFloat = 1
    /// An optional affine transform applied to the whole gradient (used for elliptical gradients
    /// produced by a non-uniform `gradientTransform`).
    var gradientTransform: CGAffineTransform = .identity

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
        let startCenter = clampedFocal(focalPoint ?? center)
        ctx.drawRadialGradient(
            gradient,
            startCenter: startCenter,
            startRadius: focalRadius,
            endCenter: center,
            endRadius: radius,
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    /// The focal point moved onto the end circle when it lies outside it (SVG 1.1 §13.2.3 —
    /// browsers clamp the same way). The projection is pulled a hair inside the edge:
    /// exactly on the edge every interpolated circle passes through the focus, so the two
    /// circles no longer enclose an area and the whole plane is left untouched.
    ///
    /// A focal *radius* means the document is following SVG 2, which changed the rule and
    /// keeps the start circle where it is, painting a cone — which CoreGraphics draws
    /// natively — so the point is only clamped for a point-like focus.
    private func clampedFocal(_ focal: CGPoint) -> CGPoint {
        guard radius > 0, focalRadius <= 0 else { return focal }
        let dx = focal.x - center.x
        let dy = focal.y - center.y
        let distance = hypot(dx, dy)
        guard distance >= radius else { return focal }
        let clamped = radius * (1 - 0.0001) / distance
        return CGPoint(x: center.x + dx * clamped, y: center.y + dy * clamped)
    }
}

/// A single color stop within a gradient.
class SVGGradientStop: SVGObject {
    class override var key: String { get { return "stop" }}

    /// The stop position, `0...1` for well-formed documents.
    var offset: Float = 0
    /// The `stop-color` (without `stop-opacity`; see `resolvedColor(currentColor:)`).
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
    override init(xmlElement: XMLElement, addDict: [String: String]? = nil) throws {
        try super.init(xmlElement: xmlElement, addDict: addDict)

        // Presentation attributes first, then the inline `style`, which outranks them (B129).
        try set(attributeDict: attributeDict)
        if let str = attributeDict["style"] {
            try set(styleStr: str)
        }
    }

    func set(styleStr: String) throws {
        try set(attributeDict: SVGSourceStyleElement.declarations(from: styleStr))
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
            if let color = SVGColors.parse(string: str) { stop_color = color }
        }
        if let str = attributeDict["stop-opacity"], let f: Float = Float(str.trimmed) {
            stopOpacity = CGFloat(f)
        }
    }
}

extension Array where Element == SVGGradientStop {
    /// `true` when the stops are already in non-decreasing offset order.
    var isSortedByOffset: Bool {
        var previous = -CGFloat.greatestFiniteMagnitude
        for stop in self {
            let offset = CGFloat(stop.offset)
            if offset < previous { return false }
            previous = offset
        }
        return true
    }
}
