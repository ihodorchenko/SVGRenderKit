import XCTest
@testable import SVGRenderKit

final class SVGStylesTests: XCTestCase {

    func testSetFontFamilyStoresFontFamilyAndNotClipPath() {
        let style = SVGSourceStyleElement()
        style.setFontFamily(str: "Helvetica, Arial")

        XCTAssertEqual(style.fontFamily, "Helvetica, Arial")
        XCTAssertNil(style.clipPath)
    }

    // MARK: Stroke attributes

    func testStrokeLinecapParsed() throws {
        let style = SVGSourceStyleElement()
        try style.set(attributeDict: ["stroke-linecap": "round"])
        XCTAssertEqual(style.strokeLinecap, .round)
    }

    func testStrokeLinejoinParsed() throws {
        let style = SVGSourceStyleElement()
        try style.set(attributeDict: ["stroke-linejoin": "bevel"])
        XCTAssertEqual(style.strokeLinejoin, .bevel)
    }

    func testStrokeMiterlimitParsed() throws {
        let style = SVGSourceStyleElement()
        try style.set(attributeDict: ["stroke-miterlimit": "8"])
        let miter = try XCTUnwrap(style.strokeMiterlimit)
        XCTAssertEqual(miter, 8, accuracy: 0.0001)
    }

    func testStrokeLinecapInheritLeavesNil() throws {
        let style = SVGSourceStyleElement()
        try style.set(attributeDict: ["stroke-linecap": "inherit"])
        XCTAssertNil(style.strokeLinecap)
    }

    func testStrokeLinecapInvalidThrows() {
        let style = SVGSourceStyleElement()
        XCTAssertThrowsError(try style.set(attributeDict: ["stroke-linecap": "bogus"]))
    }

    func testStrokeAttributesAppliedToLayer() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <line x1="10" y1="10" x2="90" y2="90" stroke="#000000" stroke-width="2"
                  stroke-linecap="round" stroke-linejoin="round" stroke-miterlimit="5"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let shape = try XCTUnwrap(findStrokedShapeLayer(in: layer))

        XCTAssertEqual(shape.lineCap.rawValue, "round")
        XCTAssertEqual(shape.lineJoin.rawValue, "round")
        XCTAssertEqual(shape.miterLimit, 5, accuracy: 0.0001)
    }

    private func findStrokedShapeLayer(in layer: CALayer) -> CAShapeLayer? {
        if let shape = layer as? CAShapeLayer, shape.strokeColor != nil {
            return shape
        }
        for sublayer in layer.sublayers ?? [] {
            if let found = findStrokedShapeLayer(in: sublayer) {
                return found
            }
        }
        return nil
    }
}
