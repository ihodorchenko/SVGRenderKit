import XCTest
@testable import SVGRenderKit

final class SVGFilterTests: XCTestCase {

    private func findLayerWithShadow(in layer: CALayer) -> CALayer? {
        if layer.shadowOpacity > 0 {
            return layer
        }
        for sublayer in layer.sublayers ?? [] {
            if let found = findLayerWithShadow(in: sublayer) {
                return found
            }
        }
        return nil
    }

    private func findLayerWithFilters(in layer: CALayer) -> CALayer? {
        if let filters = layer.filters, !filters.isEmpty {
            return layer
        }
        for sublayer in layer.sublayers ?? [] {
            if let found = findLayerWithFilters(in: sublayer) {
                return found
            }
        }
        return nil
    }

    func testDropShadowApplied() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>
                <filter id="f"><feDropShadow dx="2" dy="2" stdDeviation="3" flood-color="#000000" flood-opacity="0.5"/></filter>
            </defs>
            <rect width="50" height="50" fill="#ff0000" filter="url(#f)"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let shadowLayer = try XCTUnwrap(findLayerWithShadow(in: layer))
        XCTAssertGreaterThan(shadowLayer.shadowRadius, 0)
    }

    func testGaussianBlurApplied() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>
                <filter id="f"><feGaussianBlur stdDeviation="3"/></filter>
            </defs>
            <rect width="50" height="50" fill="#ff0000" filter="url(#f)"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        XCTAssertNotNil(findLayerWithFilters(in: layer))
    }

    func testMissingFilterThrows() {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <rect width="50" height="50" fill="#ff0000" filter="url(#missing)"/>
        </svg>
        """
        XCTAssertThrowsError(try SVGParser(svgString: svg, parsedRoot: nil).getLayer(overrideElements: nil))
    }
}
