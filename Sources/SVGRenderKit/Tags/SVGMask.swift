import UIKit

/// Defines a luminance/alpha mask that is applied to an element via its `mask` property.
open class SVGMask: SVGChildObject {
    /// The coordinate system used for the mask's position and size.
    public enum MaskUnits: String {
        case userSpaceOnUse = "userSpaceOnUse"
        case objectBoundingBox = "objectBoundingBox"
    }

    /// How the mask content is interpreted.
    public enum MaskType: String {
        case luminance = "luminance"
        case alpha = "alpha"
    }

    class override var key: String { get { return "mask" }}

    var sourceStyle: SVGSourceStyleElement?
    var transform: CATransform3D?

    private(set) var all: SVGTags<SVGObject> = SVGTags<SVGObject>()
    private(set) var uses: SVGTags<SVGUseTag> = SVGTags<SVGUseTag>()
    private(set) var shapes: SVGTags<SVGShapeObject> = SVGTags<SVGShapeObject>()
    private(set) var groups: SVGTags<SVGGTag> = SVGTags<SVGGTag>()
    private(set) var images: SVGTags<SVGImage> = SVGTags<SVGImage>()

    var maskUnits: MaskUnits = MaskUnits.objectBoundingBox
    var maskContentUnits: MaskUnits = MaskUnits.userSpaceOnUse
    var maskType: MaskType = MaskType.luminance

    /// What changes the rendered mask bitmap: its region, the element bounding box (only when the content
    /// is scaled to it) and the output scale (nested patterns rasterize at it).
    private struct MaskKey: Hashable {
        let region: [CGFloat]
        let bbox: [CGFloat]
        let scale: CGFloat
    }

    /// The bitmap is identical for every element that shares the mask, so it is rendered once per key.
    private let maskImageCache = SVGBoundedCache<MaskKey, CGImage>(limit: 16)

    /// The mask region, defaulting to -10%/-10%/120%/120% (object-bounding-box units).
    var x: SVGLength = SVGLength.percent(value: -0.1)
    var y: SVGLength = SVGLength.percent(value: -0.1)
    var width: SVGLength = SVGLength.percent(value: 1.2)
    var height: SVGLength = SVGLength.percent(value: 1.2)

    /// Initializes a mask by parsing its attributes and child elements.
    public required init(xmlElement: XMLElement, addDict: [String: String]? = nil, parent: SVGGroupProtocol) throws {
        try super.init(xmlElement: xmlElement, addDict: addDict, parent: parent)

        let tsStyle: SVGSourceStyleElement = SVGSourceStyleElement()
        try tsStyle.set(attributesAndInlineStyle: attributeDict)
        sourceStyle = tsStyle

        if let str = attributeDict["maskUnits"], let f = MaskUnits(rawValue: str) { maskUnits = f }
        if let str = attributeDict["maskContentUnits"], let f = MaskUnits(rawValue: str) { maskContentUnits = f }
        if let str = attributeDict["mask-type"], let f = MaskType(rawValue: str) { maskType = f }
        if let str = attributeDict["x"] { x = try SVGLength.get(string: str) }
        if let str = attributeDict["y"] { y = try SVGLength.get(string: str) }
        if let str = attributeDict["width"] { width = try SVGLength.get(string: str) }
        if let str = attributeDict["height"] { height = try SVGLength.get(string: str) }

        if let str = attributeDict["transform"] {
            transform = try SVGTransform.get(string: str)
        }

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

extension SVGMask {
    /// Adds `<use>` references to the mask.
    public func add(uses: [SVGUseTag]) throws {
        for use in uses {
            use.parent = self
            self.uses.add(item: use)
            self.all.add(item: use)
        }
    }

    /// Adds shapes to the mask.
    public func add(shapes: [SVGShapeObject]) throws {
        for shape in shapes {
            shape.parent = self
            self.shapes.add(item: shape)
            self.all.add(item: shape)
        }
    }
}

extension SVGMask: SVGGroupHosting {}

extension SVGMask: SVGRendering {
    /// Builds and returns a layer containing the mask's children.
    public func createLayer(addStyle: SVGSourceStyleElement?, overrideElements: [String: SVGSourceStyleElement]?) throws -> CALayer {
        let mainLayer: CAShapeLayer = CAShapeLayer()

        // Children paint in document order: the mask content composites like a group, so a
        // later child covers an earlier one whatever their types are (B119-5b).
        for element in all.array {
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

        if let transform = transform {
            mainLayer.transform = transform
        }

        return mainLayer
    }

    /// Renders the mask into a region-sized bitmap and returns it as a layer ready
    /// to be assigned to an element's `mask`. Handles `maskUnits`, `maskContentUnits`
    /// and `mask-type` (luminance vs alpha), which `CALayer.mask` alone does not.
    /// - parameter elementScale: the accumulated scale of the element's own and its
    ///   ancestors' transforms, which stretch the bitmap on screen (B119-6).
    public func maskLayer(bbox: CGRect, viewBox: CGRect, overrideElements: [String: SVGSourceStyleElement]?, elementScale: CGFloat = 1) throws -> CALayer {
        let region = maskRegion(bbox: bbox, viewBox: viewBox)

        // Rasterize at the output scale (`renderScale`), like patterns: the region-sized
        // bitmap is stretched by the view transform, so at 1 px per unit it blurs by that
        // same factor (B92) — and by the element's own transform chain on top of it (B119-6).
        let scale = max(1, getSvgOptions().renderScale * elementScale)
        getSvgOptions().usesMasks = true

        // A cached bitmap skips building the content layer tree as well. Per-element style overrides change
        // the content, so they bypass the cache.
        let cacheKey: MaskKey?
        if overrideElements == nil, region.width > 0, region.height > 0 {
            let usesBBox = maskContentUnits == .objectBoundingBox
            cacheKey = MaskKey(
                region: [region.origin.x, region.origin.y, region.width, region.height],
                bbox: usesBBox ? [bbox.origin.x, bbox.origin.y, bbox.width, bbox.height] : [],
                scale: scale)
            if let key = cacheKey, let cached = maskImageCache.value(for: key) {
                return Self.makeMaskLayer(image: cached, region: region, scale: scale)
            }
        } else {
            cacheKey = nil
        }

        let contentLayer = try createLayer(addStyle: nil, overrideElements: overrideElements)
        guard region.width > 0, region.height > 0 else { return contentLayer }
        guard let cgImage = renderMaskImage(contentLayer: contentLayer, region: region, bbox: bbox, scale: scale) else {
            return contentLayer
        }
        if let key = cacheKey { maskImageCache.set(cgImage, for: key) }
        return Self.makeMaskLayer(image: cgImage, region: region, scale: scale)
    }

    /// A layer is single-parent, so every use gets its own layer around the shared bitmap.
    private static func makeMaskLayer(image: CGImage, region: CGRect, scale: CGFloat) -> CALayer {
        let layer = CALayer()
        layer.frame = region
        layer.contents = image
        layer.contentsScale = scale
        layer.contentsGravity = .resize
        return layer
    }

    private func resolveRegionLength(_ length: SVGLength, bboxDimension: CGFloat, viewBoxDimension: CGFloat) -> CGFloat {
        switch maskUnits {
        case .objectBoundingBox:
            switch length {
            case .px(let value): return value * bboxDimension
            case .percent(let value): return value * bboxDimension
            }
        case .userSpaceOnUse:
            switch length {
            case .px(let value): return value
            case .percent(let value): return value * viewBoxDimension
            }
        }
    }

    private func maskRegion(bbox: CGRect, viewBox: CGRect) -> CGRect {
        let rx = resolveRegionLength(x, bboxDimension: bbox.width, viewBoxDimension: viewBox.width)
        let ry = resolveRegionLength(y, bboxDimension: bbox.height, viewBoxDimension: viewBox.height)
        let rw = resolveRegionLength(width, bboxDimension: bbox.width, viewBoxDimension: viewBox.width)
        let rh = resolveRegionLength(height, bboxDimension: bbox.height, viewBoxDimension: viewBox.height)
        switch maskUnits {
        case .objectBoundingBox:
            return CGRect(x: bbox.origin.x + rx, y: bbox.origin.y + ry, width: rw, height: rh)
        case .userSpaceOnUse:
            return CGRect(x: rx, y: ry, width: rw, height: rh)
        }
    }

    private func renderMaskImage(contentLayer: CALayer, region: CGRect, bbox: CGRect, scale: CGFloat) -> CGImage? {
        let width = Int(region.width.rounded(.up))
        let height = Int(region.height.rounded(.up))
        guard width > 0, height > 0 else { return nil }
        // A document-controlled region must not allocate an unbounded bitmap (B102);
        // skip the mask (the content then renders unmasked) past the cap.
        guard SVGInputLimits.bitmapFits(width: CGFloat(width) * scale, height: CGFloat(height) * scale,
                                        limit: SVGInputLimits.maxPaintBitmapDimension) else {
            SVGLog.addSLog(errorStr: "skipped mask: \(width)×\(height)px region exceeds the \(Int(SVGInputLimits.maxPaintBitmapDimension))px limit")
            return nil
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        let image = renderer.image { renderContext in
            let cg = renderContext.cgContext
            if maskContentUnits == .objectBoundingBox {
                cg.translateBy(x: bbox.origin.x - region.origin.x, y: bbox.origin.y - region.origin.y)
                cg.scaleBy(x: bbox.width, y: bbox.height)
            } else {
                cg.translateBy(x: -region.origin.x, y: -region.origin.y)
            }
            contentLayer.render(in: cg)
        }

        guard maskType == .luminance else { return image.cgImage }
        return luminanceAlphaImage(image)
    }

    private func luminanceAlphaImage(_ image: UIImage) -> CGImage? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        // Let CoreGraphics own the buffer: it is converted in place and turned into the image with no copy.
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: colorSpace, bitmapInfo: bitmapInfo),
              let base = context.data else { return nil }
        let bytesPerRow = context.bytesPerRow
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        for row in 0..<height {
            var p = pixels + row * bytesPerRow
            for _ in 0..<width {
                // Rec. 709 luma in 16-bit fixed point (0.2126 / 0.7152 / 0.0722); the weights sum to 65536.
                let luma = (13933 * UInt32(p[0]) + 46871 * UInt32(p[1]) + 4732 * UInt32(p[2])) >> 16
                let luminance = UInt8(truncatingIfNeeded: luma)
                p[0] = luminance
                p[1] = luminance
                p[2] = luminance
                p[3] = luminance
                p += 4
            }
        }
        return context.makeImage()
    }
}

extension SVGMask: SVGShapesContainer {
    public func getClipPath(byKey: String, fromParents: Bool) -> SVGClipPath? {
        return nil
    }

    public func getMask(byKey: String, fromParents: Bool) -> SVGMask? {
        return nil
    }

    public func getPattern(byKey: String, fromParents: Bool) -> SVGPattern? {
        return nil
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
