import XCTest
@testable import SVGRenderKit

/// B95 — a `userSpaceOnUse` clip-path is resolved in the element's own user space,
/// so the element's `transform` moves the clip together with its content. Groups
/// used to invert the clip by the group transform, so it stayed put (the browser
/// and the shape path both move it).
final class SVGClipPathTransformTests: XCTestCase {

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
        let index = (Int(point.y) * size + Int(point.x)) * 4 + 3
        return pixels[index]
    }

    private let defs = "<clipPath id=\"c\"><rect width=\"80\" height=\"80\"/></clipPath>"

    func testGroupClipMovesWithTransform() throws {
        // Clip 0..80 and content 0..80 both scale by 1.25 → the clip still covers the
        // content, so nothing is cut (the browser renders the full 0..100 square).
        let layer = try render("""
        <defs>\(defs)</defs>
        <g clip-path="url(#c)" transform="scale(1.25)"><rect width="80" height="80" fill="#000000"/></g>
        """)
        XCTAssertGreaterThan(alpha(layer, at: CGPoint(x: 40, y: 50)), 200)
        XCTAssertGreaterThan(alpha(layer, at: CGPoint(x: 90, y: 50)), 200)
    }

    func testShapeClipMovesWithTransform() throws {
        let layer = try render("""
        <defs>\(defs)</defs>
        <rect width="80" height="80" fill="#000000" clip-path="url(#c)" transform="scale(1.25)"/>
        """)
        XCTAssertGreaterThan(alpha(layer, at: CGPoint(x: 40, y: 50)), 200)
        XCTAssertGreaterThan(alpha(layer, at: CGPoint(x: 90, y: 50)), 200)
    }

    func testGroupClipStillClipsInLocalSpace() throws {
        // Without a transform the clip 0..40 cuts the 0..80 content at 40.
        let layer = try render("""
        <defs><clipPath id="c"><rect width="40" height="80"/></clipPath></defs>
        <g clip-path="url(#c)"><rect width="80" height="80" fill="#000000"/></g>
        """)
        XCTAssertGreaterThan(alpha(layer, at: CGPoint(x: 20, y: 50)), 200)
        XCTAssertEqual(alpha(layer, at: CGPoint(x: 60, y: 50)), 0)
    }
}
