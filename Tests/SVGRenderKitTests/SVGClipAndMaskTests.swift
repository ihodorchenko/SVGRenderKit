import XCTest
@testable import SVGRenderKit

/// B89 — `clip-path` and `mask` on the same element both apply (they intersect);
/// previously the mask overwrote the clip (both wrote `layer.mask`).
final class SVGClipAndMaskTests: XCTestCase {

    private func render(_ body: String) throws -> CALayer {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" viewBox=\"0 0 100 100\">\(body)</svg>"
        return try SVGParser(svgString: svg, parsedRoot: nil).getLayer(overrideElements: nil)
    }

    private func alpha(_ layer: CALayer, at point: CGPoint, size: Int = 100) -> UInt8 {
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        guard let ctx = CGContext(data: &pixels, width: size, height: size, bitsPerComponent: 8,
                                  bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        layer.frame = CGRect(x: 0, y: 0, width: size, height: size)
        layer.render(in: ctx)
        let index = (Int(point.y) * size + Int(point.x)) * 4 + 3
        return pixels[index]
    }

    func testShapeWithClipPathAndMaskAppliesBoth() throws {
        let layer = try render("""
        <defs>
          <clipPath id="c"><rect width="50" height="100"/></clipPath>
          <mask id="m"><rect width="100" height="100" fill="#ffffff"/></mask>
        </defs>
        <rect width="100" height="100" fill="#000000" clip-path="url(#c)" mask="url(#m)"/>
        """)
        XCTAssertGreaterThan(alpha(layer, at: CGPoint(x: 25, y: 50)), 200)
        XCTAssertEqual(alpha(layer, at: CGPoint(x: 75, y: 50)), 0)
    }

    func testGroupWithClipPathAndMaskAppliesBoth() throws {
        let layer = try render("""
        <defs>
          <clipPath id="c"><rect width="50" height="100"/></clipPath>
          <mask id="m"><rect width="100" height="100" fill="#ffffff"/></mask>
        </defs>
        <g clip-path="url(#c)" mask="url(#m)"><rect width="100" height="100" fill="#000000"/></g>
        """)
        XCTAssertGreaterThan(alpha(layer, at: CGPoint(x: 25, y: 50)), 200)
        XCTAssertEqual(alpha(layer, at: CGPoint(x: 75, y: 50)), 0)
    }
}
