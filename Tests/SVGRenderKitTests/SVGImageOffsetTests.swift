import XCTest
@testable import SVGRenderKit

/// B126 — an `<image>` placed at (x, y) ≠ 0: clip-path / mask / blur / transform must work in
/// user space, not in the image layer's local space.
@MainActor
final class SVGImageOffsetTests: XCTestCase {

    private let size = 100
    // 1×1 opaque red PNG
    private let redPNG = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg=="

    private func layer(_ body: String) throws -> CALayer {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" viewBox=\"0 0 100 100\">\(body)</svg>"
        return try SVGParser(svgString: svg, parsedRoot: nil).getLayer(overrideElements: nil)
    }

    private func alphaMap(_ layer: CALayer) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: size * size * 4)
        let ctx = CGContext(data: &data, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x: 0, y: CGFloat(size)); ctx.scaleBy(x: 1, y: -1)
        layer.frame = CGRect(x: 0, y: 0, width: size, height: size)
        layer.render(in: ctx)
        return data
    }

    private func a(_ d: [UInt8], _ x: Int, _ y: Int) -> UInt8 { d[(y * size + x) * 4 + 3] }

    private func image(_ attrs: String) -> String {
        "<image x=\"40\" y=\"40\" width=\"40\" height=\"40\" preserveAspectRatio=\"none\" href=\"\(redPNG)\" \(attrs)/>"
    }

    func testControlImageAtOffsetDrawsAtOffset() throws {
        let d = alphaMap(try layer(image("")))
        XCTAssertEqual(a(d, 60, 60), 255)
        XCTAssertEqual(a(d, 20, 20), 0)
    }

    func testUserSpaceClipPathIsNotShiftedByImageOrigin() throws {
        // clip keeps only x in [40,60) of user space.
        let d = alphaMap(try layer("<defs><clipPath id=\"c\"><rect x=\"40\" y=\"0\" width=\"20\" height=\"100\"/></clipPath></defs>" + image("clip-path=\"url(#c)\"")))
        XCTAssertEqual(a(d, 50, 60), 255, "inside clip & image")
        XCTAssertEqual(a(d, 70, 60), 0, "image part outside clip")
    }

    func testObjectBoundingBoxClipPathCoversImageBox() throws {
        let d = alphaMap(try layer("<defs><clipPath id=\"c\" clipPathUnits=\"objectBoundingBox\"><rect x=\"0\" y=\"0\" width=\"0.5\" height=\"1\"/></clipPath></defs>" + image("clip-path=\"url(#c)\"")))
        XCTAssertEqual(a(d, 50, 60), 255)
        XCTAssertEqual(a(d, 70, 60), 0)
    }

    func testUserSpaceMaskIsNotShifted() throws {
        let d = alphaMap(try layer("<defs><mask id=\"m\" maskUnits=\"userSpaceOnUse\" x=\"0\" y=\"0\" width=\"100\" height=\"100\"><rect x=\"40\" y=\"0\" width=\"20\" height=\"100\" fill=\"#fff\"/></mask></defs>" + image("mask=\"url(#m)\"")))
        XCTAssertEqual(a(d, 50, 60), 255)
        XCTAssertEqual(a(d, 70, 60), 0)
    }

    func testBlurKeepsLeftTopEdge() throws {
        let d = alphaMap(try layer("<defs><filter id=\"f\"><feGaussianBlur stdDeviation=\"3\"/></filter></defs>" + image("filter=\"url(#f)\"")))
        // blur spreads past the box on all sides: a pixel just outside the left edge is non-transparent
        XCTAssertGreaterThan(a(d, 38, 60), 0, "left edge must bleed (not be cropped)")
        XCTAssertGreaterThan(a(d, 60, 38), 0, "top edge must bleed")
        XCTAssertGreaterThan(a(d, 82, 60), 0, "right edge must bleed")
    }

    func testTransformRotatesAroundUserOrigin() throws {
        // rotate(90) about the user origin maps (x,y) -> (-y, x): the box ends at negative x → invisible
        let d = alphaMap(try layer(image("transform=\"rotate(90)\"")))
        XCTAssertEqual(a(d, 60, 60), 0)
        // translate+scale composition: translate(10,0) moves the box by 10 exactly
        let d2 = alphaMap(try layer(image("transform=\"translate(10 0) scale(0.5)\"")))
        // box (40..80) scaled 0.5 → (20..40), +10 → (30..50)
        XCTAssertEqual(a(d2, 40, 25), 255)
        XCTAssertEqual(a(d2, 60, 60), 0)
    }
}
