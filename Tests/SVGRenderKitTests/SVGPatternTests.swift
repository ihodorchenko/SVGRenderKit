import XCTest
import UIKit
@testable import SVGRenderKit

/// B98 — `<pattern>`: xlink:href inheritance, viewBox, grid-level patternTransform
/// and the tile phase.
final class SVGPatternTests: XCTestCase {

    private func render(_ body: String) throws -> CALayer {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" viewBox=\"0 0 100 100\">\(body)</svg>"
        return try SVGParser(svgString: svg, parsedRoot: nil).getLayer(overrideElements: nil)
    }

    private func findFilledShapeLayer(in layer: CALayer) -> CAShapeLayer? {
        if let shape = layer as? CAShapeLayer, shape.path != nil, shape.fillColor != nil {
            return shape
        }
        for sublayer in layer.sublayers ?? [] {
            if let found = findFilledShapeLayer(in: sublayer) {
                return found
            }
        }
        return nil
    }

    private func isPatternColor(_ color: CGColor?) -> Bool {
        guard let color = color else { return false }
        return color.pattern != nil
    }

    /// The rendered RGBA at a pixel (sampled at y=50 to avoid the raw context's y-flip).
    private func rgba(_ layer: CALayer, x: Int, y: Int = 50, size: Int = 100) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        guard let ctx = CGContext(data: &pixels, width: size, height: size, bitsPerComponent: 8,
                                  bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return (0, 0, 0, 0) }
        layer.frame = CGRect(x: 0, y: 0, width: size, height: size)
        layer.render(in: ctx)
        let o = (y * size + x) * 4
        return (pixels[o], pixels[o + 1], pixels[o + 2], pixels[o + 3])
    }

    private func isRed(_ c: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) -> Bool { c.r > 200 && c.b < 60 && c.a > 200 }
    private func isBlue(_ c: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) -> Bool { c.b > 200 && c.r < 60 && c.a > 200 }

    // MARK: - Existing behaviour

    func testPatternNotRenderedDirectly() throws {
        let layer = try render("<pattern id=\"p\" width=\"10\" height=\"10\"><rect width=\"10\" height=\"10\" fill=\"#ff0000\"/></pattern>")
        XCTAssertEqual(layer.sublayers?.count ?? 0, 0)
    }

    func testPatternAppliedAsFill() throws {
        let layer = try render("""
        <defs><pattern id="p" width="10" height="10" patternUnits="userSpaceOnUse"><rect width="10" height="10" fill="#ff0000"/></pattern></defs>
        <rect width="100" height="100" fill="url(#p)"/>
        """)
        let shape = try XCTUnwrap(findFilledShapeLayer(in: layer))
        XCTAssertTrue(isPatternColor(shape.fillColor))
    }

    func testMissingPatternIsSkipped() throws {
        let layer = try render("<rect width=\"100\" height=\"100\" fill=\"url(#missing)\"/>")
        XCTAssertEqual(layer.sublayers?.count ?? 0, 1)
    }

    // MARK: - Phase (x/y)

    func testTilePhaseIsApplied() throws {
        // A 10-wide tile at x=5; the tile's left half is red, right half blue. The grid
        // must line up with x=5 (so x=0..4 belongs to the previous tile → blue).
        let layer = try render("""
        <defs><pattern id="p" x="5" y="0" width="10" height="10" patternUnits="userSpaceOnUse" patternContentUnits="userSpaceOnUse">
        <rect x="0" y="0" width="5" height="10" fill="#ff0000"/><rect x="5" y="0" width="5" height="10" fill="#0000ff"/></pattern></defs>
        <rect width="100" height="100" fill="url(#p)"/>
        """)
        XCTAssertTrue(isBlue(rgba(layer, x: 2)), "x=2 is the previous tile's right half → blue")
        XCTAssertTrue(isRed(rgba(layer, x: 7)), "x=7 is inside the tile's left half → red")
        XCTAssertTrue(isBlue(rgba(layer, x: 12)), "x=12 is the tile's right half → blue")
    }

    // MARK: - patternTransform rotates the grid

    func testPatternTransformRotatesTheWholeGrid() throws {
        let body = { (transform: String) in """
        <defs><pattern id="p" width="20" height="20" patternUnits="userSpaceOnUse" patternContentUnits="userSpaceOnUse"\(transform)>
        <rect x="0" y="0" width="20" height="10" fill="#ff0000"/></pattern></defs>
        <rect width="100" height="100" fill="url(#p)"/>
        """ }
        // Axis-aligned horizontal stripes: every row is a single colour.
        let unrotated = try render(body(""))
        let rowColors = Set((0..<40).map { rgba(unrotated, x: $0).r > 128 ? "red" : "other" })
        XCTAssertEqual(rowColors.count, 1, "unrotated stripes leave a row uniform")

        // rotate(45): the row now crosses several stripes.
        let rotated = try render(body(" patternTransform=\"rotate(45)\""))
        var transitions = 0
        var previous = isRed(rgba(rotated, x: 0))
        for x in 1..<40 {
            let current = isRed(rgba(rotated, x: x))
            if current != previous { transitions += 1 }
            previous = current
        }
        XCTAssertGreaterThanOrEqual(transitions, 2, "a rotated grid crosses the row")
    }

    // MARK: - xlink:href inheritance

    func testHrefInheritsContent() throws {
        let layer = try render("""
        <defs>
            <pattern id="a" width="10" height="10" patternUnits="userSpaceOnUse"><rect width="200" height="200" fill="#ff0000"/></pattern>
            <pattern id="b" xlink:href="#a" width="20" height="20" patternUnits="userSpaceOnUse"/>
        </defs>
        <rect width="100" height="100" fill="url(#b)"/>
        """)
        XCTAssertTrue(isRed(rgba(layer, x: 5)))
        XCTAssertTrue(isRed(rgba(layer, x: 25)))
    }

    func testHrefInheritsGeometryAttributes() throws {
        let layer = try render("""
        <defs>
            <pattern id="a" x="5" width="10" height="10" patternUnits="userSpaceOnUse"><rect width="10" height="10" fill="#ff0000"/></pattern>
            <pattern id="b" xlink:href="#a"/>
        </defs>
        <rect width="100" height="100" fill="url(#b)"/>
        """)
        XCTAssertTrue(isRed(rgba(layer, x: 5)))
    }

    // MARK: - viewBox

    func testViewBoxScalesContentAcrossTheTile() throws {
        // viewBox 0 0 10 10 into a 20×20 tile → the 10×10 content covers the whole tile.
        let layer = try render("""
        <defs><pattern id="p" width="20" height="20" patternUnits="userSpaceOnUse" viewBox="0 0 10 10">
        <rect width="10" height="10" fill="#ff0000"/></pattern></defs>
        <rect width="100" height="100" fill="url(#p)"/>
        """)
        XCTAssertTrue(isRed(rgba(layer, x: 5)))
        XCTAssertTrue(isRed(rgba(layer, x: 15)), "viewBox stretches the content over the whole tile")
    }
}
