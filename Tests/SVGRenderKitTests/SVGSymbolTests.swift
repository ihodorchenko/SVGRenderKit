import XCTest
@testable import SVGRenderKit

final class SVGSymbolTests: XCTestCase {

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

    private func findTransformedLayer(in layer: CALayer) -> CALayer? {
        if !CATransform3DIsIdentity(layer.transform) {
            return layer
        }
        for sublayer in layer.sublayers ?? [] {
            if let found = findTransformedLayer(in: sublayer) {
                return found
            }
        }
        return nil
    }

    func testSymbolNotRenderedDirectly() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <symbol id="s" viewBox="0 0 10 10"><rect width="10" height="10" fill="#ff0000"/></symbol>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        XCTAssertEqual(layer.sublayers?.count ?? 0, 0)
    }

    func testUseRendersSymbolContent() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <symbol id="s" viewBox="0 0 10 10"><rect width="10" height="10" fill="#ff0000"/></symbol>
            <use href="#s" x="10" y="10" width="10" height="10"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let shape = try XCTUnwrap(findFilledShapeLayer(in: layer))
        XCTAssertNotNil(shape.path)
    }

    func testUseScalesSymbolByViewBox() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <symbol id="s" viewBox="0 0 10 10"><rect width="10" height="10" fill="#ff0000"/></symbol>
            <use href="#s" width="20" height="20"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let transformed = try XCTUnwrap(findTransformedLayer(in: layer))
        XCTAssertEqual(transformed.transform.m11, 2, accuracy: 0.0001)
        XCTAssertEqual(transformed.transform.m22, 2, accuracy: 0.0001)
    }

    func testUseMissingSymbolThrows() {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <use href="#missing"/>
        </svg>
        """
        XCTAssertThrowsError(try SVGParser(svgString: svg, parsedRoot: nil).getLayer(overrideElements: nil))
    }
}
