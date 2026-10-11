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

    func testCircleWithNegativeRadiusThrows() {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <circle cx="50" cy="50" r="-10" fill="#ff0000"/>
        </svg>
        """
        XCTAssertThrowsError(try SVGParser(svgString: svg, parsedRoot: nil).getLayer(overrideElements: nil))
    }

    func testSwitchRendersFirstFallbackChild() throws {
        // <switch> renders the first child without conditional-processing
        // attributes, skipping <foreignObject requiredExtensions> (Illustrator).
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
            <switch>
                <foreignObject requiredExtensions="http://ns.adobe.com/AdobeIllustrator/10.0/" x="0" y="0" width="1" height="1"/>
                <g><rect x="1" y="1" width="22" height="22" fill="red"/></g>
            </switch>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let root = try XCTUnwrap(parser.root)
        XCTAssertEqual(root.svgElement.layerElements.array.count, 1)
    }

    func testSwitchSkipsUnsupportedConditionalChild() throws {
        // When every child requires an extension we don't support, <switch> renders nothing.
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
            <switch>
                <foreignObject requiredExtensions="http://example.com/ext" x="0" y="0" width="1" height="1"/>
            </switch>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let root = try XCTUnwrap(parser.root)
        XCTAssertEqual(root.svgElement.layerElements.array.count, 0)
    }
}
