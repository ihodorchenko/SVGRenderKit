import XCTest
@testable import SVGRenderKit

/// B127 — `<text>` runs: whitespace between a text node and a `<tspan>`, text after `</tspan>`,
/// `<tspan>` styles, and the render-scale dependency of the glyph bitmap.
final class SVGTextRunsTests: XCTestCase {

    private func textLayers(_ layer: CALayer) -> [CATextLayer] {
        var out: [CATextLayer] = []
        if let t = layer as? CATextLayer { out.append(t) }
        for s in layer.sublayers ?? [] { out += textLayers(s) }
        return out
    }

    private func render(_ body: String) throws -> (CALayer, SVGParser) {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 200 100\">\(body)</svg>"
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        return (try parser.getLayer(overrideElements: nil), parser)
    }

    private func str(_ l: CATextLayer) -> String { (l.string as? NSAttributedString)?.string ?? "" }
    private func attr(_ l: CATextLayer) -> [NSAttributedString.Key: Any] {
        (l.string as? NSAttributedString)?.attributes(at: 0, effectiveRange: nil) ?? [:]
    }
    private func originX(_ l: CATextLayer) -> CGFloat { l.transform.m41 }

    func testSpaceBeforeTspanSurvives() throws {
        let (layer, _) = try render("<text x=\"10\" y=\"20\">Hello <tspan>world</tspan></text>")
        let joined = textLayers(layer).map(str).joined()
        XCTAssertEqual(joined, "Hello world")
    }

    func testTextAfterTspanIsPlacedAfterIt() throws {
        let (layer, _) = try render("<text x=\"10\" y=\"20\">A<tspan>B</tspan>C</text>")
        let layers = textLayers(layer)
        XCTAssertEqual(layers.map(str), ["A", "B", "C"])
        XCTAssertLessThan(originX(layers[0]), originX(layers[1]))
        XCTAssertLessThan(originX(layers[1]), originX(layers[2]))
    }

    func testWhitespaceAroundTspanCollapsesToOneSpace() throws {
        let (layer, _) = try render("<text>  one \n  <tspan> two </tspan>  three  </text>")
        XCTAssertEqual(textLayers(layer).map(str).joined(), "one two three")
    }

    func testTspanFillAndWeightOverrideText() throws {
        let (layer, _) = try render("<text x=\"10\" y=\"20\" fill=\"#000000\">a<tspan fill=\"#ff0000\" font-weight=\"700\">b</tspan></text>")
        let layers = textLayers(layer)
        XCTAssertEqual(layers.count, 2)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        (attr(layers[1])[.foregroundColor] as? UIColor)?.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(r, 1, accuracy: 0.01)
        XCTAssertEqual(g, 0, accuracy: 0.01)
        let outer = attr(layers[0])[.font] as? UIFont
        let inner = attr(layers[1])[.font] as? UIFont
        XCTAssertNotEqual(outer?.fontName, inner?.fontName, "bold tspan uses a different face")
    }

    func testTspanInheritsTextStyleWhenUnset() throws {
        let (layer, _) = try render("<text fill=\"#00ff00\" font-size=\"30\">a<tspan>b</tspan></text>")
        let layers = textLayers(layer)
        var g: CGFloat = 0
        (attr(layers[1])[.foregroundColor] as? UIColor)?.getRed(nil, green: &g, blue: nil, alpha: nil)
        XCTAssertEqual(g, 1, accuracy: 0.01)
        XCTAssertEqual((attr(layers[1])[.font] as? UIFont)?.pointSize, 30)
    }

    func testTextMakesDocumentScaleDependent() throws {
        let (_, parser) = try render("<text x=\"1\" y=\"5\">Hi</text>")
        XCTAssertTrue(parser.root.getSvgOptions().usesMasks, "glyph bitmap depends on renderScale, so a resize must re-render")
    }
}
