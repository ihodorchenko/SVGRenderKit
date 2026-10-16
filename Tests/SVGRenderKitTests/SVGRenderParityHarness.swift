import UIKit
@testable import SVGRenderKit

// MARK: - Fixtures

/// A single SVG fixture used by the parity tests.
struct ParityFixture {
    let name: String
    let svg: String
    /// Overrides the default differing-fraction limit when the CoreSVG reference is
    /// itself limited for this feature (e.g. it rasterizes masks at a low resolution,
    /// so their edges come out soft). `nil` uses the test's default.
    var maxDifferingFraction: Double?
    /// Skips the pixel comparison when CoreSVG rasterizes the feature through a
    /// different code path (e.g. it interpolates radial gradients in another colour
    /// space, lifting the green channel). The fixture is still rendered, so a crash or
    /// a missing gradient is caught — only the raster comparison is waived.
    var referenceLimited: Bool

    init(name: String, svg: String, maxDifferingFraction: Double? = nil, referenceLimited: Bool = false) {
        self.name = name
        self.svg = svg
        self.maxDifferingFraction = maxDifferingFraction
        self.referenceLimited = referenceLimited
    }
}

/// The corpus of fixtures exercised by the on-the-fly parity tests.
///
/// These are intentionally limited to the Icon Profile features the renderer is
/// known to support (`CONFORMANCE.md`): paths, shapes, gradients, clip paths,
/// transforms, strokes and opacity. New fixtures should be added alongside new
/// profile features, not browser-only features.
enum ParityFixtures {
    static let all: [ParityFixture] = [
        ParityFixture(name: "shapes", svg: """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <rect x="10" y="10" width="80" height="80" rx="10" fill="#2f80ed"/>
            <circle cx="50" cy="50" r="25" fill="#ffffff"/>
        </svg>
        """),
        ParityFixture(name: "rounded-rect-oversized-radius", svg: """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <rect x="5" y="5" width="90" height="20" rx="100" ry="100" fill="#e67e22"/>
        </svg>
        """),
        ParityFixture(name: "linear-gradient", svg: """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>
                <linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
                    <stop offset="0" stop-color="#ff0000"/>
                    <stop offset="1" stop-color="#0000ff"/>
                </linearGradient>
            </defs>
            <rect width="100" height="100" fill="url(#g)"/>
        </svg>
        """),
        ParityFixture(name: "gradient-offset-shape", svg: """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>
                <linearGradient id="g" x1="0" y1="0" x2="1" y2="0">
                    <stop offset="0" stop-color="#ff0000"/>
                    <stop offset="1" stop-color="#0000ff"/>
                </linearGradient>
            </defs>
            <rect x="40" y="10" width="50" height="30" fill="url(#g)"/>
        </svg>
        """),
        ParityFixture(name: "gradient-tiny-viewbox", svg: """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1">
            <defs>
                <linearGradient id="g">
                    <stop offset="0" stop-color="#ff0000"/>
                    <stop offset="1" stop-color="#0000ff"/>
                </linearGradient>
            </defs>
            <rect width="1" height="1" fill="url(#g)"/>
        </svg>
        """),
        ParityFixture(name: "linear-gradient-reflect", svg: """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>
                <linearGradient id="g" x1="0.25" y1="0" x2="0.75" y2="0" spreadMethod="reflect">
                    <stop offset="0" stop-color="#ff0000"/><stop offset="1" stop-color="#0000ff"/>
                </linearGradient>
            </defs>
            <rect width="100" height="100" fill="url(#g)"/>
        </svg>
        """),
        ParityFixture(name: "linear-gradient-repeat", svg: """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>
                <linearGradient id="g" x1="0.25" y1="0" x2="0.75" y2="0" spreadMethod="repeat">
                    <stop offset="0" stop-color="#ff0000"/><stop offset="1" stop-color="#0000ff"/>
                </linearGradient>
            </defs>
            <rect width="100" height="100" fill="url(#g)"/>
        </svg>
        """),
        // CoreSVG interpolates radial gradients in a different colour space than the
        // native radial draw (it lifts the green channel), so these rasters can't be
        // compared pixel by pixel — they are rendered only, to catch crashes/gross
        // errors. The geometry they exercise is asserted in SVGRadialGradientGeometryTests.
        ParityFixture(name: "radial-object-bounding-box", svg: """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>
                <radialGradient id="g" cx="50%" cy="50%" r="50%">
                    <stop offset="0" stop-color="#ff0000"/><stop offset="1" stop-color="#0000ff"/>
                </radialGradient>
            </defs>
            <rect x="10" y="30" width="80" height="40" fill="url(#g)"/>
        </svg>
        """, referenceLimited: true),
        ParityFixture(name: "radial-object-bounding-box-focal", svg: """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>
                <radialGradient id="g" cx="0.5" cy="0.5" r="0.5" fx="0.25" fy="0.25">
                    <stop offset="0" stop-color="#ffffff"/><stop offset="1" stop-color="#1e90ff"/>
                </radialGradient>
            </defs>
            <rect x="10" y="20" width="80" height="60" fill="url(#g)"/>
        </svg>
        """, referenceLimited: true),
        ParityFixture(name: "radial-object-bounding-box-transform", svg: """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>
                <radialGradient id="g" cx="0.5" cy="0.5" r="0.5" gradientTransform="translate(0.25 0)">
                    <stop offset="0" stop-color="#ff0000"/><stop offset="1" stop-color="#0000ff"/>
                </radialGradient>
            </defs>
            <rect x="10" y="30" width="80" height="40" fill="url(#g)"/>
        </svg>
        """, referenceLimited: true),
        ParityFixture(name: "radial-user-space-focal", svg: """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>
                <radialGradient id="g" gradientUnits="userSpaceOnUse" cx="50" cy="50" r="40" fx="30" fy="30">
                    <stop offset="0" stop-color="#ffffff"/><stop offset="1" stop-color="#1e90ff"/>
                </radialGradient>
            </defs>
            <rect width="100" height="100" fill="url(#g)"/>
        </svg>
        """, referenceLimited: true),
        ParityFixture(name: "linear-object-bounding-box-transform", svg: """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>
                <linearGradient id="g" x1="0" y1="0" x2="1" y2="0" gradientTransform="rotate(45)">
                    <stop offset="0" stop-color="#ff0000"/><stop offset="1" stop-color="#0000ff"/>
                </linearGradient>
            </defs>
            <rect x="10" y="10" width="80" height="80" fill="url(#g)"/>
        </svg>
        """),
        ParityFixture(name: "clip-path", svg: """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>
                <clipPath id="c"><circle cx="50" cy="50" r="40"/></clipPath>
            </defs>
            <rect width="100" height="100" fill="#e74c3c" clip-path="url(#c)"/>
        </svg>
        """),
        ParityFixture(name: "clip-path-object-bounding-box", svg: """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>
                <clipPath id="c" clipPathUnits="objectBoundingBox">
                    <rect x="0.25" y="0.25" width="0.5" height="0.5"/>
                </clipPath>
            </defs>
            <rect x="10" y="10" width="80" height="80" fill="#e67e22" clip-path="url(#c)"/>
        </svg>
        """),
        ParityFixture(name: "group-object-bounding-box-clip-transform", svg: """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>
                <clipPath id="c" clipPathUnits="objectBoundingBox">
                    <rect x="0" y="0" width="0.5" height="1"/>
                </clipPath>
            </defs>
            <g clip-path="url(#c)">
                <rect x="50" y="10" width="50" height="80" fill="#2f80ed" transform="translate(-20 0)"/>
            </g>
        </svg>
        """),
        // CoreSVG rasterizes masks at a low resolution (soft edges) while the kit
        // renders them at `renderScale` (crisp), so the mask edge needs more headroom.
        ParityFixture(name: "mask-luminance", svg: """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>
                <mask id="m">
                    <rect width="100" height="100" fill="#ffffff"/>
                    <circle cx="50" cy="50" r="30" fill="#000000"/>
                </mask>
            </defs>
            <rect width="100" height="100" fill="#ff0000" mask="url(#m)"/>
        </svg>
        """, maxDifferingFraction: 0.06),
        ParityFixture(name: "pattern-user-space", svg: """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>
                <pattern id="p" width="25" height="25" patternUnits="userSpaceOnUse">
                    <rect width="25" height="25" fill="#ff0000"/>
                    <circle cx="12.5" cy="12.5" r="6" fill="#0000ff"/>
                </pattern>
            </defs>
            <rect width="100" height="100" fill="url(#p)"/>
        </svg>
        """),
        // CoreSVG rasterizes pattern tiles natively, while the kit rasterizes the tile at
        // the output scale; a sub-pixel phase/rotation therefore diverges at the edges.
        // Render-only (B98); the geometry is asserted in SVGPatternTests.
        ParityFixture(name: "pattern-phase", svg: """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>
                <pattern id="p" x="5" y="5" width="20" height="20" patternUnits="userSpaceOnUse" patternContentUnits="userSpaceOnUse">
                    <rect width="10" height="10" fill="#ff0000"/>
                    <rect x="10" y="10" width="10" height="10" fill="#0000ff"/>
                </pattern>
            </defs>
            <rect width="100" height="100" fill="url(#p)"/>
        </svg>
        """, referenceLimited: true),
        ParityFixture(name: "pattern-transform", svg: """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>
                <pattern id="p" width="20" height="20" patternUnits="userSpaceOnUse" patternContentUnits="userSpaceOnUse" patternTransform="rotate(30)">
                    <rect width="20" height="10" fill="#2f80ed"/>
                </pattern>
            </defs>
            <rect width="100" height="100" fill="url(#p)"/>
        </svg>
        """, referenceLimited: true),
        ParityFixture(name: "pattern-viewbox", svg: """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>
                <pattern id="p" width="20" height="20" patternUnits="userSpaceOnUse" viewBox="0 0 10 10">
                    <rect width="5" height="10" fill="#ff0000"/>
                </pattern>
            </defs>
            <rect width="100" height="100" fill="url(#p)"/>
        </svg>
        """),
        ParityFixture(name: "transform", svg: """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <g transform="translate(50 50)">
                <rect x="-25" y="-25" width="50" height="50" fill="#27ae60" transform="rotate(45)"/>
            </g>
        </svg>
        """),
        ParityFixture(name: "evenodd-fill", svg: """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <path d="M10 10 H90 V90 H10 Z M30 30 H70 V70 H30 Z" fill-rule="evenodd" fill="#f1c40f"/>
        </svg>
        """),
        ParityFixture(name: "stroke-and-opacity", svg: """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <line x1="20" y1="20" x2="80" y2="80" stroke="#9b59b6" stroke-width="10" stroke-linecap="round"/>
            <rect x="30" y="30" width="40" height="40" fill="#2ecc71" opacity="0.5"/>
        </svg>
        """),
        ParityFixture(name: "percent-stroke-width", svg: """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <line x1="10" y1="50" x2="90" y2="50" stroke="#2c3e50" stroke-width="10%"/>
        </svg>
        """),
        ParityFixture(name: "percent-shape", svg: """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <rect x="10" y="10" width="50%" height="20" fill="#2f80ed"/>
            <circle cx="50" cy="60" r="25%" fill="#eb5757"/>
        </svg>
        """),
        ParityFixture(name: "group-clip-path", svg: """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>
                <clipPath id="c"><circle cx="50" cy="50" r="40"/></clipPath>
            </defs>
            <g clip-path="url(#c)">
                <rect x="10" y="10" width="80" height="40" fill="#e74c3c"/>
                <rect x="10" y="50" width="80" height="40" fill="#2980b9"/>
            </g>
        </svg>
        """),
        // CoreSVG does not apply the element's transform to a userSpaceOnUse clip-path,
        // so it clips where a browser (and the kit) does not. Render-only (B95); the
        // geometry is asserted in SVGClipPathTransformTests.
        ParityFixture(name: "group-clip-path-transform", svg: """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>
                <clipPath id="c"><rect width="80" height="80"/></clipPath>
            </defs>
            <g clip-path="url(#c)" transform="scale(1.25)">
                <rect width="80" height="80" fill="#27ae60"/>
            </g>
        </svg>
        """, referenceLimited: true),
        ParityFixture(name: "shape-clip-path-transform", svg: """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>
                <clipPath id="c"><rect width="80" height="80"/></clipPath>
            </defs>
            <rect width="80" height="80" fill="#27ae60" clip-path="url(#c)" transform="scale(1.25)"/>
        </svg>
        """, referenceLimited: true),
        ParityFixture(name: "group-opacity", svg: """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <g opacity="0.5">
                <rect x="20" y="20" width="40" height="40" fill="#e74c3c"/>
                <rect x="40" y="40" width="40" height="40" fill="#2980b9"/>
            </g>
        </svg>
        """),
    ]
}

// MARK: - Corpus loader

/// Loads the real icon corpus shipped with the Example app so the parity test can
/// run against it without duplicating the files in the test target.
///
/// The corpus is discovered on disk relative to the repository root (derived from
/// `#filePath`), which works for local development and CI on a full checkout.
enum CorpusLoader {
    /// The repository root, derived from this file's path — the same trick the parity fixtures
    /// use to find the corpus, and `WebKitReferenceRasters` to find its dump pointer.
    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // SVGRenderKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
    }

    /// Enumerates every `.svg` under `Example/Example/data` and returns it as a
    /// fixture named by its path relative to that directory.
    static func load(relativePath: String = "Example/Example/data") -> [ParityFixture] {
        let dataDirectory = repositoryRoot.appendingPathComponent(relativePath)

        guard FileManager.default.fileExists(atPath: dataDirectory.path) else { return [] }

        var fixtures: [ParityFixture] = []
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: dataDirectory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "svg",
                  let data = try? Data(contentsOf: url),
                  let svg = String(data: data, encoding: .utf8) else { continue }
            let name = url.path.replacingOccurrences(of: dataDirectory.path + "/", with: "")
            fixtures.append(ParityFixture(name: name, svg: svg))
        }

        return fixtures.sorted { $0.name < $1.name }
    }
}

// MARK: - Kit renderer

/// Renders an SVG with the library under test (`SVGView`).
@MainActor
enum KitRenderer {
    /// Renders `svg` offscreen at the given size and returns a rasterized image.
    ///
    /// The timeout is generous because a few corpus fixtures are large (e.g.
    /// `PASSPORT_33_gray.svg`, ~250 KB of vectorized glyphs) and parse slowly —
    /// ~8.5s of object-tree building locally, and well over a minute on shared
    /// CI runners. A too-tight timeout would misreport them as crashes.
    static func render(_ svg: String, size: CGSize, timeout: TimeInterval = 300) throws -> UIImage {
        let view = SVGView(frame: CGRect(origin: .zero, size: size))
        // This harness rasterizes the layer tree at 1× (`format.scale = 1` below), so declare
        // that as the destination scale: the kit builds resolution-dependent rasters
        // (patterns, masks) for it (B119-6) and both sides of the comparison stay 1×.
        view.outputScale = 1
        view.svgString = svg

        // `SVGView` parses on a background queue and installs the layer on main.
        // Pump the run loop until the layer is ready.
        guard waitUntil({ view.shapeLayer != nil }, timeout: timeout) else {
            throw NSError(
                domain: "SVGRenderParity",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "SVGView did not finish parsing within \(timeout)s"]
            )
        }

        view.setNeedsLayout()
        view.layoutIfNeeded()

        // `CALayer.render(in:)` rasterizes the layer tree's current contents but
        // does not run the Core Animation display pass. Layers with a custom
        // `draw(in:)` (e.g. the radial gradient layer) built on a background
        // thread never materialize their contents otherwise, so force display
        // first to match what a real on-screen `SVGView` renders.
        forceDisplay(view.layer)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            view.layer.render(in: context.cgContext)
        }
    }

    /// Recursively materializes each layer's contents by running its display pass.
    private static func forceDisplay(_ layer: CALayer) {
        layer.setNeedsDisplay()
        layer.displayIfNeeded()
        for sublayer in layer.sublayers ?? [] {
            forceDisplay(sublayer)
        }
    }
}

// MARK: - Reference renderer (CoreSVG)

/// Renders an SVG with Apple's private `CoreSVG` framework — the same native
/// rasterizer that `UIImage` uses for SVG assets. It is synchronous and
/// deterministic, which makes it a more reliable oracle for on-the-fly tests than
/// a `WKWebView` (which is async and flaky in a bare unit-test bundle).
///
/// The private API is used only in the test target; it never ships in the library.
enum ReferenceRenderer {
    /// Features that CoreSVG (the parity oracle) does not implement, making
    /// pixel comparison against it invalid for fixtures that use them.
    enum UnsupportedFeature {
        case displayNone
        case switchElement
    }

    /// Detects features the reference renderer does not support.
    static func unsupportedFeatures(in svg: String) -> [UnsupportedFeature] {
        var features: [UnsupportedFeature] = []
        let folded = svg.lowercased()
        // `display:none` / `display: none` / `display="none"`.
        if folded.contains("display:none") || folded.contains("display: none") || folded.contains("display=\"none\"") {
            features.append(.displayNone)
        }
        // CoreSVG does not render `<switch>` (SVG 1.1 conditional processing).
        if folded.contains("<switch") {
            features.append(.switchElement)
        }
        return features
    }

    @objc private final class CGSVGDocument: NSObject {}

    private struct Handle: @unchecked Sendable { let pointer: UnsafeMutableRawPointer? }

    private static let coreSVG = Handle(pointer: dlopen(
        "/System/Library/PrivateFrameworks/CoreSVG.framework/CoreSVG", RTLD_NOW))

    private static func load<T>(_ name: String) -> T {
        unsafeBitCast(dlsym(coreSVG.pointer, name), to: T.self)
    }

    private static let createFromData: @convention(c) (CFData?, CFDictionary?) -> Unmanaged<CGSVGDocument>? =
        load("CGSVGDocumentCreateFromData")
    private static let releaseDocument: @convention(c) (CGSVGDocument?) -> Void =
        load("CGSVGDocumentRelease")

    private typealias ImageFromDocument = @convention(c) (AnyObject, Selector, CGSVGDocument) -> UIImage
    private static let imageSelector: Selector = NSSelectorFromString("_imageWithCGSVGDocument:")
    private static let makeImage: ImageFromDocument = unsafeBitCast(
        UIImage.self.method(for: imageSelector), to: ImageFromDocument.self)

    /// Renders `svg` at the given size, scaling the content to fit (`xMidYMid meet`),
    /// matching `SVGView`'s layout. Returns `nil` if CoreSVG is unavailable.
    static func render(_ svg: String, size: CGSize) -> UIImage? {
        guard coreSVG.pointer != nil,
              let data = svg.data(using: .utf8),
              let document = createFromData(data as CFData, nil)?.takeUnretainedValue() else {
            return nil
        }
        defer { releaseDocument(document) }

        let image = makeImage(UIImage.self, imageSelector, document)
        let canvas = image.size
        guard canvas.width > 0, canvas.height > 0 else { return nil }

        let scale = min(size.width / canvas.width, size.height / canvas.height)
        let rendered = CGSize(width: canvas.width * scale, height: canvas.height * scale)
        let rect = CGRect(
            x: (size.width - rendered.width) / 2,
            y: (size.height - rendered.height) / 2,
            width: rendered.width,
            height: rendered.height)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in image.draw(in: rect) }
    }
}

// MARK: - Comparison

/// The result of comparing two rasterized images.
struct ParityComparison {
    let width: Int
    let height: Int
    let differingPixelCount: Int
    let totalPixelCount: Int
    /// Fraction of pixels whose maximum channel delta exceeded the tolerance.
    let differingFraction: Double
    /// Largest per-channel (RGBA) delta across all pixels, 0...255.
    let maxChannelDelta: Int
    /// Mean absolute channel delta across all pixels, normalized to 0...1.
    let meanAbsoluteError: Double

    func passed(maxDifferingFraction: Double) -> Bool {
        differingFraction <= maxDifferingFraction
    }
}

/// Rasterizes images to a common RGBA buffer and compares them pixel by pixel.
enum ImageComparator {
    /// Compares `lhs` and `rhs` at the given pixel size. Pixels whose maximum
    /// channel delta exceeds `tolerance` (0...255) are counted as differing.
    static func compare(_ lhs: UIImage, _ rhs: UIImage, size: CGSize, tolerance: Int) -> ParityComparison? {
        let width = Int(size.width)
        let height = Int(size.height)
        guard let a = rgbaBytes(lhs, width: width, height: height),
              let b = rgbaBytes(rhs, width: width, height: height) else {
            return nil
        }

        let total = width * height
        var differing = 0
        var maxDelta = 0
        var sumAbs = 0

        for i in stride(from: 0, to: a.count, by: 4) {
            let dr = abs(Int(a[i]) - Int(b[i]))
            let dg = abs(Int(a[i + 1]) - Int(b[i + 1]))
            let db = abs(Int(a[i + 2]) - Int(b[i + 2]))
            let da = abs(Int(a[i + 3]) - Int(b[i + 3]))
            let delta = max(dr, dg, db, da)
            if delta > tolerance { differing += 1 }
            if delta > maxDelta { maxDelta = delta }
            sumAbs += delta
        }

        return ParityComparison(
            width: width,
            height: height,
            differingPixelCount: differing,
            totalPixelCount: total,
            differingFraction: Double(differing) / Double(total),
            maxChannelDelta: maxDelta,
            meanAbsoluteError: Double(sumAbs) / Double(total) / 255.0
        )
    }

    /// Whether the image contains at least one non-transparent pixel.
    static func hasOpaquePixels(_ image: UIImage, width: Int = 16, height: Int = 16) -> Bool {
        guard let bytes = rgbaBytes(image, width: width, height: height) else { return false }
        var i = 3
        while i < bytes.count {
            if bytes[i] > 0 { return true }
            i += 4
        }
        return false
    }

    /// Draws `image` into an RGBA8888 (premultiplied, sRGB) buffer at `width`×`height`.
    static func rgbaBytes(_ image: UIImage, width: Int, height: Int) -> [UInt8]? {
        guard let cgImage = image.cgImage else { return nil }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * height)
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue

        let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else { return false }
            context.interpolationQuality = .high
            context.clear(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { return nil }
        return buffer
    }
}

// MARK: - Run loop helper

/// Pumps the main run loop until `condition` returns `true` or `timeout` elapses.
func waitUntil(_ condition: () -> Bool, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        guard Date() < deadline else { return false }
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
    return true
}

// MARK: - Corpus triage annotations

/// Human-readable reasons for the corpus fixtures that diverge from CoreSVG,
/// keyed by the fixture name (path relative to `Example/Example/data`).
///
/// Keeping the reason next to the fixture name lets `testCorpusParity` print
/// *why* each icon diverges instead of just a raw differing fraction, so a
/// triage run is self-explanatory.
enum ParityTriage {
    static let reasons: [String: String] = [
        // ── Text: font metrics / kerning differ from CoreSVG (Roboto/Times may be missing) ──
        "svg_1.0/PASSPORT_31.svg": "text: font metrics/kerning (Roboto-Regular/TimesNewRomanPSMT fallback)",
        "svg_1.0/PASSPORT_33.svg": "text: font metrics/kerning (Roboto-Regular/TimesNewRomanPSMT fallback)",
        "svg_1.0/PASSPORT_33_gray.svg": "text: vectorized glyphs + thin stroke rasterization",

        // ── CoreSVG reference limitations (our renderer is correct) ──
        "svg_0.0/edit_30px.svg": "ref-limit: 8-digit hex #RRGGBBAA mis-rendered by CoreSVG (as opaque black)",

        // ── Gradients ──
        // (svg_0.0/7560-gradient-blue-svg.svg matched the reference once the gradient axis
        // followed the transformed level lines, B119-11.)

        // ── Figma/Sketch drop-shadow: feMorphology erode not applied (shadow not inset) ──
        "svg_3.0/Illustration/cards_black/black_mc_stack.svg": "filter: Figma drop-shadow without feMorphology erode",
        "svg_3.0/Illustration/cards_black/black_mc_3rd_stack.svg": "filter: Figma drop-shadow without feMorphology erode",
        "svg_3.0/Illustration/cards_black/black_visa_stack.svg": "filter: Figma drop-shadow without feMorphology erode",
        "svg_3.0/Illustration/cards_black/black_visa_3rd_stack.svg": "filter: Figma drop-shadow without feMorphology erode",
        "svg_3.0/Illustration/widget_cards.svg": "filter: Figma drop-shadow without feMorphology erode",
        "svg_3.0/Illustration/widget_cards_empty.svg": "filter: Figma drop-shadow without feMorphology erode",

        // ── Mask boundary ──
        "svg_2.0/menu/commission.svg": "mask: region boundary anti-aliasing",
        "svg_3.0/action/icon__action__transaction_special.svg": "mask: region boundary anti-aliasing",

        // ── Clip-path ──
        // CoreSVG ignores the element's own transform on a userSpaceOnUse clip-path, so
        // it clips where a browser (and the kit) does not (verified against WKWebView).
        "svg_1.0/flags1x1/by.svg": "clip-path: CoreSVG ignores the element transform on a userSpaceOnUse clip",

        // ── Complex logos: path rasterization / anti-aliasing vs CoreSVG ──
        "svg_1.0/widget/america.svg": "logo: many-path rasterization / AA",
        "svg_1.0/fifa/ticket.svg": "logo: many-path rasterization / AA",
        "svg_1.0/hawaiiFlowers.svg": "logo: many-path rasterization / AA",
        "svg_1.0/finger_print.svg": "logo: many-path rasterization / AA",
        "svg_2.0/payment/maestro_200px.svg": "logo: many-path rasterization / AA",
        // (svg_3.0/devices/icon__devices__huawei.svg matched the reference once the SVG default
        // stroke-miterlimit was applied, B123.)

        // ── Cards / emblems ──
        "svg_0.0/card1.svg": "card: vectorized-glyph anti-aliasing",
        "svg_0.0/cardsocean_white.svg": "card: CSS class/compound-selector + thin-stroke edge",
        "svg_0.0/unc.svg": "emblem: many-path rasterization (scale(-1,1) transform)",
        "svg_2.0/widget/unc.svg": "emblem: many-path rasterization (scale(-1,1) transform)",

        // ── Small residual anti-aliasing differences (<6% differing) ──
        "svg_0.0/2_Illustr_1.svg": "aa: CoreGraphics vs CoreSVG rasterization",
        "svg_1.0/registrationInfo/2_Illustr_1.svg": "aa: CoreGraphics vs CoreSVG rasterization",
        "svg_1.0/registrationInfo/3_Illustr_1.svg": "aa: CoreGraphics vs CoreSVG rasterization",
        "svg_2.0/onboarding/fingerprint.svg": "aa: CoreGraphics vs CoreSVG rasterization",
        "svg_2.0/onboarding/passport_page31_done.svg": "aa: CoreGraphics vs CoreSVG rasterization",
        "svg_2.0/onboarding/passport_page31_none.svg": "aa: CoreGraphics vs CoreSVG rasterization",
        "svg_2.0/menu/like.svg": "aa: CoreGraphics vs CoreSVG rasterization",
        "svg_2.0/other/trashInRound.svg": "aa: CoreGraphics vs CoreSVG rasterization",
        "svg_2.0/tutorial/cash_back.svg": "aa: CoreGraphics vs CoreSVG rasterization",
        "svg_2.0/tutorial/history_pay.svg": "aa: CoreGraphics vs CoreSVG rasterization",
        "svg_2.0/tutorial/pay.svg": "aa: CoreGraphics vs CoreSVG rasterization",
        "svg_2.0/watch/apple_watch_accept.svg": "aa: CoreGraphics vs CoreSVG rasterization",
        "svg_2.0/watch/apple_watch_notaccept.svg": "aa: CoreGraphics vs CoreSVG rasterization",
    ]

    /// Returns the known reason for a diverging fixture, or `nil` if unknown.
    static func reason(for name: String) -> String? {
        reasons[name]
    }

    /// Human-readable reasons for the fixtures that diverge from the *browser* oracle
    /// (`WKWebView`), keyed by fixture name. The browser comparison runs next to the CoreSVG one
    /// (B122) whenever `SVGRENDERKIT_WEBKIT_RASTERS` points at a dump produced by
    /// `Scripts/webkit-parity.sh`; it reports rather than fails, so an entry here documents a
    /// known difference (and `Scripts/check-parity.sh` keeps the count from growing).
    static func webKitReason(for name: String) -> String? {
        webKitReasons[name]
    }

    static let webKitReasons: [String: String] = [
        // ── A CSS background on the root: browsers paint it, the kit and CoreSVG do not ── (2)
        "svg_2.0/launch/logo_insync.svg": "CSS background on the root: browsers paint it, the kit and CoreSVG do not (not in the Icon Profile)",
        "svg_2.0/launch/logo_insync_grey.svg": "CSS background on the root: browsers paint it, the kit and CoreSVG do not (not in the Icon Profile)",

        // ── Figma drop-shadow filters: feMorphology erode is not applied (see the CoreSVG triage) ── (6)
        "svg_3.0/Illustration/cards_black/black_mc_3rd_stack.svg": "filter: feMorphology erode is not applied by the kit; browsers apply it (CoreSVG does not either)",
        "svg_3.0/Illustration/cards_black/black_mc_stack.svg": "filter: feMorphology erode is not applied by the kit; browsers apply it (CoreSVG does not either)",
        "svg_3.0/Illustration/cards_black/black_visa_3rd_stack.svg": "filter: feMorphology erode is not applied by the kit; browsers apply it (CoreSVG does not either)",
        "svg_3.0/Illustration/cards_black/black_visa_stack.svg": "filter: feMorphology erode is not applied by the kit; browsers apply it (CoreSVG does not either)",
        "svg_3.0/Illustration/widget_cards.svg": "filter: feMorphology erode is not applied by the kit; browsers apply it (CoreSVG does not either)",
        "svg_3.0/Illustration/widget_cards_empty.svg": "filter: feMorphology erode is not applied by the kit; browsers apply it (CoreSVG does not either)",

        // ── Linear gradient stops: browsers mix in sRGB, the kit and CoreSVG in a wider space (B121) ── (37)
        "svg_0.0/7560-gradient-blue-svg.svg": "gradient stops: browsers mix in sRGB, the kit and CoreSVG in a wider space (B121)",
        "svg_1.0/registrationInfo/3_Illustr_1.svg": "gradient stops: browsers mix in sRGB, the kit and CoreSVG in a wider space (B121)",
        "svg_2.0/payment/many_payments_48px.svg": "gradient stops: browsers mix in sRGB, the kit and CoreSVG in a wider space (B121)",
        "svg_3.0/Illustration/cards/Visa_CL_PW_mini.svg": "gradient stops: browsers mix in sRGB, the kit and CoreSVG in a wider space (B121)",
        "svg_3.0/Illustration/cards/Visa_CL_PW_mini_stack.svg": "gradient stops: browsers mix in sRGB, the kit and CoreSVG in a wider space (B121)",
        "svg_3.0/Illustration/cards/Visa_csgo_mini.svg": "gradient stops: browsers mix in sRGB, the kit and CoreSVG in a wider space (B121)",
        "svg_3.0/Illustration/cards/Visa_csgo_mini_stack.svg": "gradient stops: browsers mix in sRGB, the kit and CoreSVG in a wider space (B121)",
        "svg_3.0/Illustration/cards/Visa_cyber_mini.svg": "gradient stops: browsers mix in sRGB, the kit and CoreSVG in a wider space (B121)",
        "svg_3.0/Illustration/cards/Visa_cyber_mini_stack.svg": "gradient stops: browsers mix in sRGB, the kit and CoreSVG in a wider space (B121)",
        "svg_3.0/Illustration/cards/Visa_dota_mini.svg": "gradient stops: browsers mix in sRGB, the kit and CoreSVG in a wider space (B121)",
        "svg_3.0/Illustration/cards/Visa_dota_mini_stack.svg": "gradient stops: browsers mix in sRGB, the kit and CoreSVG in a wider space (B121)",
        "svg_3.0/Illustration/cards/Visa_fifa_mini.svg": "gradient stops: browsers mix in sRGB, the kit and CoreSVG in a wider space (B121)",
        "svg_3.0/Illustration/cards/Visa_fifa_mini_stack.svg": "gradient stops: browsers mix in sRGB, the kit and CoreSVG in a wider space (B121)",
        "svg_3.0/Illustration/cards/belcard_credit_mini.svg": "gradient stops: browsers mix in sRGB, the kit and CoreSVG in a wider space (B121)",
        "svg_3.0/Illustration/cards/cmok_belcard_mini.svg": "gradient stops: browsers mix in sRGB, the kit and CoreSVG in a wider space (B121)",
        "svg_3.0/Illustration/cards/cmok_belcard_mini_stack.svg": "gradient stops: browsers mix in sRGB, the kit and CoreSVG in a wider space (B121)",
        "svg_3.0/Illustration/cards/csgo_mini.svg": "gradient stops: browsers mix in sRGB, the kit and CoreSVG in a wider space (B121)",
        "svg_3.0/Illustration/cards/csgo_mini_stack.svg": "gradient stops: browsers mix in sRGB, the kit and CoreSVG in a wider space (B121)",
        "svg_3.0/Illustration/cards/cyber_mini.svg": "gradient stops: browsers mix in sRGB, the kit and CoreSVG in a wider space (B121)",
        "svg_3.0/Illustration/cards/cyber_mini_stack.svg": "gradient stops: browsers mix in sRGB, the kit and CoreSVG in a wider space (B121)",
        "svg_3.0/Illustration/cards/dota_mini.svg": "gradient stops: browsers mix in sRGB, the kit and CoreSVG in a wider space (B121)",
        "svg_3.0/Illustration/cards/dota_mini_stack.svg": "gradient stops: browsers mix in sRGB, the kit and CoreSVG in a wider space (B121)",
        "svg_3.0/Illustration/cards/ds_mc_pictures_mini.svg": "gradient stops: browsers mix in sRGB, the kit and CoreSVG in a wider space (B121)",
        "svg_3.0/Illustration/cards/ds_mc_pictures_mini_stack.svg": "gradient stops: browsers mix in sRGB, the kit and CoreSVG in a wider space (B121)",
        "svg_3.0/Illustration/cards/ds_visa_braslav_10_mini.svg": "gradient stops: browsers mix in sRGB, the kit and CoreSVG in a wider space (B121)",
        "svg_3.0/Illustration/cards/ds_visa_braslav_10_mini_stack.svg": "gradient stops: browsers mix in sRGB, the kit and CoreSVG in a wider space (B121)",
        "svg_3.0/Illustration/cards/ds_visa_braslav_mini.svg": "gradient stops: browsers mix in sRGB, the kit and CoreSVG in a wider space (B121)",
        "svg_3.0/Illustration/cards/ds_visa_braslav_mini_stack.svg": "gradient stops: browsers mix in sRGB, the kit and CoreSVG in a wider space (B121)",
        "svg_3.0/Illustration/cards/ds_visa_pictures_mini.svg": "gradient stops: browsers mix in sRGB, the kit and CoreSVG in a wider space (B121)",
        "svg_3.0/Illustration/cards/ds_visa_pictures_mini_stack.svg": "gradient stops: browsers mix in sRGB, the kit and CoreSVG in a wider space (B121)",
        "svg_3.0/Illustration/cards/ds_visa_viva_braslav_01_mini.svg": "gradient stops: browsers mix in sRGB, the kit and CoreSVG in a wider space (B121)",
        "svg_3.0/Illustration/cards/ds_visa_viva_braslav_01_mini_stack.svg": "gradient stops: browsers mix in sRGB, the kit and CoreSVG in a wider space (B121)",
        "svg_3.0/Illustration/cards/fifa_mini.svg": "gradient stops: browsers mix in sRGB, the kit and CoreSVG in a wider space (B121)",
        "svg_3.0/Illustration/cards/fifa_mini_stack.svg": "gradient stops: browsers mix in sRGB, the kit and CoreSVG in a wider space (B121)",
        "svg_3.0/Illustration/cards/mc_virtual_ecard_mini.svg": "gradient stops: browsers mix in sRGB, the kit and CoreSVG in a wider space (B121)",
        "svg_3.0/Illustration/cards/mc_virtual_ecard_mini_stack.svg": "gradient stops: browsers mix in sRGB, the kit and CoreSVG in a wider space (B121)",
        "svg_3.0/Illustration/cards/scorina_belcard_mini.svg": "gradient stops: browsers mix in sRGB, the kit and CoreSVG in a wider space (B121)",

        // ── Text: font metrics ── (2)
        "svg_1.0/PASSPORT_31.svg": "text: font metrics/kerning (browser fonts vs the kit's fallback)",
        "svg_1.0/PASSPORT_33.svg": "text: font metrics/kerning (browser fonts vs the kit's fallback)",

        // ── Mask boundary rasterization ── (1)
        "svg_3.0/action/icon__action__transaction_special.svg": "mask: soft mask boundary rasterization (the CoreSVG triage entry for this icon says the same)",

        // ── Anti-aliasing: WebKit vs CoreGraphics at shape edges ── (31)
        "svg_0.0/card1.svg": "aa: WebKit vs CoreGraphics rasterization (differences at shape edges)",
        "svg_0.0/tiger.svg": "aa: WebKit vs CoreGraphics rasterization (differences at shape edges)",
        "svg_0.0/unc.svg": "aa: WebKit vs CoreGraphics rasterization (differences at shape edges)",
        "svg_1.0/calendar_white.svg": "aa: WebKit vs CoreGraphics rasterization (differences at shape edges)",
        "svg_1.0/finger_print.svg": "aa: WebKit vs CoreGraphics rasterization (differences at shape edges)",
        "svg_1.0/hawaiiFlowers.svg": "aa: WebKit vs CoreGraphics rasterization (differences at shape edges)",
        "svg_1.0/logo_bank_old.svg": "aa: WebKit vs CoreGraphics rasterization (differences at shape edges)",
        "svg_1.0/mgm/Illustr_0.svg": "aa: WebKit vs CoreGraphics rasterization (differences at shape edges)",
        "svg_1.0/overall/calendar-tool.svg": "aa: WebKit vs CoreGraphics rasterization (differences at shape edges)",
        "svg_1.0/widget/america.svg": "aa: WebKit vs CoreGraphics rasterization (differences at shape edges)",
        "svg_2.0/applePay/apple-pay.svg": "aa: WebKit vs CoreGraphics rasterization (differences at shape edges)",
        "svg_2.0/interview/video_dark_01.svg": "aa: WebKit vs CoreGraphics rasterization (differences at shape edges)",
        "svg_2.0/interview/video_dark_02.svg": "aa: WebKit vs CoreGraphics rasterization (differences at shape edges)",
        "svg_2.0/interview/video_dark_03.svg": "aa: WebKit vs CoreGraphics rasterization (differences at shape edges)",
        "svg_2.0/interview/video_light_01.svg": "aa: WebKit vs CoreGraphics rasterization (differences at shape edges)",
        "svg_2.0/interview/video_light_02.svg": "aa: WebKit vs CoreGraphics rasterization (differences at shape edges)",
        "svg_2.0/interview/video_light_03.svg": "aa: WebKit vs CoreGraphics rasterization (differences at shape edges)",
        "svg_2.0/onboarding/fingerprint.svg": "aa: WebKit vs CoreGraphics rasterization (differences at shape edges)",
        "svg_2.0/onboarding/key_ok.svg": "aa: WebKit vs CoreGraphics rasterization (differences at shape edges)",
        "svg_2.0/onboarding/passport_page31.svg": "aa: WebKit vs CoreGraphics rasterization (differences at shape edges)",
        "svg_2.0/onboarding/passport_page31_done.svg": "aa: WebKit vs CoreGraphics rasterization (differences at shape edges)",
        "svg_2.0/onboarding/passport_page31_none.svg": "aa: WebKit vs CoreGraphics rasterization (differences at shape edges)",
        "svg_2.0/onboarding/passport_page33.svg": "aa: WebKit vs CoreGraphics rasterization (differences at shape edges)",
        "svg_2.0/onboarding/passport_page33_done.svg": "aa: WebKit vs CoreGraphics rasterization (differences at shape edges)",
        "svg_2.0/onboarding/passport_page33_none.svg": "aa: WebKit vs CoreGraphics rasterization (differences at shape edges)",
        "svg_2.0/payment/Visa_Inc_logo_blue.svg": "aa: WebKit vs CoreGraphics rasterization (differences at shape edges)",
        "svg_2.0/payment/union-pay.svg": "aa: WebKit vs CoreGraphics rasterization (differences at shape edges)",
        "svg_2.0/tutorial/cash_back.svg": "aa: WebKit vs CoreGraphics rasterization (differences at shape edges)",
        "svg_2.0/tutorial/history_pay.svg": "aa: WebKit vs CoreGraphics rasterization (differences at shape edges)",
        "svg_2.0/tutorial/pay.svg": "aa: WebKit vs CoreGraphics rasterization (differences at shape edges)",
        "svg_2.0/widget/unc.svg": "aa: WebKit vs CoreGraphics rasterization (differences at shape edges)",
    ]
}
