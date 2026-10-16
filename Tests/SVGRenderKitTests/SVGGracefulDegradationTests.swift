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

    /// The first shape layer (in document order) and its fill / the layer opacity above it.
    private func firstShape(_ layer: CALayer) -> CAShapeLayer? {
        if let shape = layer as? CAShapeLayer, shape.path != nil { return shape }
        for sublayer in layer.sublayers ?? [] { if let found = firstShape(sublayer) { return found } }
        return nil
    }

    private func alpha(_ color: CGColor?) -> CGFloat { color?.alpha ?? -1 }

    func testTransparentFillIsAValidColourAndPaintsNothing() throws {
        let layer = try render("<rect width=\"10\" height=\"10\" fill=\"transparent\"/>" + good)
        XCTAssertEqual(shapeLayerCount(layer), 2)
        XCTAssertEqual(alpha(firstShape(layer)?.fillColor), 0, accuracy: 0.001)
    }

    func testUnknownPaintValueIsIgnoredAndTheDefaultFillRemains() throws {
        let layer = try render("<rect width=\"10\" height=\"10\" fill=\"banana\"/>" + good)
        XCTAssertEqual(shapeLayerCount(layer), 2)
        XCTAssertEqual(alpha(firstShape(layer)?.fillColor), 1, accuracy: 0.001, "default black fill, not clear")
    }

    func testInheritAndContextPaintValuesAreIgnored() throws {
        let layer = try render("<rect width=\"10\" height=\"10\" fill=\"inherit\" stroke=\"context-fill\"/>" + good)
        XCTAssertEqual(shapeLayerCount(layer), 2)
    }

    func testOutOfRangeOpacityIsClampedAndNonNumericFillOpacityIgnored() throws {
        let layer = try render("<rect width=\"10\" height=\"10\" opacity=\"1.2\" fill-opacity=\"abc\"/>" + good)
        XCTAssertEqual(shapeLayerCount(layer), 2)
        let shape = try XCTUnwrap(firstShape(layer))
        XCTAssertEqual(alpha(shape.fillColor), 1, accuracy: 0.001, "an unparsable fill-opacity leaves the fill opaque")
        XCTAssertEqual(shape.opacity, 1, accuracy: 0.001, "opacity 1.2 clamps to 1")
    }

    func testPercentOpacityIsApplied() throws {
        let layer = try render("<rect width=\"10\" height=\"10\" opacity=\"50%\"/>" + good)
        XCTAssertEqual(shapeLayerCount(layer), 2)
        var found: [Float] = []
        func collect(_ l: CALayer) { if l.opacity != 1 { found.append(l.opacity) }; l.sublayers?.forEach(collect) }
        collect(layer)
        XCTAssertEqual(found.first ?? -1, 0.5, accuracy: 0.001, "50% opacity is 0.5 (CSS Color 4)")
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
