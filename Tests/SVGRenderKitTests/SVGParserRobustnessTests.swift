import XCTest
@testable import SVGRenderKit

final class SVGParserRobustnessTests: XCTestCase {

    private func rgba(_ c: UIColor) -> [CGFloat] {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return [r, g, b, a]
    }

    private func assertColor(_ c: UIColor, _ expected: [CGFloat], file: StaticString = #filePath, line: UInt = #line) {
        let got = rgba(c)
        for (g, e) in zip(got, expected) { XCTAssertEqual(g, e, accuracy: 0.01, file: file, line: line) }
    }

    func testIndianRedAndIndigoResolve() {
        assertColor(SVGColors.getColor(string: "indianred"), [0xcd / 255.0, 0x5c / 255.0, 0x5c / 255.0, 1])
        assertColor(SVGColors.getColor(string: "indigo"), [0x4b / 255.0, 0, 0x82 / 255.0, 1])
    }

    func testNamedColorsAreCaseInsensitive() {
        assertColor(SVGColors.getColor(string: "RED"), [1, 0, 0, 1])
        assertColor(SVGColors.getColor(string: "Red"), [1, 0, 0, 1])
        assertColor(SVGColors.getColor(string: "RGB(255, 0, 0)"), [1, 0, 0, 1])
    }

    func testSpaceBeforeParenthesis() {
        assertColor(SVGColors.getColor(string: "rgb (0, 255, 0)"), [0, 1, 0, 1])
        assertColor(SVGColors.getColor(string: "hsl (120, 100%, 50%)"), [0, 1, 0, 1])
    }

    func testRGBComponentsAreClamped() {
        assertColor(SVGColors.getColor(string: "rgb(300, -5, 0)"), [1, 0, 0, 1])
        assertColor(SVGColors.getColor(string: "rgba(0, 0, 0, 2)"), [0, 0, 0, 1])
        assertColor(SVGColors.getColor(string: "argb(2, 255, 0, 0)"), [1, 0, 0, 1])
    }

    func testHSLHueWrapsAndComponentsClamp() {
        let a = rgba(SVGColors.getColor(string: "hsl(180, 100%, 50%)"))
        XCTAssertEqual(rgba(SVGColors.getColor(string: "hsl(540, 100%, 50%)")), a)
        XCTAssertEqual(rgba(SVGColors.getColor(string: "hsl(-180, 100%, 50%)")), a)
        assertColor(SVGColors.getColor(string: "hsl(0, 200%, 150%)"), [1, 1, 1, 1])
    }

    func testPaintTrimsWhitespaceAndIgnoresCase() throws {
        guard case .none = try SVGPaint.get(string: " none ") else { return XCTFail() }
        guard case .none = try SVGPaint.get(string: "NONE") else { return XCTFail() }
        guard case .currentColor = try SVGPaint.get(string: " currentcolor ") else { return XCTFail() }
        guard case .color(let c) = try SVGPaint.get(string: " #ff0000 ") else { return XCTFail() }
        assertColor(c, [1, 0, 0, 1])
        guard case .color(let n) = try SVGPaint.get(string: " Blue ") else { return XCTFail() }
        assertColor(n, [0, 0, 1, 1])
    }

    private func layer(_ body: String) throws -> CALayer {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\">\(body)</svg>"
        return try SVGParser(svgString: svg, parsedRoot: nil).getLayer(overrideElements: nil)
    }

    func testTextPositionWithListAndUnitsDoesNotThrow() throws {
        _ = try layer("<text x=\"10 20 30\" y=\"5\">a</text>")
        _ = try layer("<text x=\"10px\" y=\"50%\">a</text>")
        _ = try layer("<text x=\"abc\">a</text>")
    }

    func testMultipleClassesAllApplyStyles() throws {
        let root = try layer("""
        <style>.a{fill:#ff0000}.b{stroke:#0000ff}</style>
        <rect class="a b" width="10" height="10"/>
        """)
        func shape(_ l: CALayer) -> CAShapeLayer? {
            if let s = l as? CAShapeLayer, s.path != nil { return s }
            for sub in l.sublayers ?? [] { if let f = shape(sub) { return f } }
            return nil
        }
        let s = try XCTUnwrap(shape(root))
        assertColor(UIColor(cgColor: try XCTUnwrap(s.fillColor)), [1, 0, 0, 1])
        assertColor(UIColor(cgColor: try XCTUnwrap(s.strokeColor)), [0, 0, 1, 1])
    }
}
