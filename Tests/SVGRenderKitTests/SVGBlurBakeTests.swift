import XCTest
@testable import SVGRenderKit

/// B130 — baked blur: dependence on the render scale, resolution under scaled ancestors,
/// and a duplicated shadow when `feDropShadow` and `feGaussianBlur` share a filter.
@MainActor
final class SVGBlurBakeTests: XCTestCase {

    private func parse(_ body: String) throws -> SVGParser {
        try SVGParser(svgString: "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\">\(body)</svg>", parsedRoot: nil)
    }

    /// Bitmap-carrying sublayers (the baked blur).
    private func bitmapLayers(_ l: CALayer) -> [CALayer] {
        var out: [CALayer] = []
        if l.contents != nil { out.append(l) }
        for s in l.sublayers ?? [] { out += bitmapLayers(s) }
        return out
    }

    func testBlurMarksDocumentScaleDependent() throws {
        let parser = try parse("<defs><filter id=\"f\"><feGaussianBlur stdDeviation=\"2\"/></filter></defs><rect x=\"20\" y=\"20\" width=\"40\" height=\"40\" filter=\"url(#f)\"/>")
        _ = try parser.getLayer(overrideElements: nil)
        XCTAssertTrue(parser.root.getSvgOptions().usesMasks, "the baked bitmap depends on renderScale, so a resize must re-render")
    }

    func testBlurBitmapFollowsAncestorScale() throws {
        let parser = try parse("<defs><filter id=\"f\"><feGaussianBlur stdDeviation=\"0.5\"/></filter></defs><g transform=\"scale(4)\"><rect x=\"2\" y=\"2\" width=\"10\" height=\"10\" filter=\"url(#f)\"/></g>")
        let layer = try parser.getLayer(overrideElements: nil)
        let image = try XCTUnwrap(bitmapLayers(layer).first?.contents)
        let width = (image as! CGImage).width
        // region is 12 units wide; drawn 4× larger, so ≥ ~48 px are needed for a sharp result
        XCTAssertGreaterThanOrEqual(width, 44)
    }

    func testDropShadowPlusBlurDoesNotBakeShadowIntoBitmap() throws {
        let parser = try parse("""
        <defs><filter id="f"><feGaussianBlur stdDeviation="0.3"/><feDropShadow dx="4" dy="0" stdDeviation="0" flood-color="#000"/></filter></defs>
        <rect x="20" y="20" width="40" height="40" filter="url(#f)"/>
        """)
        let layer = try parser.getLayer(overrideElements: nil)
        let imageLayer = try XCTUnwrap(bitmapLayers(layer).first)
        let cg = imageLayer.contents as! CGImage
        // The region is the rect ± 10% = x 16…64. The rect ends at 60, its shadow at 64.
        // A pixel at x = 62 is outside the element, so it must be transparent in the bitmap.
        let scale = CGFloat(cg.width) / imageLayer.frame.width
        let px = Int((62 - imageLayer.frame.minX) * scale)
        let py = Int((40 - imageLayer.frame.minY) * scale)
        var data = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: -px, y: -(cg.height - 1 - py), width: cg.width, height: cg.height))
        XCTAssertLessThan(data[3], 40, "the shadow must not be part of the blurred element bitmap")
    }
}
