import XCTest
@testable import SVGRenderKit

final class SVGTextLayoutTests: XCTestCase {

    private func findTextLayers(in layer: CALayer) -> [CATextLayer] {
        var result: [CATextLayer] = []
        if let textLayer = layer as? CATextLayer {
            result.append(textLayer)
        }
        for sublayer in layer.sublayers ?? [] {
            result.append(contentsOf: findTextLayers(in: sublayer))
        }
        return result
    }

    private func textStrings(_ svg: String) throws -> [String] {
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        return findTextLayers(in: layer).map { layer -> String in
            if let attributed = layer.string as? NSAttributedString {
                return attributed.string
            }
            return layer.string as? String ?? ""
        }
    }

    private func firstTextLayer(_ svg: String) throws -> CATextLayer {
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        return try XCTUnwrap(findTextLayers(in: layer).first)
    }

    private func font(of layer: CATextLayer) throws -> UIFont {
        let attributed = try XCTUnwrap(layer.string as? NSAttributedString)
        return try XCTUnwrap(attributed.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
    }

    // MARK: tspan

    func testMultilineTspanRendersAllLines() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <text x="10" y="20">
                <tspan x="10" y="20">Line1</tspan>
                <tspan x="10" y="40">Line2</tspan>
            </text>
        </svg>
        """
        let strings = try textStrings(svg)
        XCTAssertEqual(strings, ["Line1", "Line2"])
    }

    func testTspanWithDxDyOffsets() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <text x="10" y="20">
                <tspan dx="5" dy="10">Line</tspan>
            </text>
        </svg>
        """
        let layer = try firstTextLayer(svg)
        let font = try font(of: layer)
        XCTAssertEqual(layer.transform.m41, 15, accuracy: 0.0001)
        // y=20 + dy=10, baseline-corrected by the font ascent.
        XCTAssertEqual(layer.transform.m42, 30 - font.ascender, accuracy: 0.0001)
    }

    // MARK: frame / anchor / baseline (T49)

    func testTextLayerHasNonZeroFrame() throws {
        let layer = try firstTextLayer("""
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><text x="10" y="20">Hi</text></svg>
        """)
        XCTAssertGreaterThan(layer.frame.width, 0)
        XCTAssertGreaterThan(layer.frame.height, 0)
    }

    func testTextLayerAnchorPointIsTopLeft() throws {
        let layer = try firstTextLayer("""
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><text x="10" y="20">Hi</text></svg>
        """)
        XCTAssertEqual(layer.anchorPoint.x, 0, accuracy: 0.0001)
        XCTAssertEqual(layer.anchorPoint.y, 0, accuracy: 0.0001)
    }

    func testTextBaselineAdjustedToY() throws {
        let layer = try firstTextLayer("""
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><text x="0" y="20">Hi</text></svg>
        """)
        let font = try font(of: layer)
        XCTAssertEqual(layer.transform.m42, 20 - font.ascender, accuracy: 0.0001)
    }

    // MARK: text-anchor

    func testTextAnchorStartNoShift() throws {
        let layer = try firstTextLayer("""
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><text x="50" y="20" text-anchor="start">Hi</text></svg>
        """)
        XCTAssertEqual(layer.transform.m41, 50, accuracy: 0.0001)
    }

    func testTextAnchorMiddleShiftsLeft() throws {
        let layer = try firstTextLayer("""
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><text x="50" y="20" text-anchor="middle">Hi</text></svg>
        """)
        XCTAssertLessThan(layer.transform.m41, 50)
    }

    func testTextAnchorEndShiftsFurtherLeft() throws {
        let start = try firstTextLayer("""
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><text x="50" y="20" text-anchor="start">Hi</text></svg>
        """)
        let end = try firstTextLayer("""
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><text x="50" y="20" text-anchor="end">Hi</text></svg>
        """)
        XCTAssertLessThan(end.transform.m41, start.transform.m41)
    }

    // B106: `text-anchor` from the inline `style` (or a `<style>` rule) must win over the default.
    func testTextAnchorFromInlineStyle() throws {
        let layer = try firstTextLayer("""
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><text x="50" y="20" style="text-anchor:middle">Hi</text></svg>
        """)
        XCTAssertLessThan(layer.transform.m41, 50)
    }
}
