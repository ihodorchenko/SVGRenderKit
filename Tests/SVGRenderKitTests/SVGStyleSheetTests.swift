import XCTest
@testable import SVGRenderKit

/// M1 — the document-wide stylesheet: selectors (compound, descendant, universal), the cascade
/// (specificity, source order, `!important`), stylesheets inside containers, CSS paint references
/// and CSS animations reached through a descendant selector.
final class SVGStyleSheetTests: XCTestCase {

    // MARK: Helpers

    private func layer(_ body: String) throws -> CALayer {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\">\(body)</svg>"
        return try SVGParser(svgString: svg, parsedRoot: nil).getLayer(overrideElements: nil)
    }

    private func shapes(_ layer: CALayer) -> [CAShapeLayer] {
        var result: [CAShapeLayer] = []
        if let shape = layer as? CAShapeLayer, shape.path != nil { result.append(shape) }
        for sublayer in layer.sublayers ?? [] { result += shapes(sublayer) }
        return result
    }

    private func fills(_ body: String) throws -> [UIColor] {
        return shapes(try layer(body)).map { UIColor(cgColor: $0.fillColor ?? UIColor.clear.cgColor) }
    }

    private func assertColor(_ color: UIColor, _ r: CGFloat, _ g: CGFloat, _ b: CGFloat,
                             file: StaticString = #filePath, line: UInt = #line) {
        var rr: CGFloat = 0, gg: CGFloat = 0, bb: CGFloat = 0, aa: CGFloat = 0
        color.getRed(&rr, green: &gg, blue: &bb, alpha: &aa)
        XCTAssertEqual(rr, r, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(gg, g, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(bb, b, accuracy: 0.01, file: file, line: line)
    }

    // MARK: Document-wide registry

    func testStyleAfterTheElementStillApplies() throws {
        let colors = try fills("""
        <rect width="10" height="10" class="late"/>
        <style>.late{fill:#ff0000}</style>
        """)
        assertColor(try XCTUnwrap(colors.first), 1, 0, 0)
    }

    func testStyleInsideDefsAppliesToTheWholeDocument() throws {
        let colors = try fills("""
        <defs><style>.brand{fill:#0000ff}</style></defs>
        <rect width="10" height="10" class="brand"/>
        """)
        assertColor(try XCTUnwrap(colors.first), 0, 0, 1)
    }

    func testStyleInsideMaskAppliesToTheWholeDocument() throws {
        let colors = try fills("""
        <defs><mask id="m"><style>.masked-brand{fill:#00ff00}</style><rect width="5" height="5"/></mask></defs>
        <rect width="10" height="10" class="masked-brand"/>
        """)
        assertColor(try XCTUnwrap(colors.first), 0, 1, 0)
    }

    // MARK: Selectors

    func testDescendantSelector() throws {
        let colors = try fills("""
        <style>.wrap path{fill:#ff0000}</style>
        <g class="wrap"><path d="M0 0h10v10z"/></g>
        <path d="M0 0h10v10z"/>
        """)
        XCTAssertEqual(colors.count, 2)
        assertColor(colors[0], 1, 0, 0)
        assertColor(colors[1], 0, 0, 0)
    }

    func testDescendantSelectorAcrossSeveralLevels() throws {
        let colors = try fills("""
        <style>.a .b path{fill:#00ff00}</style>
        <g class="a"><g class="b"><path d="M0 0h10v10z"/></g></g>
        """)
        assertColor(try XCTUnwrap(colors.first), 0, 1, 0)
    }

    func testCompoundSelectors() throws {
        let colors = try fills("""
        <style>
            path.foo{fill:#ff0000}
            #bar.foo{fill:#0000ff}
            rect.baz#qux{fill:#00ff00}
        </style>
        <path class="foo" d="M0 0h10v10z"/>
        <path id="bar" class="foo" d="M0 0h10v10z"/>
        <rect id="qux" class="baz" width="10" height="10"/>
        """)
        XCTAssertEqual(colors.count, 3)
        assertColor(colors[0], 1, 0, 0)
        assertColor(colors[1], 0, 0, 1)
        assertColor(colors[2], 0, 1, 0)
    }

    func testUniversalSelector() throws {
        let colors = try fills("""
        <style>*{fill:#ff0000}</style>
        <rect width="10" height="10"/>
        <path d="M0 0h10v10z" fill="#0000ff"/>
        """)
        XCTAssertEqual(colors.count, 2)
        assertColor(colors[0], 1, 0, 0)
        // A rule (even `*`) outranks a presentation attribute, so both shapes are red.
        assertColor(colors[1], 1, 0, 0)
    }

    func testDescendantSelectorDoesNotMatchOutsideTheAncestor() throws {
        let colors = try fills("""
        <style>.wrap path{fill:#ff0000}</style>
        <g class="wrap"><path d="M0 0h10v10z"/></g>
        <g><path d="M0 0h10v10z"/></g>
        """)
        XCTAssertEqual(colors.count, 2)
        assertColor(colors[0], 1, 0, 0)
        assertColor(colors[1], 0, 0, 0)
    }

    func testUnsupportedSelectorsAreDropped() throws {
        let colors = try fills("""
        <style>
            g > path{fill:#ff0000}
            path:first-child{fill:#0000ff}
            path[data-x]{fill:#00ff00}
        </style>
        <g><path d="M0 0h10v10z"/></g>
        """)
        assertColor(try XCTUnwrap(colors.first), 0, 0, 0)
    }

    // MARK: Cascade

    func testIdOutranksClassAndClassOutranksTag() throws {
        let colors = try fills("""
        <style>
            path{fill:#ff0000}
            .a{fill:#0000ff}
            #b{fill:#00ff00}
        </style>
        <path id="b" class="a" d="M0 0h10v10z"/>
        """)
        assertColor(try XCTUnwrap(colors.first), 0, 1, 0)
    }

    func testMoreClassesWin() throws {
        let colors = try fills("""
        <style>
            .a{fill:#ff0000}
            .a.b{fill:#0000ff}
        </style>
        <path class="a b" d="M0 0h10v10z"/>
        """)
        assertColor(try XCTUnwrap(colors.first), 0, 0, 1)
    }

    func testLaterRuleWinsAtEqualSpecificity() throws {
        let colors = try fills("""
        <style>
            .a{fill:#ff0000}
            .b{fill:#0000ff}
        </style>
        <path class="a b" d="M0 0h10v10z"/>
        """)
        assertColor(try XCTUnwrap(colors.first), 0, 0, 1)
    }

    func testLaterStylesheetWinsAtEqualSpecificity() throws {
        let colors = try fills("""
        <style>.a{fill:#ff0000}</style>
        <style>.a{fill:#0000ff}</style>
        <path class="a" d="M0 0h10v10z"/>
        """)
        assertColor(try XCTUnwrap(colors.first), 0, 0, 1)
    }

    func testImportantRuleBeatsHigherSpecificityNormalRule() throws {
        let colors = try fills("""
        <style>
            #b{fill:#0000ff}
            path{fill:#ff0000 !important}
        </style>
        <path id="b" d="M0 0h10v10z"/>
        """)
        assertColor(try XCTUnwrap(colors.first), 1, 0, 0)
    }

    func testImportantRuleBeatsNormalInlineStyle() throws {
        let colors = try fills("""
        <style>.a{fill:#ff0000 !important}</style>
        <path class="a" style="fill:#0000ff" d="M0 0h10v10z"/>
        """)
        assertColor(try XCTUnwrap(colors.first), 1, 0, 0)
    }

    func testImportantInlineStyleBeatsImportantRule() throws {
        let colors = try fills("""
        <style>.a{fill:#ff0000 !important}</style>
        <path class="a" style="fill:#00ff00 !important" d="M0 0h10v10z"/>
        """)
        assertColor(try XCTUnwrap(colors.first), 0, 1, 0)
    }

    func testNormalInlineStyleBeatsNormalRule() throws {
        let colors = try fills("""
        <style>.a{fill:#ff0000}</style>
        <path class="a" style="fill:#00ff00" d="M0 0h10v10z"/>
        """)
        assertColor(try XCTUnwrap(colors.first), 0, 1, 0)
    }

    // MARK: Paint and animations through selectors

    func testGradientPaintFromADescendantRule() throws {
        let root = try layer("""
        <defs><linearGradient id="g"><stop offset="0" stop-color="#ff0000"/><stop offset="1" stop-color="#0000ff"/></linearGradient></defs>
        <style>.wrap path{fill:url(#g)}</style>
        <g class="wrap"><path d="M0 0h10v10z"/></g>
        """)
        func gradients(_ layer: CALayer) -> [CAGradientLayer] {
            var result: [CAGradientLayer] = []
            if let gradient = layer as? CAGradientLayer { result.append(gradient) }
            for sublayer in layer.sublayers ?? [] { result += gradients(sublayer) }
            return result
        }
        XCTAssertFalse(gradients(root).isEmpty, "the descendant rule's url(#g) fill resolves to a gradient")
    }

    func testDashoffsetAnimationFromADescendantRule() throws {
        let root = try layer("""
        <style>
            .specimen .draw{animation: draw 1s linear infinite}
            @keyframes draw{0%{stroke-dashoffset:0}100%{stroke-dashoffset:20}}
        </style>
        <g class="specimen"><path class="draw" d="M0 0h10v10z" stroke="#000" fill="none" stroke-dasharray="5 5"/></g>
        """)
        func find(_ layer: CALayer) -> CALayer? {
            if layer.animationKeys()?.contains("lineDashPhase") == true { return layer }
            for sublayer in layer.sublayers ?? [] {
                if let found = find(sublayer) { return found }
            }
            return nil
        }
        XCTAssertNotNil(find(root), "the animation declaration reached the path through a descendant selector")
    }
}
