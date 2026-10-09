import XCTest
@testable import SVGRenderKit

final class SVGParserTests: XCTestCase {

    func testParseAndRenderMinimalSVG() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <rect x="0" y="0" width="100" height="100" fill="#ff0000"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)

        XCTAssertNotNil(layer)
        XCTAssertFalse(layer.sublayers?.isEmpty ?? true)
    }

    func testParseMissingSVGTagThrows() {
        XCTAssertThrowsError(try SVGParser(svgString: "<rect/>", parsedRoot: nil))
    }
}
