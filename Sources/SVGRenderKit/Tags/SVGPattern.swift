import UIKit

/// A `<pattern>` paint server: a tiled fill defined by a rectangle and its content.
open class SVGPattern: SVGChildObject {
    /// The coordinate system used for the pattern tile's `x`/`y`/`width`/`height`.
    public enum PatternUnits: String {
        case userSpaceOnUse = "userSpaceOnUse"
        case objectBoundingBox = "objectBoundingBox"
    }

    class override var key: String { get { return "pattern" }}

    var sourceStyle: SVGSourceStyleElement?
    var transform: CATransform3D?

    private(set) var all: SVGTags<SVGObject> = SVGTags<SVGObject>()
    private(set) var uses: SVGTags<SVGUseTag> = SVGTags<SVGUseTag>()
    private(set) var shapes: SVGTags<SVGShapeObject> = SVGTags<SVGShapeObject>()
    private(set) var groups: SVGTags<SVGGTag> = SVGTags<SVGGTag>()
    private(set) var images: SVGTags<SVGImage> = SVGTags<SVGImage>()

    var patternUnits: PatternUnits = PatternUnits.objectBoundingBox
    var patternContentUnits: PatternUnits = PatternUnits.userSpaceOnUse
    var x: SVGLength = SVGLength.px(value: 0)
    var y: SVGLength = SVGLength.px(value: 0)
    var width: SVGLength = SVGLength.px(value: 0)
    var height: SVGLength = SVGLength.px(value: 0)
    /// When present, the content's `viewBox` is fitted into the tile and
    /// `patternContentUnits` is ignored (SVG 1.1 §13.3).
    var viewBox: CGRect?
    var preserveAspectRatio = SVGPreserveAspectRatio()

    /// Whether `xlink:href` inheritance has already been resolved.
    private var hrefResolved = false
    /// The pattern whose children this one inherits when it has none of its own.
    private var inheritedContent: SVGPattern?

    /// Everything that changes the rendered tile: the tile region, the element bounding box (only when
    /// the content is scaled to it) and the output scale.
    private struct TileKey: Hashable {
        let region: [CGFloat]
        let bbox: [CGFloat]
        let scale: CGFloat
        let opacity: CGFloat
    }

    /// Tiles are identical for every shape that shares the same region and scale, so a hatch fill used by
    /// hundreds of shapes is rasterized once instead of once per shape.
    private let tileCache = SVGBoundedCache<TileKey, UIImage>(limit: 16)

    /// Initializes a pattern by parsing its geometry attributes and child elements.
    public required init(xmlElement: XMLElement, addDict: [String: String]? = nil, parent: SVGGroupProtocol) throws {
        try super.init(xmlElement: xmlElement, addDict: addDict, parent: parent)

        let tsStyle: SVGSourceStyleElement = SVGSourceStyleElement()
        try tsStyle.set(attributesAndInlineStyle: attributeDict)
        sourceStyle = tsStyle

        if let str = attributeDict["patternUnits"], let f = PatternUnits(rawValue: str) { patternUnits = f }
        if let str = attributeDict["patternContentUnits"], let f = PatternUnits(rawValue: str) { patternContentUnits = f }
        if let str = attributeDict["x"] { x = try SVGLength.get(string: str) }
        if let str = attributeDict["y"] { y = try SVGLength.get(string: str) }
        if let str = attributeDict["width"] { width = try SVGLength.get(string: str) }
        if let str = attributeDict["height"] { height = try SVGLength.get(string: str) }
        if let str = attributeDict["patternTransform"] {
            transform = try SVGTransform.get(string: str)
        }
        if let str = attributeDict["viewBox"] {
            let numbers = str.trimmed
                .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",")))
                .filter { !$0.isEmpty }
                .compactMap { Double($0) }
            if numbers.count == 4 {
                viewBox = CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
            }
        }
        preserveAspectRatio = SVGPreserveAspectRatio.get(string: attributeDict["preserveAspectRatio"])

        for children in xmlElement.xmlChildren {
            try parse(children: children)
        }
    }

    internal func parse(children: XMLElement) throws {
        switch children.name {
        case SVGUseTag.key:
            let use: SVGUseTag = try SVGUseTag(xmlElement: children, parent: self)
            try self.add(uses: [use])
        case SVGGTag.key:
            let group: SVGGTag = try SVGGTag(xmlElement: children, parent: self)
            self.groups.add(item: group)
            self.all.add(item: group)
        case SVGImage.key:
            let image: SVGImage = try SVGImage(xmlElement: children, parent: self)
            self.images.add(item: image)
            self.all.add(item: image)
        default:
            if let shapeTag = try SVGShapeObject.create(xml: children, parent: self) {
                try self.add(shapes: [shapeTag])
            }
        }
    }
}

// MARK: - xlink:href inheritance

extension SVGPattern {
    private var hasOwnContent: Bool {
        !shapes.array.isEmpty || !groups.array.isEmpty || !uses.array.isEmpty || !images.array.isEmpty
    }

    /// Resolves `xlink:href` inheritance (SVG 1.1 §13.3): missing attributes and, when
    /// this pattern has no children of its own, the referenced pattern's children.
    /// Lazy so a forward reference works; idempotent.
    func resolveHref() {
        guard !hrefResolved, case .local(let key)? = href else { return }
        hrefResolved = true
        guard let source = parent.getPattern(byKey: key, fromParents: true), source !== self else { return }
        source.resolveHref()

        if attributeDict["x"] == nil { x = source.x }
        if attributeDict["y"] == nil { y = source.y }
        if attributeDict["width"] == nil { width = source.width }
        if attributeDict["height"] == nil { height = source.height }
        if attributeDict["patternUnits"] == nil { patternUnits = source.patternUnits }
        if attributeDict["patternContentUnits"] == nil { patternContentUnits = source.patternContentUnits }
        if attributeDict["patternTransform"] == nil { transform = source.transform }
        if attributeDict["viewBox"] == nil { viewBox = source.viewBox }
        if attributeDict["preserveAspectRatio"] == nil { preserveAspectRatio = source.preserveAspectRatio }

        if !hasOwnContent {
            inheritedContent = source.hasOwnContent ? source : source.inheritedContent
        }
    }

    /// The shapes/groups/uses/images to render, honoring inherited content.
    private var contentSource: SVGPattern { inheritedContent ?? self }
}

// MARK: - Tiling

extension SVGPattern {
    /// A `CGPattern` fill whose grid carries the tile phase (`x`/`y`) and
    /// `patternTransform`; the tile image only holds the content. `nil` for an empty tile.
    func fillColor(bbox: CGRect, viewBox viewBoxRect: CGRect, opacity: CGFloat?) -> CGColor? {
        resolveHref()
        guard let image = tileImage(bbox: bbox, viewBox: viewBoxRect, opacity: opacity) else { return nil }
        guard let pattern = makePattern(image: image, bbox: bbox, viewBox: viewBoxRect) else { return nil }
        guard let space = CGColorSpace(patternBaseSpace: nil) else { return nil }
        // A coloured pattern carries the fill-opacity baked into its tile (the pattern's
        // colour components are not a tint), so the components stay neutral.
        var components: [CGFloat] = [1, 1, 1, 1]
        return CGColor(patternSpace: space, pattern: pattern, components: &components)
    }

    /// A length in the tile's own coordinate system (`objectBoundingBox` values are
    /// fractions of the box, `userSpaceOnUse` percentages are relative to the viewport).
    private func tileValue(_ length: SVGLength, viewBoxDimension: CGFloat) -> CGFloat {
        switch patternUnits {
        case .objectBoundingBox:
            switch length {
            case .px(let value): return value
            case .percent(let value): return value
            }
        case .userSpaceOnUse:
            switch length {
            case .px(let value): return value
            case .percent(let value): return value * viewBoxDimension
            }
        }
    }

    private func tileSize(bbox: CGRect, viewBox viewBoxRect: CGRect) -> CGSize {
        let w = tileValue(width, viewBoxDimension: viewBoxRect.width)
        let h = tileValue(height, viewBoxDimension: viewBoxRect.height)
        switch patternUnits {
        case .objectBoundingBox: return CGSize(width: w * bbox.width, height: h * bbox.height)
        case .userSpaceOnUse: return CGSize(width: w, height: h)
        }
    }

    /// The tile's top-left in user space (the phase anchor, before `patternTransform`).
    private func tileOrigin(bbox: CGRect, viewBox viewBoxRect: CGRect) -> CGPoint {
        let px = tileValue(x, viewBoxDimension: viewBoxRect.width)
        let py = tileValue(y, viewBoxDimension: viewBoxRect.height)
        switch patternUnits {
        case .objectBoundingBox: return CGPoint(x: bbox.origin.x + px * bbox.width, y: bbox.origin.y + py * bbox.height)
        case .userSpaceOnUse: return CGPoint(x: px, y: py)
        }
    }

    /// `patternTransform` re-expressed in user space (it acts in bounding-box units for
    /// `objectBoundingBox`), applied to the grid together with the tile phase.
    private func gridTransform(bbox: CGRect) -> CGAffineTransform {
        guard let transform = transform else { return .identity }
        let m = CATransform3DGetAffineTransform(transform)
        switch patternUnits {
        case .userSpaceOnUse:
            return m
        case .objectBoundingBox:
            guard bbox.width > 0, bbox.height > 0 else { return m }
            let toUser = CGAffineTransform(scaleX: bbox.width, y: bbox.height)
            let fromUser = CGAffineTransform(scaleX: 1 / bbox.width, y: 1 / bbox.height)
            return fromUser.concatenating(m).concatenating(toUser)
        }
    }

    private func makePattern(image: UIImage, bbox: CGRect, viewBox viewBoxRect: CGRect) -> CGPattern? {
        let size = tileSize(bbox: bbox, viewBox: viewBoxRect)
        guard size.width > 0, size.height > 0 else { return nil }
        let origin = tileOrigin(bbox: bbox, viewBox: viewBoxRect)
        let matrix = CGAffineTransform(translationX: origin.x, y: origin.y)
            .concatenating(gridTransform(bbox: bbox))

        let info = Unmanaged.passRetained(image).toOpaque()
        var callbacks = CGPatternCallbacks(version: 0,
                                           drawPattern: SVGPattern.drawTile,
                                           releaseInfo: SVGPattern.releaseTile)
        return CGPattern(info: info,
                         bounds: CGRect(origin: .zero, size: size),
                         matrix: matrix, xStep: size.width, yStep: size.height,
                         tiling: .constantSpacing, isColored: true, callbacks: &callbacks)
    }

    /// `CGPatternCreate` takes a C function pointer, so the tile image travels via `info`.
    private static let drawTile: CGPatternDrawPatternCallback = { info, ctx in
        guard let info = info else { return }
        let image = Unmanaged<UIImage>.fromOpaque(info).takeUnretainedValue()
        guard let cgImage = image.cgImage else { return }
        // The tile was rasterized y-down (UIKit) but a pattern context is y-up, so flip
        // it back to keep the content the right way up.
        ctx.saveGState()
        ctx.translateBy(x: 0, y: image.size.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(cgImage, in: CGRect(origin: .zero, size: image.size))
        ctx.restoreGState()
    }

    private static let releaseTile: CGPatternReleaseInfoCallback = { info in
        guard let info = info else { return }
        Unmanaged<UIImage>.fromOpaque(info).release()
    }

    /// Renders the pattern content into a tile image, or `nil` if the tile has no size.
    /// `viewBox` (if present) fits the content into the tile; otherwise
    /// `patternContentUnits` maps it.
    func tileImage(bbox: CGRect, viewBox viewBoxRect: CGRect, opacity: CGFloat?) -> UIImage? {
        resolveHref()
        let identity = ObjectIdentifier(self)
        guard SVGInputLimits.enterPattern(identity) else {
            SVGLog.addSLog(errorStr: "skipped pattern: it references itself")
            return nil
        }
        defer { SVGInputLimits.exitPattern(identity) }
        let size = tileSize(bbox: bbox, viewBox: viewBoxRect)
        guard size.width > 0, size.height > 0 else { return nil }
        let origin = tileOrigin(bbox: bbox, viewBox: viewBoxRect)
        let fillOpacity = min(max(opacity ?? 1, 0), 1)

        let options = getSvgOptions()
        options.usesPatterns = true
        let scale = max(1, options.renderScale)
        // A document-controlled tile must not allocate an unbounded bitmap (B102);
        // skip the pattern (the shape keeps its previous fill) past the cap.
        guard SVGInputLimits.bitmapFits(width: size.width * scale, height: size.height * scale,
                                        limit: SVGInputLimits.maxPaintBitmapDimension) else {
            SVGLog.addSLog(errorStr: "skipped pattern: \(Int(size.width))×\(Int(size.height))px tile exceeds the \(Int(SVGInputLimits.maxPaintBitmapDimension))px limit")
            return nil
        }
        let usesBBox = patternContentUnits == .objectBoundingBox && viewBox == nil
        let key = TileKey(
            region: [origin.x, origin.y, size.width, size.height],
            bbox: (usesBBox || patternUnits == .objectBoundingBox) ? [bbox.origin.x, bbox.origin.y, bbox.width, bbox.height] : [],
            scale: scale,
            opacity: fillOpacity)
        return tileCache.value(for: key) {
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = scale
            format.opaque = false
            let renderer = UIGraphicsImageRenderer(size: size, format: format)
            return renderer.image { context in
                if let layer = try? contentSource.createLayer(overrideElements: nil) {
                    layer.opacity = Float(fillOpacity)
                    let cg = context.cgContext
                    if let viewBox = viewBox, viewBox.width > 0, viewBox.height > 0 {
                        // A `viewBox` fits the content into the tile's own box, whose size
                        // in tile units is then scaled up to the image (user) size.
                        let wP = tileValue(self.width, viewBoxDimension: viewBoxRect.width)
                        let hP = tileValue(self.height, viewBoxDimension: viewBoxRect.height)
                        let unitX = wP != 0 ? size.width / wP : 1
                        let unitY = hP != 0 ? size.height / hP : 1
                        let fit = preserveAspectRatio.resolve(viewBox: viewBox, containerSize: CGSize(width: wP, height: hP))
                        cg.scaleBy(x: unitX, y: unitY)
                        cg.translateBy(x: fit.translateX, y: fit.translateY)
                        cg.scaleBy(x: fit.scaleX, y: fit.scaleY)
                        cg.translateBy(x: -viewBox.origin.x, y: -viewBox.origin.y)
                    } else if usesBBox {
                        cg.translateBy(x: bbox.origin.x - origin.x, y: bbox.origin.y - origin.y)
                        cg.scaleBy(x: bbox.width, y: bbox.height)
                    }
                    // `userSpaceOnUse` content: its coordinate system already has its
                    // origin at the tile's (x, y), so no extra transform is needed.
                    layer.render(in: cg)
                }
            }
        }
    }
}

extension SVGPattern {
    /// Adds `<use>` references to the pattern.
    public func add(uses: [SVGUseTag]) throws {
        for use in uses {
            use.parent = self
            self.uses.add(item: use)
            self.all.add(item: use)
        }
    }

    /// Adds shapes to the pattern.
    public func add(shapes: [SVGShapeObject]) throws {
        for shape in shapes {
            shape.parent = self
            self.shapes.add(item: shape)
            self.all.add(item: shape)
        }
    }
}

extension SVGPattern: SVGGroupHosting {}

extension SVGPattern: SVGRendering {
    /// Builds a layer containing the pattern's children.
    public func createLayer(addStyle: SVGSourceStyleElement?, overrideElements: [String: SVGSourceStyleElement]?) throws -> CALayer {
        let mainLayer: CAShapeLayer = CAShapeLayer()
        let source = contentSource

        // Children paint in document order, so a later child covers an earlier one whatever
        // their types are (B119-5b).
        for element in source.all.array {
            if let group = element as? SVGGTag {
                let layer = try group.createLayer(addStyle: addStyle, overrideElements: overrideElements)
                mainLayer.addSublayer(layer)
            } else if let use = element as? SVGUseTag {
                let layer = try use.createLayer(addStyle: addStyle, overrideElements: overrideElements)
                mainLayer.addSublayer(layer)
            } else if let path = element as? SVGShapeObject {
                let layer = try path.createLayer(addStyle: addStyle, overrideElements: overrideElements)
                mainLayer.addSublayer(layer)
            } else if let image = element as? SVGImage {
                let layer = try image.createLayer(addStyle: addStyle, overrideElements: overrideElements)
                mainLayer.addSublayer(layer)
            }
        }

        return mainLayer
    }
}

extension SVGPattern: SVGShapesContainer {
    public func getClipPath(byKey: String, fromParents: Bool) -> SVGClipPath? {
        return nil
    }

    public func getMask(byKey: String, fromParents: Bool) -> SVGMask? {
        return nil
    }

    public func getPattern(byKey: String, fromParents: Bool) -> SVGPattern? {
        return parent.getPattern(byKey: byKey, fromParents: true)
    }

    public func getMarker(byKey: String, fromParents: Bool) -> SVGMarker? {
        return nil
    }

    public func getFilter(byKey: String, fromParents: Bool) -> SVGFilter? {
        return nil
    }

    public func getRendering(byKey: String, fromParents: Bool) -> SVGRendering? {
        return parent.getRendering(byKey: byKey, fromParents: true)
    }

    public func getGradient(byKey: String, fromParents: Bool) -> SVGBaseGradient? {
        return parent.getGradient(byKey: byKey, fromParents: true)
    }

    public func getStyle(forObject: SVGShapeObject, overrideElements: [String: SVGSourceStyleElement]?) -> SVGSourceStyleElement {
        var style: SVGSourceStyleElement = parent.getStyle(forObject: forObject, overrideElements: overrideElements)
        if let selfStyle = self.sourceStyle {
            style = style.combine(child: selfStyle)
        }
        return style
    }

    public func selectorStyle(forObject: SVGShapeObject) -> SVGSourceStyleElement {
        return parent.selectorStyle(forObject: forObject)
    }

    public func getSvgOptions() -> SVGOptions {
        return parent.getSvgOptions()
    }
}
