import UIKit

/// Renders an SVG `<image>` element that embeds a raster image via a data URI.
///
/// Only inline `data:` URIs (typically base64-encoded PNG/JPEG) are supported;
/// external URLs are out of scope and degrade to an empty layer.
open class SVGImage: SVGObject, SVGRendering {
    class override var key: String { get { return "image" }}

    var parent: SVGShapesContainer

    var sourceStyle: SVGSourceStyleElement?
    var transform: CATransform3D?

    var x: SVGLength = SVGLength.px(value: 0)
    var y: SVGLength = SVGLength.px(value: 0)
    var width: SVGLength = SVGLength.px(value: 0)
    var height: SVGLength = SVGLength.px(value: 0)
    /// The raw `href` value (a `data:` URI, or an unsupported external URL).
    var imageHref: String?

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

    /// Builds a layer displaying the decoded image at its resolved frame.
    public func createLayer(addStyle: SVGSourceStyleElement?, overrideElements: [String: SVGSourceStyleElement]?) throws -> CALayer {
        let viewBox = parent.getSvgOptions().viewBox
        let resolvedX = resolve(x, reference: viewBox.width)
        let resolvedY = resolve(y, reference: viewBox.height)
        let resolvedWidth = resolve(width, reference: viewBox.width)
        let resolvedHeight = resolve(height, reference: viewBox.height)

        let layer = CALayer()
        layer.frame = CGRect(x: resolvedX, y: resolvedY, width: resolvedWidth, height: resolvedHeight)

        if let href = imageHref, let image = SVGImage.decode(dataURI: href) {
            layer.contents = image.cgImage
            layer.contentsGravity = .resize
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
