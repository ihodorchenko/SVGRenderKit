import XCTest
@testable import SVGRenderKit

final class SVGLinearGradientTagTests: XCTestCase {

    private func findGradientLayer(in layer: CALayer) -> CAGradientLayer? {
        if let gradientLayer = layer as? CAGradientLayer {
            return gradientLayer
        }
        for sublayer in layer.sublayers ?? [] {
            if let found = findGradientLayer(in: sublayer) {
                return found
            }
        }
        return nil
    }

    func testVerticalGradientWithTransformKeepsPointingDown() throws {
        // A vertical gradient with a rotate(45) transform used to flip direction
        // (or produce NaN) due to `atan(y / x)` division.
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>
                <linearGradient id="g" x1="0" y1="0" x2="0" y2="100" gradientTransform="rotate(45)">
                    <stop offset="0" stop-color="#ff0000"/>
                    <stop offset="1" stop-color="#0000ff"/>
                </linearGradient>
            </defs>
            <rect width="100" height="100" fill="url(#g)"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let gradientLayer = try XCTUnwrap(findGradientLayer(in: layer))

        XCTAssertTrue(gradientLayer.startPoint.x.isFinite)
        XCTAssertTrue(gradientLayer.startPoint.y.isFinite)
        XCTAssertTrue(gradientLayer.endPoint.x.isFinite)
        XCTAssertTrue(gradientLayer.endPoint.y.isFinite)

        XCTAssertEqual(gradientLayer.startPoint.x, 0, accuracy: 1e-6)
        XCTAssertEqual(gradientLayer.startPoint.y, 0, accuracy: 1e-6)
        XCTAssertEqual(gradientLayer.endPoint.x, 0, accuracy: 1e-6)
        XCTAssertEqual(gradientLayer.endPoint.y, 1, accuracy: 1e-6)
    }

    func testMalformedGradientTransformDoesNotThrow() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>
                <linearGradient id="g" x1="0" y1="0" x2="0" y2="100" gradientTransform="rotate(foo)">
                    <stop offset="0" stop-color="#ff0000"/>
                    <stop offset="1" stop-color="#0000ff"/>
                </linearGradient>
            </defs>
            <rect width="100" height="100" fill="url(#g)"/>
        </svg>
        """
        // Must log an error to the console but not fail the whole parse.
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        XCTAssertNotNil(layer)
    }
}
