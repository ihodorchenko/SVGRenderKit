import XCTest
@testable import SVGRenderKit

/// B135 — an `objectBoundingBox` gradient on a stroke is resolved against the bounding box of the
/// geometry *without* the stroke (SVG 1.1 §13.2), the same box a pattern uses. The pixel checks sit
/// inside the stroke, so they tell the stroke's own bounds from the geometry's.
@MainActor
final class SVGGradientStrokeBBoxTests: XCTestCase {

    private let size = 100

    private func render(_ body: String) throws -> [UInt8] {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\">\(body)</svg>"
        let layer = try SVGParser(svgString: svg, parsedRoot: nil).getLayer(overrideElements: nil)
        var data = [UInt8](repeating: 0, count: size * size * 4)
        guard let ctx = CGContext(data: &data, width: size, height: size, bitsPerComponent: 8,
                                  bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return data }
        ctx.translateBy(x: 0, y: CGFloat(size))
        ctx.scaleBy(x: 1, y: -1)
        layer.frame = CGRect(x: 0, y: 0, width: size, height: size)
        layer.render(in: ctx)
        return data
    }

    private func rgba(_ d: [UInt8], _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        let i = (y * size + x) * 4
        return (Int(d[i]), Int(d[i + 1]), Int(d[i + 2]), Int(d[i + 3]))
    }

    private let stops = "<stop offset=\"0\" stop-color=\"#f00\"/><stop offset=\"1\" stop-color=\"#00f\"/>"

    func testLinearStrokeGradientUsesGeometryBBox() throws {
        let d = try render("""
            <defs><linearGradient id="g">\(stops)</linearGradient></defs>
            <rect x="20" y="20" width="60" height="60" fill="none" stroke="url(#g)" stroke-width="20"/>
            """)
        // The same gradient painted as a fill over a box spanning the geometry's x range
        // (20…80) is the reference for the colour at x = 30.
        let ref = try render("""
            <defs><linearGradient id="g">\(stops)</linearGradient></defs>
            <rect x="20" y="0" width="60" height="100" fill="url(#g)"/>
            """)
        let mid = rgba(d, 30, 15), want = rgba(ref, 30, 15)
        XCTAssertEqual(mid.r, want.r, accuracy: 4, "t must be measured over the geometry box, got \(mid), want \(want)")
        XCTAssertEqual(mid.b, want.b, accuracy: 4)
        // Left of the geometry box the gradient pads with its first stop.
        let pad = rgba(d, 12, 50)
        XCTAssertEqual(pad.r, 255, accuracy: 2, "outside the box the first stop pads, got \(pad)")
        XCTAssertEqual(pad.b, 0, accuracy: 2)
    }

    func testRadialStrokeGradientUsesGeometryBBox() throws {
        let d = try render("""
            <defs><radialGradient id="g">\(stops)</radialGradient></defs>
            <rect x="20" y="20" width="60" height="60" fill="none" stroke="url(#g)" stroke-width="20"/>
            """)
        // (50, 15) lies 35 above the centre: beyond the radius of the geometry box (30), so it
        // pads with the last stop; against the stroked box (radius 40) it would still be mid-gradient.
        let p = rgba(d, 50, 15)
        XCTAssertEqual(p.b, 255, accuracy: 3, "got \(p)")
        XCTAssertEqual(p.r, 0, accuracy: 3)
    }

    func testFillGradientIgnoresStroke() throws {
        let body = "<defs><linearGradient id=\"g\">\(stops)</linearGradient></defs>"
        let plain = try render(body + "<rect x=\"20\" y=\"20\" width=\"60\" height=\"60\" fill=\"url(#g)\"/>")
        let stroked = try render(body + "<rect x=\"20\" y=\"20\" width=\"60\" height=\"60\" fill=\"url(#g)\" stroke=\"#000\" stroke-width=\"10\"/>")
        XCTAssertEqual(rgba(stroked, 50, 50).r, rgba(plain, 50, 50).r, accuracy: 1)
        XCTAssertEqual(rgba(stroked, 30, 50).b, rgba(plain, 30, 50).b, accuracy: 1)
    }
}
