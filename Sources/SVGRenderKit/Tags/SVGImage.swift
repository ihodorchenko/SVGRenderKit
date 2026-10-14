import UIKit

/// Renders an SVG `<image>` element that embeds a raster image via a data URI.
///
/// Only inline `data:` URIs (typically base64-encoded PNG/JPEG) are supported;
/// external URLs are out of scope and degrade to an empty layer.
open class SVGImage: SVGObject, SVGRendering {
    class override var key: String { get { return "image" }}

    /// The owning parent. `unowned`: the parent owns this `<image>` and always outlives it.
    unowned var parent: SVGShapesContainer

    var sourceStyle: SVGSourceStyleElement?
    var transform: CATransform3D?
    /// How the raster is fitted into the `x`/`y`/`width`/`height` box (default `xMidYMid meet`).
    var preserveAspectRatio = SVGPreserveAspectRatio()

    var x: SVGLength = SVGLength.px(value: 0)
    var y: SVGLength = SVGLength.px(value: 0)
    var width: SVGLength = SVGLength.px(value: 0)
    var height: SVGLength = SVGLength.px(value: 0)
    /// The raw `href` value (a `data:` URI, or an unsupported external URL).
    var imageHref: String?

    /// Decoded raster shared by every `createLayer` of this node (per `<use>`, pattern tile and mask render).
    private let decodedImageCache = SVGBoundedCache<String, UIImage>(limit: 1)

    /// Initializes an `<image>` tag by parsing its position, size, href, and style.
    public required init(xmlElement: XMLElement, addDict: [String: String]? = nil, parent: SVGShapesContainer) throws {
        self.parent = parent
        try super.init(xmlElement: xmlElement, addDict: addDict)

        let tsStyle: SVGSourceStyleElement = SVGSourceStyleElement()
        if let str = attributeDict["style"] {
            try tsStyle.set(styleStr: str, force: false)
        }
        try tsStyle.set(attributeDict: attributeDict)
        sourceStyle = tsStyle

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
        if let str = attributeDict["xlink:href"] {
            imageHref = str
        } else if let str = attributeDict["href"] {
            imageHref = str
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
    public func createLayer(addStyle: SVGSourceStyleElement?, overrideElements: [String: SVGSourceStyleElement]?) throws -> CALayer {
        let viewBox = parent.getSvgOptions().viewBox
        let resolvedX = resolve(x, reference: viewBox.width)
        let resolvedY = resolve(y, reference: viewBox.height)
        let resolvedWidth = resolve(width, reference: viewBox.width)
        let resolvedHeight = resolve(height, reference: viewBox.height)

        let layer = CALayer()
        layer.frame = CGRect(x: resolvedX, y: resolvedY, width: resolvedWidth, height: resolvedHeight)

        if let href = imageHref, let image = decodedImageCache.value(for: href, make: { SVGImage.decode(dataURI: href) }) {
            let imageSize = image.size
            if preserveAspectRatio.align == .none || imageSize.width <= 0 || imageSize.height <= 0 {
                layer.contents = image.cgImage
                layer.contentsGravity = .resize
            } else {
                // Fit the raster per `preserveAspectRatio`; `slice` overflows, so clip to the box.
                let fit = preserveAspectRatio.resolve(
                    viewBox: CGRect(origin: .zero, size: imageSize),
                    containerSize: CGSize(width: resolvedWidth, height: resolvedHeight))
                let content = CALayer()
                content.contents = image.cgImage
                content.contentsGravity = .resize
                content.frame = CGRect(x: fit.translateX, y: fit.translateY,
                                       width: imageSize.width * fit.scaleX, height: imageSize.height * fit.scaleY)
                layer.addSublayer(content)
                layer.masksToBounds = true
            }
        }
        if let display = sourceStyle?.display, display == .none {
            layer.isHidden = true
        }
        if let visibility = sourceStyle?.visibility, visibility != .visible {
            layer.isHidden = true
        }

        if let transform = transform {
            layer.transform = transform
        }
        if let opacity = sourceStyle?.opacity {
            layer.opacity = (opacity >= 0 && opacity <= 1) ? opacity : 1
        }

        return layer
    }

    /// Decodes a `data:` URI into a `UIImage`, supporting base64 and percent-encoded payloads.
    static func decode(dataURI: String) -> UIImage? {
        guard dataURI.hasPrefix("data:"), let comma = dataURI.firstIndex(of: ",") else { return nil }
        let metaStart = dataURI.index(dataURI.startIndex, offsetBy: "data:".count)
        let meta = dataURI[metaStart..<comma]
        let payload = dataURI[dataURI.index(after: comma)...]

        if meta.contains(";base64") {
            guard let data = Data(base64Encoded: String(payload)) else { return nil }
            return UIImage(data: data)
        }
        guard let decoded = String(payload).removingPercentEncoding,
              let data = decoded.data(using: .utf8) else { return nil }
        return UIImage(data: data)
    }
}
