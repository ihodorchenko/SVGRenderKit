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
/// Parsing and layer building run on the library's serial background queue (they share per-document
/// state on cached trees), while rasterization and encoding, which dominate the cost, run concurrently
/// across the available cores. The methods are safe to call from any thread, and the completion handler
/// is invoked on a background queue.
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
        // Cancelling the awaiting task cancels the render cooperatively: queued work that
        // has not started yet is abandoned (B112).
        let token = CancelToken()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                start(source, size: size, format: format, scale: scale, background: background,
                      overrideElements: overrideElements, token: token) { continuation.resume(with: $0) }
            }
        } onCancel: {
            token.cancelled.value = true
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
        start(source, size: size, format: format, scale: scale, background: background,
              overrideElements: overrideElements, token: CancelToken(), completion: completion)
    }

    /// A cooperative cancellation flag, shared between the async wrapper and the queued work.
    private final class CancelToken: @unchecked Sendable {
        let cancelled = LockedBox<Bool>(false)
    }

    private static func start(
        _ source: SVGSource, size: CGSize?, format: SVGRenderFormat, scale: CGFloat,
        background: UIColor?, overrideElements: [String: SVGSourceStyleElement]?,
        token: CancelToken, completion: @escaping @Sendable (Result<Data, Error>) -> Void
    ) {
        // Parsing and layer building share per-document state (`renderScale`, parser cache) with `SVGView`
        // loads, so they run on the shared serial queue. The built layer tree is private to this render,
        // so rasterizing and encoding it can proceed concurrently with other renders.
        let overrides = UncheckedSendable(overrideElements)
        SVGWorkQueue.shared.async {
            guard !token.cancelled.value else { completion(.failure(CancellationError())); return }
            let prepared: Prepared
            do {
                prepared = try prepare(source, size: size, format: format, scale: scale,
                                       background: background, overrideElements: overrides.value)
            } catch {
                completion(.failure(error))
                return
            }
            guard !token.cancelled.value else { completion(.failure(CancellationError())); return }
            let job = UncheckedSendable(prepared)
            rasterizeQueue.addOperation {
                guard !token.cancelled.value else { completion(.failure(CancellationError())); return }
                completion(Result { rasterize(job.value) })
            }
        }
    }

    /// Runs rasterization and encoding. Capped at the core count: each job holds a full bitmap, so
    /// unbounded fan-out would trade speed for memory pressure.
    private static let rasterizeQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "SVGRenderKit.SVGRenderer.rasterize"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = max(2, ProcessInfo.processInfo.activeProcessorCount)
        return queue
    }()

    /// A built layer tree plus everything needed to rasterize it, with no remaining ties to the parsed document.
    private struct Prepared {
        let container: CALayer
        let outputSize: CGSize
        let format: SVGRenderFormat
        let scale: CGFloat
        let background: UIColor?
    }

    private static func prepare(
        _ source: SVGSource, size: CGSize?, format: SVGRenderFormat, scale: CGFloat,
        background: UIColor?, overrideElements: [String: SVGSourceStyleElement]?
    ) throws -> Prepared {
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
        // An untrusted document's natural size (or a caller's size) must not allocate an
        // unbounded bitmap (B102).
        guard SVGInputLimits.bitmapFits(width: outputSize.width * scale, height: outputSize.height * scale,
                                        limit: SVGInputLimits.maxRenderDimension) else {
            throw SVGError.content(text: "cannot render at size \(outputSize) scale \(scale): exceeds the \(Int(SVGInputLimits.maxRenderDimension))px limit")
        }

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
        return Prepared(container: container, outputSize: outputSize, format: format, scale: scale, background: background)
    }

    private static func rasterize(_ prepared: Prepared) -> Data {
        let container = prepared.container
        let outputSize = prepared.outputSize
        let scale = prepared.scale
        let background = prepared.background
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

        switch prepared.format {
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
