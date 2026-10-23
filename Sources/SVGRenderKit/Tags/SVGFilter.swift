import UIKit
import CoreImage

/// A drop-shadow filter primitive (`feDropShadow`).
struct SVGDropShadow {
    var dx: CGFloat = 0
    var dy: CGFloat = 0
    var stdDeviation: CGFloat = 0
    var color: UIColor = .black
    var opacity: CGFloat = 1
}

/// A `<filter>` element containing a small subset of filter primitives.
class SVGFilter: SVGChildObject {
    class override var key: String { get { return "filter" }}

    /// The `feGaussianBlur` standard deviation, if the filter contains one.
    var blurStdDeviation: CGFloat?
    /// The `feDropShadow` effect, if the filter contains one.
    var dropShadow: SVGDropShadow?
    /// A blur that applies to the element itself *in addition to* `dropShadow`
    /// (`feGaussianBlur` + `feDropShadow` in one filter).
    var layerBlur: CGFloat?

    /// Initializes a filter by parsing its `feGaussianBlur`, `feDropShadow`, and the
    /// SVG 1.1 drop-shadow primitive chain (`feOffset` + `feFlood`) as well as the
    /// Figma/Sketch drop-shadow chain (`feColorMatrix` color tint).
    required init(xmlElement: XMLElement, addDict: [String: String]? = nil, parent: SVGGroupProtocol) throws {
        try super.init(xmlElement: xmlElement, addDict: addDict, parent: parent)

        var offsetDX: CGFloat = 0
        var offsetDY: CGFloat = 0
        var floodColor: UIColor = .black
        var floodOpacity: CGFloat = 1
        var hasOffsetOrFlood = false
        var hasOffset = false
        // A shadow color/opacity produced by an feColorMatrix tint (Figma exports
        // drop-shadows as an alpha extraction matrix followed by a constant-color
        // matrix; the latter carries the shadow's RGB and opacity).
        var tintColor: UIColor?
        var tintOpacity: CGFloat = 1
        var separateBlur: CGFloat?
        var hasExplicitDropShadow = false

        for child in xmlElement.xmlChildren {
            switch child.name {
            case "feGaussianBlur":
                if let str = child.attribute(by: "stdDeviation")?.text, let f = SVGFilter.parseStdDeviation(str) {
                    blurStdDeviation = f
                    separateBlur = f
                }
            case "feDropShadow":
                var shadow = SVGDropShadow()
                if let str = child.attribute(by: "dx")?.text, let f = Float(str.trimmed) { shadow.dx = CGFloat(f) }
                if let str = child.attribute(by: "dy")?.text, let f = Float(str.trimmed) { shadow.dy = CGFloat(f) }
                if let str = child.attribute(by: "stdDeviation")?.text, let f = SVGFilter.parseStdDeviation(str) { shadow.stdDeviation = f }
                hasExplicitDropShadow = true
                if let str = child.attribute(by: "flood-color")?.text { shadow.color = SVGColors.getColor(string: str) }
                if let str = child.attribute(by: "flood-opacity")?.text, let f = Float(str.trimmed) { shadow.opacity = CGFloat(f) }
                dropShadow = shadow
            case "feOffset":
                hasOffsetOrFlood = true
                hasOffset = true
                if let str = child.attribute(by: "dx")?.text, let f = Float(str.trimmed) { offsetDX = CGFloat(f) }
                if let str = child.attribute(by: "dy")?.text, let f = Float(str.trimmed) { offsetDY = CGFloat(f) }
            case "feFlood":
                hasOffsetOrFlood = true
                if let str = child.attribute(by: "flood-color")?.text { floodColor = SVGColors.getColor(string: str) }
                if let str = child.attribute(by: "flood-opacity")?.text, let f = Float(str.trimmed) { floodOpacity = CGFloat(f) }
            case "feColorMatrix":
                if let type = child.attribute(by: "type")?.text, type.trimmed == "matrix",
                   let values = child.attribute(by: "values")?.text,
                   let matrix = SVGFilter.parseColorMatrix(values) {
                    // A shadow tint matrix maps its input to a constant RGB color:
                    // R' = v4, G' = v9, B' = v14, A' = v18 · A. It is distinguishable
                    // from the alpha-extraction matrix (whose RGB constants are zero).
                    let r = CGFloat(matrix[4])
                    let g = CGFloat(matrix[9])
                    let b = CGFloat(matrix[14])
                    let a = CGFloat(matrix[18])
                    if r != 0 || g != 0 || b != 0 {
                        tintColor = UIColor(red: r, green: g, blue: b, alpha: 1)
                        tintOpacity = a
                    }
                }
            default:
                break
            }
        }

        // An explicit `feDropShadow` next to a standalone `feGaussianBlur` blurs the element too.
        if hasExplicitDropShadow, let blur = separateBlur { layerBlur = blur }

        // Figma/Sketch drop-shadow: an feOffset + feGaussianBlur + feColorMatrix
        // color tint. The tint overrides the (transparent) feFlood background fix.
        if dropShadow == nil, hasOffset, let tintColor = tintColor {
            var shadow = SVGDropShadow()
            shadow.dx = offsetDX
            shadow.dy = offsetDY
            shadow.stdDeviation = blurStdDeviation ?? 0
            shadow.color = tintColor
            shadow.opacity = tintOpacity
            dropShadow = shadow
        }

        // SVG 1.1 expresses a drop-shadow as an feOffset + feFlood [+ feGaussianBlur]
        // primitive chain. Fold it into the same shadow spec used by feDropShadow.
        if dropShadow == nil, hasOffsetOrFlood {
            var shadow = SVGDropShadow()
            shadow.dx = offsetDX
            shadow.dy = offsetDY
            shadow.stdDeviation = blurStdDeviation ?? 0
            shadow.color = floodColor
            shadow.opacity = floodOpacity
            dropShadow = shadow
        }
    }

    /// Parses `stdDeviation`, which is one number or an `x y` pair. `CIGaussianBlur` and `CALayer`
    /// shadows are isotropic, so a pair is approximated by its mean.
    static func parseStdDeviation(_ raw: String) -> CGFloat? {
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ","))
        let numbers = raw.components(separatedBy: separators).filter { !$0.isEmpty }.compactMap { Double($0) }
        guard !numbers.isEmpty, numbers.count <= 2, numbers.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
        return CGFloat(numbers.reduce(0, +) / Double(numbers.count))
    }

    /// Parses a 4×5 `feColorMatrix` `values` list (20 numbers) into an array.
    private static func parseColorMatrix(_ raw: String) -> [Float]? {
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ","))
        let tokens = raw.components(separatedBy: separators).filter { !$0.isEmpty }
        guard tokens.count >= 20 else { return nil }
        var values: [Float] = []
        values.reserveCapacity(20)
        for token in tokens.prefix(20) {
            guard let f = Float(token) else { return nil }
            values.append(f)
        }
        return values
    }
}

extension SVGFilter {
    /// Whether applying the filter bakes a bitmap whose resolution depends on the render scale.
    var bakesBitmap: Bool { blurStdDeviation != nil || layerBlur != nil }

    /// Applies the parsed filter effects to the given layer.
    /// - Parameters:
    ///   - layer: the layer whose content is filtered.
    ///   - bbox: the element's bounds in the layer's local space (the filter-region base).
    ///   - scale: pixels per user unit, so the blur is rasterized at the output resolution.
    func apply(to layer: CALayer, bbox: CGRect, scale: CGFloat) {
        if let shadow = dropShadow {
            // Bake the separate blur first: rasterizing a layer draws its shadow too, which
            // would then show twice — baked into the bitmap and again by the layer (B130).
            if let blur = layerBlur { bakeBlur(into: layer, bbox: bbox, stdDeviation: blur, scale: scale) }
            layer.shadowColor = shadow.color.cgColor
            layer.shadowOpacity = Float(shadow.opacity)
            // `CALayer.shadowRadius` is the CoreGraphics blur radius, which is about
            // twice the Gaussian sigma — so a `stdDeviation` of `s` needs a radius of
            // `2s`, otherwise the shadow is twice as sharp as the SVG asks for (B110).
            layer.shadowRadius = shadow.stdDeviation * 2
            layer.shadowOffset = CGSize(width: shadow.dx, height: shadow.dy)
            return
        }
        if let blur = blurStdDeviation {
            bakeBlur(into: layer, bbox: bbox, stdDeviation: blur, scale: scale)
        }
    }

    /// `CIGaussianBlur`, shared because building a `CIContext` per call is expensive.
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// SVG's initial filter region is `-10% -10% 120% 120%` of the bounding box: the blur
    /// spills outside the shape, so rasterize (and keep) that padded region.
    private static let filterRegion = CGRect(x: -0.1, y: -0.1, width: 1.2, height: 1.2)

    /// Rasterizes the layer's content, blurs it and puts the result back as the layer's
    /// only child. `CALayer.filters` is a no-op on iOS, so the blur must be baked in (B97).
    private func bakeBlur(into layer: CALayer, bbox: CGRect, stdDeviation: CGFloat, scale: CGFloat) {
        guard bbox.width > 0, bbox.height > 0, scale > 0, stdDeviation > 0 else { return }
        // A region past the bitmap cap is rasterized at a lower resolution rather than dropped.
        let side = max(Self.filterRegion.width * bbox.width, Self.filterRegion.height * bbox.height) * scale
        let scale = side > SVGInputLimits.maxPaintBitmapDimension
            ? scale * SVGInputLimits.maxPaintBitmapDimension / side : scale
        guard scale > 0 else { return }

        let region = CGRect(
            x: bbox.origin.x + Self.filterRegion.origin.x * bbox.width,
            y: bbox.origin.y + Self.filterRegion.origin.y * bbox.height,
            width: Self.filterRegion.width * bbox.width,
            height: Self.filterRegion.height * bbox.height)

        // Rasterize without the layer's own mask: the filter applies to the element's
        // geometry, and the mask (clip-path/mask) clips the *result* afterwards.
        let savedMask = layer.mask
        layer.mask = nil
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: region.size, format: format).image { ctx in
            ctx.cgContext.translateBy(x: -region.origin.x, y: -region.origin.y)
            layer.render(in: ctx.cgContext)
        }
        layer.mask = savedMask

        guard let cgImage = image.cgImage, let blurred = Self.blur(cgImage, radius: min(stdDeviation * scale, SVGInputLimits.maxBlurRadius)) else { return }

        layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        // The layer's own `contents` (an `<image>`) is replaced by the baked bitmap too,
        // otherwise the sharp original would show through the blur (B111).
        layer.contents = nil
        let imageLayer = CALayer()
        imageLayer.frame = region
        imageLayer.contents = blurred
        imageLayer.contentsScale = scale
        imageLayer.contentsGravity = .resize
        layer.addSublayer(imageLayer)
    }

    /// Blurs a bitmap, keeping its extent so it still lines up with the region it covers.
    private static func blur(_ image: CGImage, radius: CGFloat) -> CGImage? {
        let input = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        // Clamping avoids the darkened edges a finite extent would otherwise produce.
        filter.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage else { return nil }
        return ciContext.createCGImage(output, from: input.extent)
    }
}
