import UIKit
@testable import SVGRenderKit

// MARK: - Fixtures

/// A single SVG fixture used by the parity tests.
struct ParityFixture {
    let name: String
    let svg: String
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
        ParityFixture(name: "clip-path", svg: """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>
                <clipPath id="c"><circle cx="50" cy="50" r="40"/></clipPath>
            </defs>
            <rect width="100" height="100" fill="#e74c3c" clip-path="url(#c)"/>
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
    ]
}

// MARK: - Corpus loader

/// Loads the real icon corpus shipped with the Example app so the parity test can
/// run against it without duplicating the files in the test target.
///
/// The corpus is discovered on disk relative to the repository root (derived from
/// `#filePath`), which works for local development and CI on a full checkout.
enum CorpusLoader {
    /// Enumerates every `.svg` under `Example/Example/data` and returns it as a
    /// fixture named by its path relative to that directory.
    static func load(relativePath: String = "Example/Example/data") -> [ParityFixture] {
        let sourceURL = URL(fileURLWithPath: #filePath)
        let repoRoot = sourceURL
            .deletingLastPathComponent() // SVGRenderKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
        let dataDirectory = repoRoot.appendingPathComponent(relativePath)

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
enum KitRenderer {
    /// Renders `svg` offscreen at the given size and returns a rasterized image.
    static func render(_ svg: String, size: CGSize, timeout: TimeInterval = 5) throws -> UIImage {
        let view = SVGView(frame: CGRect(origin: .zero, size: size))
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

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            view.layer.render(in: context.cgContext)
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
    @objc private final class CGSVGDocument: NSObject {}

    private static let coreSVG: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/PrivateFrameworks/CoreSVG.framework/CoreSVG", RTLD_NOW)

    private static func load<T>(_ name: String) -> T {
        unsafeBitCast(dlsym(coreSVG, name), to: T.self)
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
        guard coreSVG != nil,
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
