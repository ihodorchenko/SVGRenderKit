import XCTest
@testable import SVGRenderKit

/// B132 — `patternUnits="objectBoundingBox"` with a `viewBox` / `patternTransform`.
@MainActor
final class SVGPatternBBoxTests: XCTestCase {

    private let size = 100

    private func alphaMap(_ body: String) throws -> [UInt8] {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\">\(body)</svg>"
        let layer = try SVGParser(svgString: svg, parsedRoot: nil).getLayer(overrideElements: nil)
        var data = [UInt8](repeating: 0, count: size * size * 4)
        let ctx = CGContext(data: &data, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x: 0, y: CGFloat(size)); ctx.scaleBy(x: 1, y: -1)
        layer.frame = CGRect(x: 0, y: 0, width: size, height: size)
        layer.render(in: ctx)
        return data
    }

    private func a(_ d: [UInt8], _ x: Int, _ y: Int) -> UInt8 { d[(y * size + x) * 4 + 3] }

    func testViewBoxFitIsUniformOnNonSquareBoundingBox() throws {
        // Tile = the whole 100×50 box; the 10×10 viewBox fits uniformly (scale 5), centred:
        // the 5×10 black bar lands on x 25…50 — it must not stretch to x 0…50.
        let d = try alphaMap("""
        <defs><pattern id="p" width="1" height="1" viewBox="0 0 10 10"><rect width="5" height="10" fill="#000"/></pattern></defs>
        <rect width="100" height="50" fill="url(#p)"/>
        """)
        // (Sampled at mid-height and with full-height content: the raw test context is y-flipped.)
        XCTAssertEqual(a(d, 10, 25), 0, "a stretched fit would paint here")
        XCTAssertEqual(a(d, 35, 25), 255)
        XCTAssertEqual(a(d, 60, 25), 0)
    }

    func testPatternTransformActsInUserSpaceForBoundingBoxUnits() throws {
        // Tile 50×50 (0.5 × 1 of the 100×50 box), black bar 0…25 (patternContentUnits=objectBoundingBox). translate(10 0) shifts
        // the grid by 10 user units: the square covers x 10…35 (not a bbox-scaled 1000 units).
        let d = try alphaMap("""
        <defs><pattern id="p" width="0.5" height="1" patternContentUnits="objectBoundingBox" patternTransform="translate(10 0)"><rect width="0.25" height="1" fill="#000"/></pattern></defs>
        <rect width="100" height="50" fill="url(#p)"/>
        """)
        XCTAssertEqual(a(d, 5, 25), 0)
        XCTAssertEqual(a(d, 20, 25), 255)
        XCTAssertEqual(a(d, 40, 25), 0)
    }
}
