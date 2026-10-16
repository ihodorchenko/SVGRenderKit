import XCTest
@testable import SVGRenderKit

/// B117 — pixel-level coverage that was missing: a blur that really softens the edge (and leaves no
/// sharp copy of the element under it), a drop shadow that is blurred, and `<text>` stroke / `<tspan>`
/// placement as they come out in the bitmap.
@MainActor
final class SVGBlurTextPixelTests: XCTestCase {

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

    private func px(_ d: [UInt8], _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        let i = (y * size + x) * 4
        return (Int(d[i]), Int(d[i + 1]), Int(d[i + 2]), Int(d[i + 3]))
    }

    // MARK: blur

    func testGaussianBlurSoftensTheEdgeWithoutASharpLayerUnderneath() throws {
        let d = try render("""
            <defs><filter id="f" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="4"/></filter></defs>
            <rect x="30" y="30" width="40" height="40" fill="#000" filter="url(#f)"/>
            """)
        // A sharp rect would be fully opaque at x = 31 and fully transparent at x = 28.
        let inside = px(d, 31, 50), outside = px(d, 27, 50)
        XCTAssertLessThan(inside.a, 245, "edge pixel inside the rect must be softened, got \(inside)")
        XCTAssertGreaterThan(inside.a, 60)
        XCTAssertGreaterThan(outside.a, 8, "the blur must bleed outside the rect, got \(outside)")
        XCTAssertLessThan(outside.a, 150)
        // The centre stays solid and far away stays empty.
        XCTAssertGreaterThan(px(d, 50, 50).a, 245)
        XCTAssertEqual(px(d, 5, 50).a, 0)
        // Alpha falls monotonically across the edge: no plateau from an unblurred copy.
        let ramp = (22...38).map { px(d, $0, 50).a }
        XCTAssertEqual(ramp, ramp.sorted(), "alpha must rise monotonically over the edge: \(ramp)")
        XCTAssertGreaterThan(Set(ramp).count, 8, "a real blur produces a gradual ramp: \(ramp)")
    }

    func testDropShadowIsBlurredAndElementStaysSharp() throws {
        let d = try render("""
            <defs><filter id="f" x="-50%" y="-50%" width="200%" height="200%"><feDropShadow dx="12" dy="0" stdDeviation="3" flood-color="#000"/></filter></defs>
            <rect x="20" y="35" width="30" height="30" fill="#f00" filter="url(#f)"/>
            """)
        // The element itself is sharp and red.
        let body = px(d, 35, 50)
        XCTAssertGreaterThan(body.r, 240); XCTAssertGreaterThan(body.a, 245)
        // The shadow (x 32…62) shows to the right of the element, blurred: its right edge at 62
        // is soft, so a pixel just inside is not fully dark and a pixel just outside is not clear.
        let shadowInside = px(d, 59, 50), shadowOutside = px(d, 65, 50)
        XCTAssertGreaterThan(px(d, 55, 50).a, 200, "shadow body visible, got \(px(d, 55, 50))")
        XCTAssertLessThan(shadowInside.a, 250, "shadow edge must be soft, got \(shadowInside)")
        XCTAssertGreaterThan(shadowOutside.a, 5, "shadow bleeds past its edge, got \(shadowOutside)")
        XCTAssertEqual(px(d, 85, 50).a, 0)
    }

    // MARK: text

    private func redPixels(_ d: [UInt8]) -> Int {
        var n = 0
        for y in 0..<size { for x in 0..<size { let p = px(d, x, y); if p.r > 180 && p.g < 80 && p.b < 80 && p.a > 150 { n += 1 } } }
        return n
    }

    // B136: `<text>` stroke (solid colours; gradient/pattern stroke degrades to its fallback).
    func testTextStrokeAttributesPaintAnOutline() throws {
        let d = try render("<text x=\"10\" y=\"70\" font-size=\"60\" font-family=\"Helvetica\" fill=\"none\" stroke=\"#f00\" stroke-width=\"3\">H</text>")
        XCTAssertGreaterThan(redPixels(d), 40, "stroke on <text> must be painted")
    }

    func testTextFillStillPaintedWithStroke() throws {
        let d = try render("<text x=\"10\" y=\"70\" font-size=\"60\" font-family=\"Helvetica\" fill=\"#00f\" stroke=\"#f00\" stroke-width=\"2\">H</text>")
        var blue = 0
        for y in 0..<size { for x in 0..<size { let p = px(d, x, y); if p.b > 180 && p.r < 80 && p.a > 150 { blue += 1 } } }
        XCTAssertGreaterThan(blue, 40, "fill must paint")
        XCTAssertGreaterThan(redPixels(d), 20, "stroke must paint over the glyph edge")
    }

    // MARK: text stroke / compositing (B136)

    private let H = "x=\"10\" y=\"70\" font-size=\"60\" font-family=\"Helvetica\""
    private typealias Pixel = (r: Int, g: Int, b: Int, a: Int)
    private func count(_ d: [UInt8], _ match: (Pixel) -> Bool) -> Int {
        var n = 0
        for y in 0..<size { for x in 0..<size where match(px(d, x, y)) { n += 1 } }
        return n
    }
    private let isRed: (Pixel) -> Bool = { $0.r > 180 && $0.g < 80 && $0.b < 80 && $0.a > 150 }
    private let isBlue: (Pixel) -> Bool = { $0.b > 180 && $0.r < 80 && $0.g < 80 && $0.a > 150 }
    private let isBlack: (Pixel) -> Bool = { $0.r < 60 && $0.g < 60 && $0.b < 60 && $0.a > 200 }

    func testStrokeLiesOutsideTheFillEdge() throws {
        let fillOnly = try render("<text \(H) fill=\"#00f\">H</text>")
        let stroked = try render("<text \(H) fill=\"#00f\" stroke=\"#f00\" stroke-width=\"6\">H</text>")
        let bounds = try XCTUnwrap(region(fillOnly, where: isBlue))
        let strokedBounds = try XCTUnwrap(region(stroked, where: { self.isRed($0) || self.isBlue($0) }))
        // half the stroke width (3px) pokes outside the glyph on every side
        XCTAssertGreaterThan(strokedBounds.width, bounds.width + 3)
        XCTAssertGreaterThan(strokedBounds.height, bounds.height + 3)
        XCTAssertEqual(count(stroked, isRed) > 100, true)
    }

    func testStrokeWithoutFillPaintsOnlyOutline() throws {
        let d = try render("<text \(H) fill=\"none\" stroke=\"#f00\" stroke-width=\"2\">H</text>")
        XCTAssertGreaterThan(count(d, isRed), 40)
        XCTAssertEqual(count(d, isBlue), 0)
        // centre of the H's left stem is hollow-ish: far fewer pixels than a filled glyph would give
        let filled = try render("<text \(H) fill=\"#f00\">H</text>")
        XCTAssertLessThan(count(d, isRed), count(filled, isRed))
    }

    func testStrokeOpacityFadesOutline() throws {
        let d = try render("<text \(H) fill=\"none\" stroke=\"#f00\" stroke-width=\"4\" stroke-opacity=\"0.4\">H</text>")
        XCTAssertEqual(count(d, isRed), 0, "no fully red pixels at 40% opacity")
        XCTAssertGreaterThan(count(d, { $0.r > 0 && $0.a > 60 && $0.a < 140 }), 40)
    }

    func testStrokeDashedOutlineHasLessInkThanSolid() throws {
        let solid = try render("<text \(H) fill=\"none\" stroke=\"#f00\" stroke-width=\"3\">H</text>")
        let dashed = try render("<text \(H) fill=\"none\" stroke=\"#f00\" stroke-width=\"3\" stroke-dasharray=\"6 6\">H</text>")
        XCTAssertGreaterThan(count(dashed, isRed), 20)
        XCTAssertLessThan(count(dashed, isRed), count(solid, isRed) * 3 / 4)
    }

    func testStrokeLinejoinChangesCornerShape() throws {
        let miter = try render("<text \(H) fill=\"none\" stroke=\"#f00\" stroke-width=\"10\" stroke-linejoin=\"miter\">H</text>")
        let round = try render("<text \(H) fill=\"none\" stroke=\"#f00\" stroke-width=\"10\" stroke-linejoin=\"round\">H</text>")
        XCTAssertGreaterThan(count(miter, isRed), count(round, isRed), "round joins cut off the miter corners")
    }

    func testTspanOverridesAndInheritsStroke() throws {
        let d = try render("<text x=\"5\" y=\"60\" font-size=\"40\" font-family=\"Helvetica\" fill=\"none\" stroke=\"#f00\" stroke-width=\"2\">A<tspan stroke=\"#00f\" dx=\"10\">B</tspan></text>")
        let red = try XCTUnwrap(region(d, where: isRed), "text stroke inherited by the plain run")
        let blue = try XCTUnwrap(region(d, where: isBlue), "tspan overrides the stroke colour")
        XCTAssertLessThan(red.minX, blue.minX)
    }

    func testStrokeWidthScalesWithTheViewBox() throws {
        // the same viewBox rendered into a 2x bitmap: stroke pixels grow ~4x
        let body = "<text \(H) fill=\"none\" stroke=\"#f00\" stroke-width=\"3\">H</text>"
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\" width=\"200\" height=\"200\">\(body)</svg>"
        let layer = try SVGParser(svgString: svg, parsedRoot: nil).getLayer(overrideElements: nil)
        let small = try render(body)
        let big = 200
        var data = [UInt8](repeating: 0, count: big * big * 4)
        let ctx = try XCTUnwrap(CGContext(data: &data, width: big, height: big, bitsPerComponent: 8, bytesPerRow: big * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.translateBy(x: 0, y: CGFloat(big)); ctx.scaleBy(x: 2, y: -2)
        layer.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        layer.render(in: ctx)
        var n = 0
        for i in stride(from: 0, to: data.count, by: 4) where data[i] > 180 && data[i + 1] < 80 && data[i + 2] < 80 && data[i + 3] > 150 { n += 1 }
        let ratio = Double(n) / Double(max(1, count(small, isRed)))
        XCTAssertEqual(ratio, 4, accuracy: 1.2, "stroke thickens with the glyphs")
    }

    func testOpacityOnText() throws {
        let d = try render("<text \(H) fill=\"#000\" opacity=\"0.5\">H</text>")
        XCTAssertEqual(count(d, isBlack), 0)
        XCTAssertGreaterThan(count(d, { $0.a > 100 && $0.a < 150 }), 40)
    }

    func testClipPathOnText() throws {
        let d = try render("<defs><clipPath id=\"c\"><rect x=\"0\" y=\"0\" width=\"60\" height=\"100\"/></clipPath></defs><text \(H) fill=\"#000\" clip-path=\"url(#c)\">HH</text>")
        let plain = try render("<text \(H) fill=\"#000\">HH</text>")
        let r = try XCTUnwrap(region(d, where: { $0.a > 100 }), "clipped text must still paint its visible part")
        XCTAssertLessThanOrEqual(r.maxX, 61)
        XCTAssertGreaterThan(try XCTUnwrap(region(plain, where: { $0.a > 100 })).maxX, 70, "unclipped text extends past the clip")
    }

    func testMaskOnText() throws {
        let d = try render("<defs><mask id=\"m\"><rect x=\"0\" y=\"0\" width=\"60\" height=\"100\" fill=\"#fff\"/></mask></defs><text \(H) fill=\"#000\" mask=\"url(#m)\">HH</text>")
        let r = try XCTUnwrap(region(d, where: { $0.a > 100 }), "masked text must still paint its visible part")
        XCTAssertLessThanOrEqual(r.maxX, 61)
    }

    func testFilterOnText() throws {
        let plain = try render("<text \(H) fill=\"#000\">H</text>")
        let d = try render("<defs><filter id=\"f\" x=\"-50%\" y=\"-50%\" width=\"200%\" height=\"200%\"><feGaussianBlur stdDeviation=\"3\"/></filter></defs><text \(H) fill=\"#000\" filter=\"url(#f)\">H</text>")
        XCTAssertGreaterThan(count(d, { $0.a > 5 }), 40, "blurred text must still paint")
        XCTAssertLessThan(count(d, isBlack), count(plain, isBlack) / 2, "blur softens the glyphs")
        XCTAssertGreaterThan(count(d, { $0.a > 5 }), count(plain, { $0.a > 5 }), "blur bleeds beyond the glyph")
    }

    private func region(_ d: [UInt8], where match: ((r: Int, g: Int, b: Int, a: Int)) -> Bool) -> CGRect? {
        var minX = size, minY = size, maxX = -1, maxY = -1
        for y in 0..<size { for x in 0..<size where match(px(d, x, y)) {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        return maxX < 0 ? nil : CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    func testTspanWithOwnFillAndDxDyInMixedContent() throws {
        let d = try render("<text x=\"5\" y=\"40\" font-size=\"30\" font-family=\"Helvetica\" fill=\"#000\">A<tspan fill=\"#0f0\" dx=\"20\" dy=\"15\">B</tspan>C</text>")
        let black = { (p: (r: Int, g: Int, b: Int, a: Int)) in p.r < 60 && p.g < 60 && p.b < 60 && p.a > 200 }
        let green = { (p: (r: Int, g: Int, b: Int, a: Int)) in p.g > 180 && p.r < 80 && p.b < 80 && p.a > 150 }
        let g = try XCTUnwrap(region(d, where: green), "tspan fill must render in its own colour")
        // "A" is the black glyph left of the green one ("C" continues from the shifted baseline).
        let left = try XCTUnwrap(region(d, where: { black($0) }), "text content must render")
        var aMaxY = -1
        for y in 0..<size { for x in 0..<Int(g.minX) where black(px(d, x, y)) { aMaxY = max(aMaxY, y) } }
        XCTAssertGreaterThanOrEqual(aMaxY, 0)
        XCTAssertGreaterThan(g.minX, left.minX + 20, "dx moves the tspan right of the first glyph")
        // dy = 15 lowers the tspan's baseline; the glyph tops differ accordingly.
        XCTAssertEqual(Int(g.maxY) - aMaxY, 15, accuracy: 4)
        // the trailing text continues from the tspan: black pixels exist to the right of the green glyph.
        var rightOfGreen = 0
        for y in 0..<size { for x in Int(g.maxX)..<size where black(px(d, x, y)) { rightOfGreen += 1 } }
        XCTAssertGreaterThan(rightOfGreen, 20, "text after </tspan> must follow it")
    }
}
