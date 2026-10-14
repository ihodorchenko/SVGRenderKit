import XCTest
@testable import SVGRenderKit

final class SVGRadialGradientTests: XCTestCase {

    private func findRadialGradientLayer(in layer: CALayer) -> RadialGradientLayer? {
        if let radial = layer as? RadialGradientLayer {
            return radial
        }
        for sublayer in layer.sublayers ?? [] {
            if let found = findRadialGradientLayer(in: sublayer) {
                return found
            }
        }
        return nil
    }

    func testRadialGradientDefaultsDoNotThrow() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>
                <radialGradient id="g">
                    <stop offset="0" stop-color="#ff0000"/>
                    <stop offset="1" stop-color="#0000ff"/>
                </radialGradient>
            </defs>
            <rect width="100" height="100" fill="url(#g)"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        XCTAssertNotNil(layer)
    }

    func testRadialGradientPercentageAttributes() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>
                <radialGradient id="g" cx="50%" cy="50%" r="50%">
                    <stop offset="0" stop-color="#ff0000"/>
                    <stop offset="1" stop-color="#0000ff"/>
                </radialGradient>
            </defs>
            <rect width="100" height="100" fill="url(#g)"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        XCTAssertNotNil(layer)
    }

    func testRadialGradientTransformTranslate() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>
                <radialGradient id="g" cx="0" cy="0" r="50" gradientUnits="userSpaceOnUse" gradientTransform="translate(10 0)">
                    <stop offset="0" stop-color="#ff0000"/>
                    <stop offset="1" stop-color="#0000ff"/>
                </radialGradient>
            </defs>
            <rect width="100" height="100" fill="url(#g)"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let radial = try XCTUnwrap(findRadialGradientLayer(in: layer))
        XCTAssertEqual(radial.center.x, 10, accuracy: 0.001)
        XCTAssertEqual(radial.center.y, 0, accuracy: 0.001)
        XCTAssertEqual(radial.radius, 50, accuracy: 0.001)
    }

    func testRadialGradientFocalPoint() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>
                <radialGradient id="g" cx="0.5" cy="0.5" r="0.5" fx="0.2" fy="0.3">
                    <stop offset="0" stop-color="#ff0000"/>
                    <stop offset="1" stop-color="#0000ff"/>
                </radialGradient>
            </defs>
            <rect width="100" height="100" fill="url(#g)"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let radial = try XCTUnwrap(findRadialGradientLayer(in: layer))
        // objectBoundingBox keeps center/focal in the element's unit square and maps
        // them onto the box via `gradientTransform`, so map back for the absolute point.
        let center = radial.center.applying(radial.gradientTransform)
        let focal = try XCTUnwrap(radial.focalPoint).applying(radial.gradientTransform)
        XCTAssertEqual(center.x, 50, accuracy: 0.001)
        XCTAssertEqual(center.y, 50, accuracy: 0.001)
        XCTAssertEqual(focal.x, 20, accuracy: 0.001)
        XCTAssertEqual(focal.y, 30, accuracy: 0.001)
    }

    func testRadialGradientFocalDefaultsToCenter() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>
                <radialGradient id="g" cx="0.5" cy="0.5" r="0.5">
                    <stop offset="0" stop-color="#ff0000"/>
                    <stop offset="1" stop-color="#0000ff"/>
                </radialGradient>
            </defs>
            <rect width="100" height="100" fill="url(#g)"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let radial = try XCTUnwrap(findRadialGradientLayer(in: layer))
        let focal = try XCTUnwrap(radial.focalPoint).applying(radial.gradientTransform)
        XCTAssertEqual(focal.x, 50, accuracy: 0.001)
        XCTAssertEqual(focal.y, 50, accuracy: 0.001)
    }

    func testRadialGradientNegativeRadiusDisables() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>
                <radialGradient id="g" cx="0.5" cy="0.5" r="-50%">
                    <stop offset="0" stop-color="#ff0000"/>
                    <stop offset="1" stop-color="#0000ff"/>
                </radialGradient>
            </defs>
            <rect width="100" height="100" fill="url(#g)"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        // A negative radius disables the gradient; no radial layer is created.
        XCTAssertNil(findRadialGradientLayer(in: layer))
    }
}
