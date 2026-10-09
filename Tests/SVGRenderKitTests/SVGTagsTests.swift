import XCTest
@testable import SVGRenderKit

final class SVGTagsTests: XCTestCase {

    func testStoresMultipleElementsPerClass() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <rect class="foo" width="10" height="10"/>
            <circle class="foo" cx="50" cy="50" r="10"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let root = try XCTUnwrap(parser.root)
        let items = root.svgElement.all.getAll(byClass: ".foo")
        XCTAssertEqual(items.count, 2)
    }
}
