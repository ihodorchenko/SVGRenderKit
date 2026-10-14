import XCTest
@testable import SVGRenderKit

/// B85 — a single malformed value or element must never fail the whole document:
/// the offending property / element is logged and skipped, the rest still renders.
final class SVGGracefulDegradationTests: XCTestCase {

    private func render(_ body: String) throws -> CALayer {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" viewBox=\"0 0 100 100\">\(body)</svg>"
        return try SVGParser(svgString: svg, parsedRoot: nil).getLayer(overrideElements: nil)
    }

    /// Counts rendered shape layers (each shape contributes its `pathLayer`).
    private func shapeLayerCount(_ layer: CALayer) -> Int {
        var count = 0
        if let shape = layer as? CAShapeLayer, shape.path != nil { count += 1 }
        for sublayer in layer.sublayers ?? [] {
            count += shapeLayerCount(sublayer)
        }
        return count
    }

    private let good = "<rect x=\"10\" y=\"10\" width=\"20\" height=\"20\" fill=\"#00ff00\"/>"

    // MARK: Malformed property values are ignored, the shape still renders

    func testUnknownPaintValueIsIgnored() throws {
        let layer = try render("<rect width=\"10\" height=\"10\" fill=\"transparent\"/>" + good)
        XCTAssertEqual(shapeLayerCount(layer), 2)
    }

    func testInheritAndContextPaintValuesAreIgnored() throws {
        let layer = try render("<rect width=\"10\" height=\"10\" fill=\"inherit\" stroke=\"context-fill\"/>" + good)
        XCTAssertEqual(shapeLayerCount(layer), 2)
    }

    func testInvalidOpacityValuesAreIgnored() throws {
        let layer = try render("<rect width=\"10\" height=\"10\" opacity=\"1.2\" fill-opacity=\"abc\"/>" + good)
        XCTAssertEqual(shapeLayerCount(layer), 2)
    }

    func testPercentOpacityIsIgnored() throws {
        let layer = try render("<rect width=\"10\" height=\"10\" opacity=\"50%\"/>" + good)
        XCTAssertEqual(shapeLayerCount(layer), 2)
    }

    func testUnknownDisplayValueIsIgnored() throws {
        let layer = try render("<rect width=\"10\" height=\"10\" display=\"banana\"/>" + good)
        XCTAssertEqual(shapeLayerCount(layer), 2)
    }

    func testInheritFontValuesAreIgnored() throws {
        let layer = try render("<rect width=\"10\" height=\"10\" font-style=\"inherit\" font-weight=\"inherit\"/>" + good)
        XCTAssertEqual(shapeLayerCount(layer), 2)
    }

    func testStrokeDashoffsetWithUnitIsParsed() {
        let style = SVGSourceStyleElement()
        try? style.set(attributeDict: ["stroke-dashoffset": "5px"])
        XCTAssertEqual(style.strokeDashoffset, 5)
    }

    func testBrokenUrlReferencesAreSkipped() throws {
        let layer = try render("<rect width=\"10\" height=\"10\" fill=\"url(#nope)\" clip-path=\"url(#nope2)\" mask=\"url(#nope3)\"/>" + good)
        XCTAssertEqual(shapeLayerCount(layer), 2)
    }

    // MARK: Malformed geometry skips only the offending element

    func testRectWithoutDimensionsIsSkipped() throws {
        let layer = try render("<rect x=\"10\"/>" + good)
        XCTAssertEqual(shapeLayerCount(layer), 1)
    }

    func testCircleWithoutRadiusIsSkipped() throws {
        let layer = try render("<circle cx=\"50\" cy=\"50\"/>" + good)
        XCTAssertEqual(shapeLayerCount(layer), 1)
    }

    func testOddPointCountIsSkipped() throws {
        let layer = try render("<polyline points=\"0 0 10\"/>" + good)
        XCTAssertEqual(shapeLayerCount(layer), 1)
    }

    func testEmptyPathDataIsSkipped() throws {
        let layer = try render("<path d=\"\"/>" + good)
        XCTAssertEqual(shapeLayerCount(layer), 1)
    }

    func testBrokenPathDataRendersUpToTheError() throws {
        // The scanner keeps the sub-path parsed before the invalid character (B85).
        let layer = try render("<path d=\"M0 0 L10 10 @\"/>")
        XCTAssertEqual(shapeLayerCount(layer), 1)
    }
}
