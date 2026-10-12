import UIKit

/// The encoding of data produced by `SVGRenderer`.
public enum SVGRenderFormat: Sendable {
    /// PNG, with transparency preserved unless a `background` is given.
    case png
    /// JPEG with the given compression quality (`0...1`). JPEG has no alpha channel,
    /// so the background defaults to white.
    case jpeg(quality: CGFloat = 0.9)
    /// A single-page PDF. Shapes stay vector; `scale` is ignored (the page is in points).
    case pdf
}

/// Where the SVG document comes from.
public enum SVGSource: @unchecked Sendable {
    /// Raw SVG markup, with an optional identifier used for parser caching.
    case string(String, name: String? = nil)
    /// Raw SVG data, with an optional identifier used for parser caching.
    case data(Data, name: String? = nil)
    /// The file URL of an SVG.
    case url(URL)
}

/// Renders SVG documents straight to image or PDF `Data`, without creating an `SVGView`.
///
/// Parsing and rasterization run on the library's background queue, so the methods are safe to
/// call from any thread. The completion handler is invoked on that background queue.
public enum SVGRenderer {

    /// Renders `source` to encoded data.
    /// - parameter source: The SVG to render.
    /// - parameter size: The output size in points. `nil` uses the document's own size
    ///   (`width`/`height`, falling back to the `viewBox`). The SVG is fitted using its `preserveAspectRatio`.
    /// - parameter format: The output encoding.
    /// - parameter scale: Pixels per point for raster formats (e.g. `2` for @2x). Defaults to `1`.
    /// - parameter background: A color filled behind the SVG; `nil` keeps PNG/PDF transparent
    ///   (JPEG falls back to white).
    /// - parameter overrideElements: Optional per-element style overrides.
    public static func render(
        _ source: SVGSource,
        size: CGSize? = nil,
        format: SVGRenderFormat = .png,
        scale: CGFloat = 1,
        background: UIColor? = nil,
        overrideElements: [String: SVGSourceStyleElement]? = nil
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            render(source, size: size, format: format, scale: scale, background: background,
                   overrideElements: overrideElements) { continuation.resume(with: $0) }
        }
    }

    /// Callback variant of `render(_:size:format:scale:background:overrideElements:)`.
    /// - parameter completion: Called once with the encoded data or the error, on a background queue.
    public static func render(
        _ source: SVGSource,
        size: CGSize? = nil,
        format: SVGRenderFormat = .png,
        scale: CGFloat = 1,
        background: UIColor? = nil,
        overrideElements: [String: SVGSourceStyleElement]? = nil,
        completion: @escaping @Sendable (Result<Data, Error>) -> Void
    ) {
        // Shares the queue with `SVGView` loads: parsing and layer building mutate per-document state.
        let overrides = UncheckedSendable(overrideElements)
        SVGWorkQueue.shared.async {
            completion(Result {
                try renderSync(source, size: size, format: format, scale: scale,
                               background: background, overrideElements: overrides.value)
            })
        }
    }

    private static func renderSync(
        _ source: SVGSource, size: CGSize?, format: SVGRenderFormat, scale: CGFloat,
        background: UIColor?, overrideElements: [String: SVGSourceStyleElement]?
    ) throws -> Data {
        let parser: SVGParser
        switch source {
        case .string(let string, let name): parser = try SVGParser.getParser(svgString: string, name: name)
        case .data(let data, let name): parser = try SVGParser.getParser(svgData: data, name: name)
        case .url(let url): parser = try SVGParser.getParser(svgURL: url)
        }

        let options = parser.root.getSvgOptions()
        let viewBox = options.viewBox
        let natural = options.size.width > 0 && options.size.height > 0 ? options.size : viewBox.size
        let outputSize = size ?? natural
        guard outputSize.width > 0, outputSize.height > 0, outputSize.width.isFinite, outputSize.height.isFinite else {
            throw SVGError.content(text: "cannot render at size \(outputSize)")
        }
        guard scale > 0 else { throw SVGError.content(text: "scale must be positive") }

        let resolved = options.preserveAspectRatio.resolve(viewBox: viewBox, containerSize: outputSize)
        // Rasterize paint servers (patterns) at the final output resolution.
        let isPDF: Bool
        if case .pdf = format { isPDF = true } else { isPDF = false }
        options.renderScale = max(resolved.scaleX, resolved.scaleY) * (isPDF ? 1 : scale)

        let layer = try parser.getLayer(overrideElements: overrideElements)

        var transform = CATransform3DIdentity
        transform = CATransform3DTranslate(transform, resolved.translateX, resolved.translateY, 0)
        transform = CATransform3DScale(transform, resolved.scaleX, resolved.scaleY, 1)
        transform = CATransform3DTranslate(transform, -viewBox.origin.x, -viewBox.origin.y, 0)
        layer.transform = transform

        let container = CALayer()
        container.bounds = CGRect(origin: .zero, size: outputSize)
        container.anchorPoint = .zero
        container.masksToBounds = true
        container.addSublayer(layer)
        // `CALayer.render(in:)` does not run the display pass, so layers with custom drawing
        // would come out empty without this.
        SVGSignpost.interval("SVGRenderer.display") { forceDisplay(container) }

        let draw: (CGContext) -> Void = { context in
            if let background = background {
                context.setFillColor(background.cgColor)
                context.fill(CGRect(origin: .zero, size: outputSize))
            }
            container.render(in: context)
        }

        switch format {
        case .png:
            let renderer = UIGraphicsImageRenderer(size: outputSize, format: rasterFormat(scale: scale, opaque: false))
            // `pngData` rasterizes (the draw closure) and encodes in one call, so both share a signpost.
            return SVGSignpost.interval("SVGRenderer.rasterize+encode") {
                renderer.pngData { draw($0.cgContext) }
            }
        case .jpeg(let quality):
            let renderer = UIGraphicsImageRenderer(size: outputSize, format: rasterFormat(scale: scale, opaque: true))
            return SVGSignpost.interval("SVGRenderer.rasterize+encode") {
                renderer.jpegData(withCompressionQuality: quality) { rendererContext in
                    if background == nil {
                        UIColor.white.setFill()
                        rendererContext.fill(CGRect(origin: .zero, size: outputSize))
                    }
                    draw(rendererContext.cgContext)
                }
            }
        case .pdf:
            let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: outputSize))
            return SVGSignpost.interval("SVGRenderer.rasterize+encode") {
                renderer.pdfData { draw($0.cgContext) }
            }
        }
    }

    private static func rasterFormat(scale: CGFloat, opaque: Bool) -> UIGraphicsImageRendererFormat {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = opaque
        format.preferredRange = .standard
        return format
    }

    private static func forceDisplay(_ layer: CALayer) {
        layer.setNeedsDisplay()
        layer.displayIfNeeded()
        for sublayer in layer.sublayers ?? [] { forceDisplay(sublayer) }
    }
}

private struct UncheckedSendable<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
