import XCTest
@testable import SVGRenderKit

/// B94 — a group's `contentBounds` (its `objectBoundingBox` for clip paths and masks)
/// must include the `transform` of its descendants; previously it unioned untransformed
/// shape bounds, so the box was computed in the wrong place.
final class SVGGroupContentBoundsTests: XCTestCase {

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

    // MARK: - contentBounds itself

    func testContentBoundsIncludesChildTransform() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <g><rect x="50" y="10" width="50" height="80" transform="translate(-20 0)"/></g>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let group = try XCTUnwrap(parser.root.svgElement.layerElements.array.compactMap { $0 as? SVGGTag }.first)
        // The rect spans 50..100 locally; translate(-20) moves it to 30..80.
        XCTAssertEqual(group.contentBounds.minX, 30, accuracy: 0.001)
        XCTAssertEqual(group.contentBounds.maxX, 80, accuracy: 0.001)
        XCTAssertEqual(group.contentBounds.minY, 10, accuracy: 0.001)
        XCTAssertEqual(group.contentBounds.maxY, 90, accuracy: 0.001)
    }

    func testContentBoundsIncludesNestedGroupTransform() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <g><g transform="translate(-20 0)"><rect x="50" y="10" width="50" height="80"/></g></g>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let group = try XCTUnwrap(parser.root.svgElement.layerElements.array.compactMap { $0 as? SVGGTag }.first)
        XCTAssertEqual(group.contentBounds.minX, 30, accuracy: 0.001)
        XCTAssertEqual(group.contentBounds.maxX, 80, accuracy: 0.001)
    }

    // MARK: - objectBoundingBox clip path on a group

    func testGroupBoundingBoxClipHonorsChildTransform() throws {
        let layer = try render("""
        <defs>
          <clipPath id="c" clipPathUnits="objectBoundingBox"><rect x="0" y="0" width="0.5" height="1"/></clipPath>
        </defs>
        <g clip-path="url(#c)">
          <rect x="50" y="10" width="50" height="80" fill="#000000" transform="translate(-20 0)"/>
        </g>
        """)
        // Content box is 30..80, so the left-half clip keeps 30..55, not 50..75.
        XCTAssertGreaterThan(alpha(layer, at: CGPoint(x: 40, y: 50)), 200)
        XCTAssertEqual(alpha(layer, at: CGPoint(x: 70, y: 50)), 0)
        XCTAssertEqual(alpha(layer, at: CGPoint(x: 20, y: 50)), 0)
    }

    func testGroupBoundingBoxMaskHonorsChildTransform() throws {
        let layer = try render("""
        <defs>
          <mask id="m" maskUnits="objectBoundingBox" maskContentUnits="objectBoundingBox">
            <rect x="0" y="0" width="0.5" height="1" fill="#ffffff"/>
          </mask>
        </defs>
        <g mask="url(#m)">
          <rect x="50" y="10" width="50" height="80" fill="#000000" transform="translate(-20 0)"/>
        </g>
        """)
        XCTAssertGreaterThan(alpha(layer, at: CGPoint(x: 40, y: 50)), 200)
        XCTAssertEqual(alpha(layer, at: CGPoint(x: 70, y: 50)), 0)
    }
}
