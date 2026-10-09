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

    // MARK: Stroke dash

    func testStrokeDasharrayParsed() throws {
        let style = SVGSourceStyleElement()
        try style.set(attributeDict: ["stroke-dasharray": "5, 5"])
        let arr = try XCTUnwrap(style.strokeDasharray)
        XCTAssertEqual(arr, [CGFloat(5), CGFloat(5)])
    }

    func testStrokeDasharraySpaceSeparated() throws {
        let style = SVGSourceStyleElement()
        try style.set(attributeDict: ["stroke-dasharray": "5 3 2"])
        let arr = try XCTUnwrap(style.strokeDasharray)
        XCTAssertEqual(arr, [CGFloat(5), CGFloat(3), CGFloat(2), CGFloat(5), CGFloat(3), CGFloat(2)])
    }

    func testStrokeDasharrayOddCountDoubled() throws {
        let style = SVGSourceStyleElement()
        try style.set(attributeDict: ["stroke-dasharray": "5"])
        let arr = try XCTUnwrap(style.strokeDasharray)
        XCTAssertEqual(arr, [CGFloat(5), CGFloat(5)])
    }

    func testStrokeDasharrayNoneLeavesNil() throws {
        let style = SVGSourceStyleElement()
        try style.set(attributeDict: ["stroke-dasharray": "none"])
        XCTAssertNil(style.strokeDasharray)
    }

    func testStrokeDasharrayInvalidThrows() {
        let style = SVGSourceStyleElement()
        XCTAssertThrowsError(try style.set(attributeDict: ["stroke-dasharray": "foo"]))
    }

    func testStrokeDashoffsetParsed() throws {
        let style = SVGSourceStyleElement()
        try style.set(attributeDict: ["stroke-dashoffset": "3"])
        let offset = try XCTUnwrap(style.strokeDashoffset)
        XCTAssertEqual(offset, 3, accuracy: 0.0001)
    }

    func testStrokeDashAppliedToLayer() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <line x1="0" y1="50" x2="100" y2="50" stroke="#000000" stroke-width="2"
                  stroke-dasharray="5 5" stroke-dashoffset="2"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let shape = try XCTUnwrap(findStrokedShapeLayer(in: layer))

        guard let pattern = shape.lineDashPattern else {
            return XCTFail("expected a dash pattern")
        }
        XCTAssertEqual(pattern.count, 2)
        XCTAssertEqual(pattern[0].doubleValue, 5, accuracy: 0.0001)
        XCTAssertEqual(pattern[1].doubleValue, 5, accuracy: 0.0001)
        XCTAssertEqual(shape.lineDashPhase, 2, accuracy: 0.0001)
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
