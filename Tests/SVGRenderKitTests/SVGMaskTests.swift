import XCTest
@testable import SVGRenderKit

final class SVGMaskTests: XCTestCase {

    private func findMaskedLayer(in layer: CALayer) -> CALayer? {
        if layer.mask != nil {
            return layer
        }
        for sublayer in layer.sublayers ?? [] {
            if let found = findMaskedLayer(in: sublayer) {
                return found
            }
        }
        return nil
    }

    func testMaskNotRenderedDirectly() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <mask id="m"><rect width="50" height="50" fill="#ffffff"/></mask>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        XCTAssertEqual(layer.sublayers?.count ?? 0, 0)
    }

    func testMaskAppliedToElement() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>
                <mask id="m"><rect width="50" height="50" fill="#ffffff"/></mask>
            </defs>
            <rect width="100" height="100" fill="#ff0000" mask="url(#m)"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let masked = try XCTUnwrap(findMaskedLayer(in: layer))
        XCTAssertNotNil(masked.mask)
        // The mask content is rendered into a bitmap and assigned as `contents`.
        XCTAssertNotNil(masked.mask?.contents)
    }

    func testMissingMaskIsSkipped() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <rect width="100" height="100" fill="#ff0000" mask="url(#missing)"/>
        </svg>
        """
        // A missing reference is logged and skipped, not failing the document (B85).
        let layer = try SVGParser(svgString: svg, parsedRoot: nil).getLayer(overrideElements: nil)
        XCTAssertEqual(layer.sublayers?.count ?? 0, 1)
    }
}
