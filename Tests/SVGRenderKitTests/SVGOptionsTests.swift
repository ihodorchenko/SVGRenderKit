import XCTest
@testable import SVGRenderKit

final class SVGOptionsTests: XCTestCase {

    // MARK: T38 — version / baseProfile

    func testVersionAndBaseProfileParsed() throws {
        let options = try SVGOptions(attributeDict: [
            "viewBox": "0 0 100 100",
            "version": "1.1",
            "baseProfile": "tiny"
        ])
        XCTAssertEqual(options.version, "1.1")
        XCTAssertEqual(options.baseProfile, "tiny")
    }

    func testVersionAndBaseProfileDefaultNil() throws {
        let options = try SVGOptions(attributeDict: [
            "viewBox": "0 0 100 100"
        ])
        XCTAssertNil(options.version)
        XCTAssertNil(options.baseProfile)
    }

    // MARK: T39 — unknown elements are tolerated

    func testUnknownElementsAreTolerated() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" version="1.1" viewBox="0 0 100 100">
            <metadata><foo>bar</foo></metadata>
            <title>My icon</title>
            <desc>Description</desc>
            <unknownElement attr="x"/>
            <image href="nope.png"/>
            <switch><g/></switch>
            <rect width="10" height="10" fill="#ff0000"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        XCTAssertNotNil(layer)
        XCTAssertFalse(layer.sublayers?.isEmpty ?? true)
    }
}
