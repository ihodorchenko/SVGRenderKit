import XCTest
@testable import SVGRenderKit

final class SVGRadialGradientTests: XCTestCase {

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
}
