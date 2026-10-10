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

    func testVerticalGradientWithRotateTransformBecomesDiagonal() throws {
        // A vertical gradient rotated by 45° must become diagonal (not stay vertical).
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>
                <linearGradient id="g" x1="0" y1="0" x2="0" y2="100" gradientUnits="userSpaceOnUse" gradientTransform="rotate(45)">
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

        // The rotation must change the gradient axis; it is no longer vertical.
        XCTAssertNotEqual(gradientLayer.endPoint.x, 0, accuracy: 1e-6)
    }

    func testGradientTransformTranslateShiftsGradient() throws {
        // translate(50 0) on a vertical userSpaceOnUse gradient shifts its axis to x=50.
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>
                <linearGradient id="g" x1="0" y1="0" x2="0" y2="100" gradientUnits="userSpaceOnUse" gradientTransform="translate(50 0)">
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

        XCTAssertEqual(gradientLayer.startPoint.x, 0.5, accuracy: 1e-6)
        XCTAssertEqual(gradientLayer.startPoint.y, 0, accuracy: 1e-6)
        XCTAssertEqual(gradientLayer.endPoint.x, 0.5, accuracy: 1e-6)
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

    func testStopOffsetPercentage() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>
                <linearGradient id="g">
                    <stop offset="0%" stop-color="#ff0000"/>
                    <stop offset="50%" stop-color="#00ff00"/>
                    <stop offset="100%" stop-color="#0000ff"/>
                </linearGradient>
            </defs>
            <rect width="100" height="100" fill="url(#g)"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let gradient = try XCTUnwrap(findGradientLayer(in: layer))
        let locations = try XCTUnwrap(gradient.locations)
        XCTAssertEqual(locations.count, 3)
        XCTAssertEqual(locations[1].doubleValue, 0.5, accuracy: 0.0001)
    }

    func testDefaultGradientUnitsIsObjectBoundingBox() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>
                <linearGradient id="g" x1="0" y1="0" x2="1" y2="0">
                    <stop offset="0" stop-color="#ff0000"/>
                    <stop offset="1" stop-color="#0000ff"/>
                </linearGradient>
            </defs>
            <rect width="100" height="100" fill="url(#g)"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let gradient = try XCTUnwrap(findGradientLayer(in: layer))
        XCTAssertEqual(gradient.startPoint.x, 0, accuracy: 1e-6)
        XCTAssertEqual(gradient.endPoint.x, 1, accuracy: 1e-6)
    }

    func testNegativeStopOffsetClampsToZero() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>
                <linearGradient id="g">
                    <stop offset="-0.5" stop-color="#ff0000"/>
                    <stop offset="0.5" stop-color="#0000ff"/>
                </linearGradient>
            </defs>
            <rect width="100" height="100" fill="url(#g)"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let gradient = try XCTUnwrap(findGradientLayer(in: layer))
        let locations = try XCTUnwrap(gradient.locations)
        XCTAssertEqual(locations.count, 2)
        XCTAssertEqual(locations[0].doubleValue, 0, accuracy: 0.0001)
        XCTAssertEqual(locations[1].doubleValue, 0.5, accuracy: 0.0001)
    }

    func testStopOffsetAboveOneClampsToOne() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>
                <linearGradient id="g">
                    <stop offset="0" stop-color="#ff0000"/>
                    <stop offset="1.5" stop-color="#0000ff"/>
                </linearGradient>
            </defs>
            <rect width="100" height="100" fill="url(#g)"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let gradient = try XCTUnwrap(findGradientLayer(in: layer))
        let locations = try XCTUnwrap(gradient.locations)
        XCTAssertEqual(locations.count, 2)
        XCTAssertEqual(locations[1].doubleValue, 1, accuracy: 0.0001)
    }

    func testSingleStopGradientRendersSolid() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>
                <linearGradient id="g">
                    <stop offset="0" stop-color="#00ff00"/>
                </linearGradient>
            </defs>
            <rect width="100" height="100" fill="url(#g)"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let gradient = try XCTUnwrap(findGradientLayer(in: layer))
        let locations = try XCTUnwrap(gradient.locations)
        XCTAssertEqual(locations.count, 2)
        XCTAssertEqual(gradient.colors?.count, 2)
    }
}
