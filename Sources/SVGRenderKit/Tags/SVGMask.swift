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

    var maskUnits: MaskUnits = MaskUnits.objectBoundingBox
    var maskContentUnits: MaskUnits = MaskUnits.userSpaceOnUse
    var maskType: MaskType = MaskType.luminance

    /// The mask region, defaulting to -10%/-10%/120%/120% (object-bounding-box units).
    var x: SVGLength = SVGLength.percent(value: -0.1)
    var y: SVGLength = SVGLength.percent(value: -0.1)
    var width: SVGLength = SVGLength.percent(value: 1.2)
    var height: SVGLength = SVGLength.percent(value: 1.2)

    /// Initializes a mask by parsing its attributes and child elements.
    public required init(xmlElement: XMLElement, addDict: [String: String]? = nil, parent: SVGGroupProtocol) throws {
        try super.init(xmlElement: xmlElement, addDict: addDict, parent: parent)

        let tsStyle: SVGSourceStyleElement = SVGSourceStyleElement()
        if let str = attributeDict["style"] {
            try tsStyle.set(styleStr: str, force: false)
        }
        try tsStyle.set(attributeDict: attributeDict)
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

extension SVGMask: SVGRendering {
    /// Builds and returns a layer containing the mask's shapes and `<use>` references.
    public func createLayer(addStyle: SVGSourceStyleElement?, overrideElements: [String: SVGSourceStyleElement]?) throws -> CALayer {
        let mainLayer: CAShapeLayer = CAShapeLayer()

        for use in uses.array {
            let layer = try use.createLayer(overrideElements: overrideElements)
            mainLayer.addSublayer(layer)
        }

        for path in shapes.array {
            let layer = try path.createLayer(overrideElements: overrideElements)
            mainLayer.addSublayer(layer)
        }

        if let transform = transform {
            mainLayer.transform = transform
        }

        return mainLayer
    }

    /// Renders the mask into a region-sized bitmap and returns it as a layer ready
    /// to be assigned to an element's `mask`. Handles `maskUnits`, `maskContentUnits`
    /// and `mask-type` (luminance vs alpha), which `CALayer.mask` alone does not.
    public func maskLayer(bbox: CGRect, viewBox: CGRect, overrideElements: [String: SVGSourceStyleElement]?) throws -> CALayer {
        let contentLayer = try createLayer(addStyle: nil, overrideElements: overrideElements)
        let region = maskRegion(bbox: bbox, viewBox: viewBox)
        guard region.width > 0, region.height > 0 else { return contentLayer }
        guard let cgImage = renderMaskImage(contentLayer: contentLayer, region: region, bbox: bbox) else {
            return contentLayer
        }
        let layer = CALayer()
        layer.frame = region
        layer.contents = cgImage
        layer.contentsScale = 1
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

    private func renderMaskImage(contentLayer: CALayer, region: CGRect, bbox: CGRect) -> CGImage? {
        let width = Int(region.width.rounded(.up))
        let height = Int(region.height.rounded(.up))
        guard width > 0, height > 0 else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
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
        let bytesPerRow = width * 4
        var data = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: &data, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo) else { return nil }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        for i in stride(from: 0, to: data.count, by: 4) {
            let luminance = UInt8(max(0, min(255, 0.2126 * Double(data[i]) + 0.7152 * Double(data[i + 1]) + 0.0722 * Double(data[i + 2]))))
            data[i] = luminance
            data[i + 1] = luminance
            data[i + 2] = luminance
            data[i + 3] = luminance
        }
        guard let provider = CGDataProvider(data: Data(data) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
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

    public func getSvgOptions() -> SVGOptions {
        return parent.getSvgOptions()
    }
}
