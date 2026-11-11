import UIKit
import ImageIO

/// Renders an SVG `<image>` element that embeds a raster image via a data URI.
///
/// Only inline `data:` URIs (typically base64-encoded PNG/JPEG) are supported;
/// external URLs are out of scope and degrade to an empty layer.
class SVGImage: SVGObject, SVGRendering {
    class override var key: String { get { return "image" }}

    /// The owning parent. `unowned`: the parent owns this `<image>` and always outlives it.
    unowned var parent: SVGShapesContainer

    private let presentationStyle = SVGSourceStyleElement()
    private let inlineStyle = SVGSourceStyleElement()
    private let inlineImportantStyle = SVGSourceStyleElement()
    /// Inline `style` declarations that belong to CSS animations (not presentation properties).
    private var cssAnimationDeclarations: [(property: String, value: String)] = []
    private var cssImportantAnimationDeclarations: [(property: String, value: String)] = []

    /// Presentation attributes → normal selector rules → normal inline `style` → `!important`
    /// selector rules → `!important` inline declarations.
    private func effectiveStyle() -> SVGSourceStyleElement {
        var style = presentationStyle
        if let sheet = parent.getSvgOptions().stylesheet {
            style = style.combine(child: sheet.selectorStyle(for: self, media: parent.getSvgOptions().mediaContext))
                .combine(child: inlineStyle)
                .combine(child: sheet.importantSelectorStyle(for: self, media: parent.getSvgOptions().mediaContext))
                .combine(child: inlineImportantStyle)
        } else {
            style = style.combine(child: inlineStyle)
        }
        return style
    }
    var transform: CATransform3D?
    /// How the raster is fitted into the `x`/`y`/`width`/`height` box (default `xMidYMid meet`).
    var preserveAspectRatio = SVGPreserveAspectRatio()

    var x: SVGLength = SVGLength.px(value: 0)
    var y: SVGLength = SVGLength.px(value: 0)
    var width: SVGLength = SVGLength.px(value: 0)
    var height: SVGLength = SVGLength.px(value: 0)
    /// The raw `href` value (a `data:` URI, or an unsupported external URL).
    var imageHref: String?
    /// A short digest of `imageHref`, so the decoded-image cache never stores the full
    /// (potentially multi-MB) data URI as a key.
    private var imageHrefDigest: String?

    /// Decoded raster shared by every `createLayer` of this node (per `<use>`, pattern tile and mask render).
    private let decodedImageCache = SVGBoundedCache<String, UIImage>(limit: 1)

    /// Initializes an `<image>` tag by parsing its position, size, href, and style.
    required init(xmlElement: XMLElement, addDict: [String: String]? = nil, parent: SVGShapesContainer) throws {
        self.parent = parent
        try super.init(xmlElement: xmlElement, addDict: addDict)

        // Presentation attributes, then `<style>`-block rules (resolved at render time), then
        // the inline `style`, which outranks both (B124).
        try presentationStyle.set(attributeDict: attributeDict)
        if let str = attributeDict["style"] {
            let parts = SVGSourceStyleElement.styles(from: str)
            inlineStyle.set(element: parts.normal)
            inlineImportantStyle.set(element: parts.important)
            for declaration in SVGSourceStyleElement.declarationsWithImportance(from: str)
            where declaration.property == "animation" || declaration.property.hasPrefix("animation-") {
                let pair = (property: declaration.property, value: declaration.value)
                if declaration.important {
                    cssImportantAnimationDeclarations.append(pair)
                } else {
                    cssAnimationDeclarations.append(pair)
                }
            }
        }

        if let str = attributeDict["x"] {
            x = try SVGLength.get(string: str)
        }
        if let str = attributeDict["y"] {
            y = try SVGLength.get(string: str)
        }
        if let str = attributeDict["width"] {
            width = try SVGLength.get(string: str)
        }
        if let str = attributeDict["height"] {
            height = try SVGLength.get(string: str)
        }
        if let str = attributeDict["xlink:href"] ?? attributeDict["href"] {
            imageHref = str
            imageHrefDigest = md5Hex(str)
        }
        if let str = attributeDict["transform"] {
            transform = try SVGTransform.get(string: str)
        }
        preserveAspectRatio = SVGPreserveAspectRatio.get(string: attributeDict["preserveAspectRatio"])
    }

    /// Resolves a length against the viewBox dimension, mirroring shape length resolution.
    private func resolve(_ length: SVGLength, reference: CGFloat) -> CGFloat {
        switch length {
        case .px(let value):
            return value
        case .percent(let value):
            return value * reference
        }
    }

    /// The image's box in user space.
    func frame(viewBox: CGRect) -> CGRect {
        return CGRect(x: resolve(x, reference: viewBox.width),
                      y: resolve(y, reference: viewBox.height),
                      width: resolve(width, reference: viewBox.width),
                      height: resolve(height, reference: viewBox.height))
    }

    /// Builds a layer displaying the decoded image at its resolved frame.
    func createLayer(addStyle: SVGSourceStyleElement?, overrideElements: [String: SVGSourceStyleElement]?) throws -> CALayer {
        let viewBox = parent.getSvgOptions().viewBox
        let resolvedX = resolve(x, reference: viewBox.width)
        let resolvedY = resolve(y, reference: viewBox.height)
        let resolvedWidth = resolve(width, reference: viewBox.width)
        let resolvedHeight = resolve(height, reference: viewBox.height)

        // `layer` is a zero-sized container whose origin is the user-space origin (like a
        // group's layer), so `clip-path`/`mask`/`filter`/`transform` act in user space; the
        // picture lives in `content`, placed at (x, y) (B126).
        let style = effectiveStyle()
        let layer = CALayer()
        let content = CALayer()
        content.frame = CGRect(x: resolvedX, y: resolvedY, width: resolvedWidth, height: resolvedHeight)
        layer.addSublayer(content)

        if let href = imageHref, let digest = imageHrefDigest,
           let image = decodedImageCache.value(for: digest, make: { SVGImage.decode(dataURI: href) }) {
            let imageSize = image.size
            if preserveAspectRatio.align == .none || imageSize.width <= 0 || imageSize.height <= 0 {
                content.contents = image.cgImage
                content.contentsGravity = .resize
            } else {
                // Fit the raster per `preserveAspectRatio`; `slice` overflows, so clip to the box.
                let fit = preserveAspectRatio.resolve(
                    viewBox: CGRect(origin: .zero, size: imageSize),
                    containerSize: CGSize(width: resolvedWidth, height: resolvedHeight))
                let picture = CALayer()
                picture.contents = image.cgImage
                picture.contentsGravity = .resize
                picture.frame = CGRect(x: fit.translateX, y: fit.translateY,
                                       width: imageSize.width * fit.scaleX, height: imageSize.height * fit.scaleY)
                content.addSublayer(picture)
                content.masksToBounds = true
            }
        }
        if let display = style.display, display == .none {
            layer.isHidden = true
        }
        if let visibility = style.visibility, visibility != .visible {
            layer.isHidden = true
        }

        // `clip-path` / `mask` / `filter` composite the image like any other element (B111).
        // The `objectBoundingBox` base is the image's own box.
        let box = CGRect(x: resolvedX, y: resolvedY, width: resolvedWidth, height: resolvedHeight)
        let transformContext = SVGTransformStyle.Context(
            viewBox: viewBox, bbox: box,
            origin: style.transformOrigin, box: style.transformBox)
        let resolvedTransform = SVGTransformStyle.resolvedTransform(
            style: style, attributeTransform: transform, context: transformContext)
        do {
            let maskScale = (resolvedTransform?.svgScaleFactor ?? 1)
                * ((parent as? SVGGroupObject)?.accumulatedScale() ?? 1)
            try style.applyGroupComposite(to: layer, bbox: box, container: parent, overrideElements: overrideElements, maskScale: maskScale)
        }

        if let resolvedTransform = resolvedTransform {
            layer.transform = resolvedTransform
        }
        if let opacity = style.opacity {
            layer.opacity = (opacity >= 0 && opacity <= 1) ? opacity : 1
        }

        // CSS animations on an `<image>` (opacity/transform) ride the same attach path as shapes.
        let cssAnimations = cssAnimations(style: style, transformContext: transformContext,
                                          baseTransform: resolvedTransform)
        parent.getSvgOptions().attach(cssAnimations, to: layer, pathLayer: nil)

        return layer
    }

    /// CSS animations on the image: the document's `<style>` rules matching it plus its inline
    /// `style`. Only `opacity` and `transform` apply to a raster element.
    private func cssAnimations(style: SVGSourceStyleElement,
                               transformContext: SVGTransformStyle.Context,
                               baseTransform: CATransform3D?) -> [SVGAnimation] {
        let options = parent.getSvgOptions()
        guard let sheet = options.stylesheet else { return [] }
        let declarations = sheet.animationDeclarations(for: self, media: options.mediaContext)
            + cssAnimationDeclarations
            + sheet.importantAnimationDeclarations(for: self, media: options.mediaContext)
            + cssImportantAnimationDeclarations
        guard !declarations.isEmpty else { return [] }
        let base = SVGCSSAnimations.BaseValues(
            opacity: min(1, max(0, Double(style.opacity ?? 1))),
            transform: baseTransform ?? CATransform3DIdentity)
        return SVGCSSAnimations.animations(
            specs: SVGCSSAnimations.specs(from: declarations),
            keyframes: { [parent] name in parent.keyframes(named: name) },
            base: base,
            properties: [.opacity, .transform],
            transformContextProvider: { transformContext })
    }

    /// Decodes a `data:` URI into a `UIImage`, supporting base64 and percent-encoded payloads.
    static func decode(dataURI: String) -> UIImage? {
        guard dataURI.hasPrefix("data:"), let comma = dataURI.firstIndex(of: ",") else { return nil }
        let metaStart = dataURI.index(dataURI.startIndex, offsetBy: "data:".count)
        let meta = dataURI[metaStart..<comma]
        let payload = dataURI[dataURI.index(after: comma)...]

        if meta.contains(";base64") {
            // A data URI may wrap its base64 payload across lines; ignore the line breaks
            // (and any other stray characters) instead of failing to decode (B99).
            guard let data = Data(base64Encoded: String(payload), options: .ignoreUnknownCharacters) else { return nil }
            return image(from: data)
        }
        guard let decoded = String(payload).removingPercentEncoding,
              let data = decoded.data(using: .utf8) else { return nil }
        return image(from: data)
    }

    /// Decodes `data`, refusing a bitmap over `SVGInputLimits.maxImagePixels` before it is
    /// allocated (a tiny PNG can declare gigapixel dimensions).
    private static func image(from data: Data) -> UIImage? {
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int,
           w * h > SVGInputLimits.maxImagePixels {
            SVGLog.addSLog(errorStr: "skipped <image>: \(w)×\(h) px exceeds the pixel limit")
            return nil
        }
        return UIImage(data: data)
    }
}
