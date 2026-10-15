import XCTest
import UIKit
@testable import SVGRenderKit

/// B100 — a gradient-filled path must honor `fill-rule`: an even-odd path leaves its
/// holes empty, but the gradient's silhouette mask used the default non-zero rule,
/// so the holes were painted.
final class SVGGradientFillRuleTests: XCTestCase {

    private func render(_ body: String) throws -> CALayer {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\">\(body)</svg>"
        return try SVGParser(svgString: svg, parsedRoot: nil).getLayer(overrideElements: nil)
    }

    private func alpha(_ layer: CALayer, at point: CGPoint, size: Int = 100) -> UInt8 {
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        guard let ctx = CGContext(data: &pixels, width: size, height: size, bitsPerComponent: 8,
                                  bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        layer.frame = CGRect(x: 0, y: 0, width: size, height: size)
        layer.render(in: ctx)
        return pixels[(Int(point.y) * size + Int(point.x)) * 4 + 3]
    }

    // Two same-direction subpaths: non-zero fills both, even-odd leaves the inner hole.
    private let defs = "<defs><linearGradient id=\"g\"><stop offset=\"0\" stop-color=\"#ff0000\"/><stop offset=\"1\" stop-color=\"#0000ff\"/></linearGradient></defs>"
    private let hole = "M0 0 H100 V100 H0 Z M25 25 H75 V75 H25 Z"

    func testGradientFillHonorsEvenOddRule() throws {
        let layer = try render("\(defs)<path d=\"\(hole)\" fill=\"url(#g)\" fill-rule=\"evenodd\"/>")
        XCTAssertGreaterThan(alpha(layer, at: CGPoint(x: 10, y: 50)), 200)
        XCTAssertEqual(alpha(layer, at: CGPoint(x: 50, y: 50)), 0, "an even-odd hole must stay empty")
    }

    func testGradientFillNonZeroFillsTheHole() throws {
        let layer = try render("\(defs)<path d=\"\(hole)\" fill=\"url(#g)\" fill-rule=\"nonzero\"/>")
        XCTAssertGreaterThan(alpha(layer, at: CGPoint(x: 10, y: 50)), 200)
        XCTAssertGreaterThan(alpha(layer, at: CGPoint(x: 50, y: 50)), 200, "non-zero fills the inner subpath")
    }
}
