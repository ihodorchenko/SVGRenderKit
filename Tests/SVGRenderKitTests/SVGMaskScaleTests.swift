import XCTest
@testable import SVGRenderKit

/// B92 — the mask bitmap must be rasterized at `renderScale`, not at 1 pixel per
/// SVG unit. Otherwise the region-sized bitmap is stretched by the view transform
/// (a 24-unit icon shown at 240 pt blurs 10×).
final class SVGMaskScaleTests: XCTestCase {

    private func findMaskedLayer(in layer: CALayer) -> CALayer? {
        if layer.mask != nil { return layer }
        for sublayer in layer.sublayers ?? [] {
            if let found = findMaskedLayer(in: sublayer) { return found }
        }
        return nil
    }

    /// Renders the same document with the given `renderScale` and returns the mask layer
    /// applied to the shape.
    private func maskLayer(renderScale: CGFloat) throws -> CALayer {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs><mask id="m"><rect width="50" height="50" fill="#ffffff"/></mask></defs>
            <rect width="100" height="100" fill="#ff0000" mask="url(#m)"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        parser.root.getSvgOptions().renderScale = renderScale
        let layer = try parser.getLayer(overrideElements: nil)
        let masked = try XCTUnwrap(findMaskedLayer(in: layer))
        return try XCTUnwrap(masked.mask)
    }

    func testMaskBitmapIsRasterizedAtRenderScale() throws {
        let mask = try maskLayer(renderScale: 4)
        let image: CGImage = try XCTUnwrap(mask.contents) as! CGImage
        // The bitmap covers the mask region in SVG units, so its pixel size must be
        // the region times the render scale to stay sharp once the view scales it up.
        let expectedWidth = Int(mask.frame.width.rounded(.up)) * 4
        let expectedHeight = Int(mask.frame.height.rounded(.up)) * 4
        XCTAssertEqual(image.width, expectedWidth)
        XCTAssertEqual(image.height, expectedHeight)
        XCTAssertEqual(mask.contentsScale, 4, accuracy: 0.001)
    }

    func testMaskBitmapDefaultsToUnitScale() throws {
        let mask = try maskLayer(renderScale: 1)
        let image: CGImage = try XCTUnwrap(mask.contents) as! CGImage
        XCTAssertEqual(image.width, Int(mask.frame.width.rounded(.up)))
        XCTAssertEqual(image.height, Int(mask.frame.height.rounded(.up)))
        XCTAssertEqual(mask.contentsScale, 1, accuracy: 0.001)
    }
}
