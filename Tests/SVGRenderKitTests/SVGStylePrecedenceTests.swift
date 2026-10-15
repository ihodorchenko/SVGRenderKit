import XCTest
@testable import SVGRenderKit

final class SVGStylePrecedenceTests: XCTestCase {

    private func root(_ body: String) throws -> CALayer {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\">\(body)</svg>"
        return try SVGParser(svgString: svg, parsedRoot: nil).getLayer(overrideElements: nil)
    }

    /// The first layer that actually carries path geometry (container layers have a default black fill).
    private func firstShape(_ l: CALayer) -> CAShapeLayer? {
        if let s = l as? CAShapeLayer, s.path != nil { return s }
        for sub in l.sublayers ?? [] { if let f = firstShape(sub) { return f } }
        return nil
    }

    private func fill(_ body: String) throws -> UIColor {
        let l = try root(body)
        let shape = try XCTUnwrap(firstShape(l))
        return UIColor(cgColor: try XCTUnwrap(shape.fillColor))
    }

    private func texts(_ l: CALayer) -> [CATextLayer] {
        var out: [CATextLayer] = []
        if let t = l as? CATextLayer { out.append(t) }
        for s in l.sublayers ?? [] { out += texts(s) }
        return out
    }

    private func assertColor(_ c: UIColor, _ r: CGFloat, _ g: CGFloat, _ b: CGFloat, file: StaticString = #filePath, line: UInt = #line) {
        var rr: CGFloat = 0, gg: CGFloat = 0, bb: CGFloat = 0, aa: CGFloat = 0
        c.getRed(&rr, green: &gg, blue: &bb, alpha: &aa)
        XCTAssertEqual(rr, r, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(gg, g, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(bb, b, accuracy: 0.01, file: file, line: line)
    }

    func testStyleBlockBeatsPresentationAttribute() throws {
        let c = try fill("<style>.foo{fill:#ff0000}</style><rect class=\"foo\" fill=\"#0000ff\" width=\"10\" height=\"10\"/>")
        assertColor(c, 1, 0, 0)
    }

    func testInlineStyleBeatsStyleBlock() throws {
        let c = try fill("<style>.foo{fill:#ff0000}</style><rect class=\"foo\" style=\"fill:#00ff00\" width=\"10\" height=\"10\"/>")
        assertColor(c, 0, 1, 0)
    }

    func testInlineStyleBeatsPresentationAttributeOnSameElement() throws {
        let c = try fill("<rect fill=\"#0000ff\" style=\"fill:#00ff00\" width=\"10\" height=\"10\"/>")
        assertColor(c, 0, 1, 0)
    }

    func testPresentationAttributeBeatsInheritedStyle() throws {
        let c = try fill("<g fill=\"#ff0000\"><rect fill=\"#0000ff\" width=\"10\" height=\"10\"/></g>")
        assertColor(c, 0, 0, 1)
    }

    // MARK: B109 — inline style parsing

    func testInlineStyleLastDuplicateWins() throws {
        let c = try fill("<rect width=\"10\" height=\"10\" style=\"fill:#ff0000;fill:#00ff00\"/>")
        assertColor(c, 0, 1, 0)
    }

    func testInlineStyleImportantSuffixIsIgnored() throws {
        let c = try fill("<rect width=\"10\" height=\"10\" style=\"fill:#00ff00 !important\"/>")
        assertColor(c, 0, 1, 0)
    }

    func testPatternInheritedFillDoesNotOverrideShapeAttribute() throws {
        let c = try fill("<defs><clipPath id=\"c\" fill=\"#ff0000\"><rect fill=\"#0000ff\" width=\"10\" height=\"10\"/></clipPath></defs><rect width=\"5\" height=\"5\" fill=\"#00ff00\"/>")
        assertColor(c, 0, 1, 0)
    }

    func testTextFillColorAndNone() throws {
        let t = try XCTUnwrap(texts(try root("<text x=\"1\" y=\"10\" fill=\"#ff0000\">a</text>")).first)
        let attr = try XCTUnwrap(t.string as? NSAttributedString)
        let color = try XCTUnwrap(attr.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor)
        assertColor(color, 1, 0, 0)
        XCTAssertTrue(texts(try root("<text x=\"1\" y=\"10\" fill=\"none\">a</text>")).isEmpty)
    }

    func testTextCurrentColorOpacityAndFillOpacity() throws {
        let l = try root("<text x=\"1\" y=\"10\" color=\"#0000ff\" fill=\"currentColor\" fill-opacity=\"0.5\" opacity=\"0.4\">a</text>")
        let t = try XCTUnwrap(texts(l).first)
        let attr = try XCTUnwrap(t.string as? NSAttributedString)
        let color = try XCTUnwrap(attr.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor)
        assertColor(color, 0, 0, 1)
        var a: CGFloat = 0
        color.getRed(nil, green: nil, blue: nil, alpha: &a)
        XCTAssertEqual(a, 0.5, accuracy: 0.01)
        XCTAssertEqual(t.superlayer?.opacity ?? 0, 0.4, accuracy: 0.01)
    }

    func testTspanContinuesAfterPrecedingText() throws {
        let l = try root("<text x=\"10\" y=\"20\">Hello<tspan dx=\"5\">World</tspan></text>")
        let ts = texts(l)
        XCTAssertEqual(ts.count, 2)
        let first = ts[0], second = ts[1]
        XCTAssertEqual(second.transform.m41, first.transform.m41 + first.bounds.width + 5, accuracy: 0.5)
    }
}
