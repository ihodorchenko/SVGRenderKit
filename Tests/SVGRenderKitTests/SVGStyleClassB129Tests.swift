import XCTest
@testable import SVGRenderKit

/// B129 — `inherit`, presentation-vs-`style` order, CSS colour syntaxes, style-attribute parsing.
@MainActor
final class SVGStyleClassB129Tests: XCTestCase {

    private func parse(_ body: String) throws -> SVGParser {
        try SVGParser(svgString: "<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" viewBox=\"0 0 100 100\">\(body)</svg>", parsedRoot: nil)
    }

    private func rgba(_ c: UIColor) -> [CGFloat] {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return [r, g, b, a].map { ($0 * 100).rounded() / 100 }
    }

    // MARK: inherit

    func testClipRuleInheritKeepsParentRule() {
        let parent = SVGSourceStyleElement(); parent.clipRule = .evenodd
        let child = SVGSourceStyleElement(); child.setClipRule(str: "inherit")
        XCTAssertEqual(parent.combine(child: child).clipRule, .evenodd)
    }

    func testVisibilityInheritAndUnknownKeepParent() {
        let parent = SVGSourceStyleElement(); parent.setVisibility(str: "hidden")
        for value in ["inherit", "bogus"] {
            let child = SVGSourceStyleElement(); child.setVisibility(str: value)
            XCTAssertEqual(parent.combine(child: child).visibility, .hidden, "visibility=\(value)")
        }
    }

    func testTextAnchorInheritKeepsParent() throws {
        let parent = SVGSourceStyleElement(); try parent.set(attributeDict: ["text-anchor": "middle"])
        let child = SVGSourceStyleElement(); try child.set(attributeDict: ["text-anchor": "inherit"])
        XCTAssertEqual(parent.combine(child: child).textAnchor, "middle")
    }

    // MARK: presentation attribute vs inline style

    func testStopInlineStyleBeatsPresentationAttribute() throws {
        let parser = try parse("<defs><linearGradient id=\"g\"><stop offset=\"0\" stop-color=\"#0000ff\" style=\"stop-color:#ff0000\"/></linearGradient></defs><rect width=\"10\" height=\"10\" fill=\"url(#g)\"/>")
        let gradient = try XCTUnwrap(parser.root.svgElement.getGradient(byKey: "g", fromParents: false) as? SVGLinearGradientTag)
        let stop = try XCTUnwrap(gradient.stops.first)
        XCTAssertEqual(rgba(stop.stop_color), [1, 0, 0, 1])
    }

    func testImageInlineStyleBeatsPresentationAttribute() throws {
        let parser = try parse("<image x=\"0\" y=\"0\" width=\"10\" height=\"10\" opacity=\"1\" style=\"opacity:0.5\" href=\"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg==\"/>")
        let layer = try parser.getLayer(overrideElements: nil)
        func find(_ l: CALayer) -> CALayer? {
            if l.opacity != 1 { return l }
            for s in l.sublayers ?? [] { if let f = find(s) { return f } }
            return nil
        }
        XCTAssertEqual(try XCTUnwrap(find(layer)).opacity, 0.5, accuracy: 0.001)
    }

    func testPatternMaskClipMarkerStyleOrder() throws {
        // `display:none` inline must beat the presentation `display="inline"` on every container.
        let parser = try parse("""
        <defs>
        <clipPath id="c" display="inline" style="display:none"><rect width="1" height="1"/></clipPath>
        <mask id="m" display="inline" style="display:none"><rect width="1" height="1"/></mask>
        <pattern id="p" width="1" height="1" display="inline" style="display:none"><rect width="1" height="1"/></pattern>
        <marker id="k" display="inline" style="display:none"><rect width="1" height="1"/></marker>
        </defs>
        """)
        let svg = parser.root.svgElement
        XCTAssertEqual(svg.getClipPath(byKey: "c", fromParents: false)?.sourceStyle?.display, SVGDisplaytype.none)
        XCTAssertEqual(svg.getMask(byKey: "m", fromParents: false)?.sourceStyle?.display, SVGDisplaytype.none)
        XCTAssertEqual(svg.getPattern(byKey: "p", fromParents: false)?.sourceStyle?.display, SVGDisplaytype.none)
        XCTAssertEqual(svg.getMarker(byKey: "k", fromParents: false)?.sourceStyle?.display, SVGDisplaytype.none)
    }

    // MARK: colours

    func testRgbSpaceSyntaxWithSlashAlpha() {
        XCTAssertEqual(rgba(SVGColors.getColor(string: "rgb(255 0 0 / 50%)")), [1, 0, 0, 0.5])
        XCTAssertEqual(rgba(SVGColors.getColor(string: "rgb(255 0 0 / 0.5)")), [1, 0, 0, 0.5])
    }

    func testRgbFourArgumentComma() {
        XCTAssertEqual(rgba(SVGColors.getColor(string: "rgb(255, 0, 0, 0.5)")), [1, 0, 0, 0.5])
    }

    func testHslSpaceSyntax() {
        XCTAssertEqual(rgba(SVGColors.getColor(string: "hsl(0 100% 50%)")), [1, 0, 0, 1])
        XCTAssertEqual(rgba(SVGColors.getColor(string: "hsl(0 100% 50% / 50%)")), [1, 0, 0, 0.5])
    }

    func testInvalidFillDeclarationIsIgnoredNotClear() throws {
        let parser = try parse("<g fill=\"#ff0000\"><rect width=\"10\" height=\"10\" style=\"fill:rgb(1,2)\"/></g>")
        let layer = try parser.getLayer(overrideElements: nil)
        func shape(_ l: CALayer) -> CAShapeLayer? {
            if let s = l as? CAShapeLayer, s.path != nil { return s }
            for c in l.sublayers ?? [] { if let f = shape(c) { return f } }
            return nil
        }
        let fill = try XCTUnwrap(shape(layer)).fillColor
        XCTAssertEqual(rgba(UIColor(cgColor: try XCTUnwrap(fill))), [1, 0, 0, 1], "an invalid declaration is dropped, the inherited fill stays")
    }

    // MARK: style attribute parsing

    func testStyleCommentsAreStripped() {
        let d = SVGSourceStyleElement.declarations(from: "fill: red /* c ; x:y */; /* a */ stroke : blue")
        XCTAssertEqual(d["fill"], "red")
        XCTAssertEqual(d["stroke"], "blue")
        XCTAssertEqual(d.count, 2)
    }

    func testSemicolonInsideUrlDataIsNotASeparator() {
        let d = SVGSourceStyleElement.declarations(from: "background:url(data:image/png;base64,AAAA);opacity:0.5")
        XCTAssertEqual(d["background"], "url(data:image/png;base64,AAAA)")
        XCTAssertEqual(d["opacity"], "0.5")
    }

    // MARK: <use> offsets

    func testUsePercentOffsetIsRelativeToViewport() throws {
        let parser = try parse("<defs><rect id=\"r\" width=\"10\" height=\"10\" fill=\"#000\"/></defs><use href=\"#r\" x=\"50%\" y=\"10%\"/>")
        let layer = try parser.getLayer(overrideElements: nil)
        func shifted(_ l: CALayer) -> CGAffineTransform? {
            let t = l.transform
            if t.m41 != 0 || t.m42 != 0 { return CATransform3DGetAffineTransform(t) }
            for c in l.sublayers ?? [] { if let f = shifted(c) { return f } }
            return nil
        }
        let t = try XCTUnwrap(shifted(layer))
        XCTAssertEqual(t.tx, 50, accuracy: 0.01)
        XCTAssertEqual(t.ty, 10, accuracy: 0.01)
    }
}
