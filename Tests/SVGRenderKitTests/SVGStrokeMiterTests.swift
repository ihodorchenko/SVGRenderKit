import XCTest
import UIKit
@testable import SVGRenderKit

/// B123 — `stroke-miterlimit` must fall back to the SVG default (4), not to `CALayer`'s own
/// default (10).
///
/// The fixture is a single stroked path whose corner turns by ~17°, so the miter ratio is ~6.8:
/// between the two limits. With the SVG default the spike is cut off and a bevel is drawn; with 10
/// the spike is painted and reaches several pixels past the corner. The test therefore asserts that
/// an *absent* attribute renders exactly like an explicit `stroke-miterlimit="4"`, and — so the
/// fixture cannot pass vacuously — that `"10"` renders further.
final class SVGStrokeMiterTests: XCTestCase {

    private let canvas = 100

    func testDefaultMiterLimitBehavesLikeTheSVGDefault() throws {
        let spikeWithDefault = try sparkExtent(try layer(attributes: ""))
        let spikeWithFour = try sparkExtent(try layer(attributes: "stroke-miterlimit=\"4\""))
        let spikeWithTen = try sparkExtent(try layer(attributes: "stroke-miterlimit=\"10\""))

        XCTAssertGreaterThan(
            spikeWithTen, spikeWithFour,
            "the fixture must actually exercise the miter limit (the spike has to show at 10)"
        )
        XCTAssertEqual(
            spikeWithDefault, spikeWithFour,
            "an unset stroke-miterlimit must behave like the SVG default (4), not CALayer's 10"
        )
    }

    /// The rightmost painted pixel on the row through the corner: a miter spike reaches well past
    /// it, a bevel does not.
    private func sparkExtent(_ layer: CALayer) throws -> Int {
        var pixels = [UInt8](repeating: 0, count: canvas * canvas * 4)
        guard let context = CGContext(data: &pixels, width: canvas, height: canvas, bitsPerComponent: 8,
                                      bytesPerRow: canvas * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw XCTSkip("no bitmap context")
        }
        layer.frame = CGRect(x: 0, y: 0, width: canvas, height: canvas)
        layer.render(in: context)

        let row = canvas / 2
        for column in stride(from: canvas - 1, through: 0, by: -1) where pixels[(row * canvas + column) * 4 + 3] > 8 {
            return column
        }
        return -1
    }

    /// A stroked path with one sharp corner at (50, 50): the two segments go back to the left at
    /// ±8°, so the outer join is a miter that outgrows the SVG limit but fits CALayer's.
    private func layer(attributes: String) throws -> CALayer {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(canvas) \(canvas)">
            <path d="M10 43 L50 50 L10 57" fill="none" stroke="#000000" stroke-width="4" \(attributes)/>
        </svg>
        """
        return try SVGParser(svgString: svg, parsedRoot: nil).getLayer(overrideElements: nil)
    }
}
