import XCTest
@testable import SVGRenderKit

final class SVGCurrentColorTests: XCTestCase {

    private func findFilledShapeLayer(in layer: CALayer) -> CAShapeLayer? {
        if let shape = layer as? CAShapeLayer, shape.path != nil, shape.fillColor != nil {
            return shape
        }
        for sublayer in layer.sublayers ?? [] {
            if let found = findFilledShapeLayer(in: sublayer) {
                return found
            }
        }
        return nil
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

    private func assertColor(_ color: CGColor?, red: CGFloat, green: CGFloat, blue: CGFloat,
                             file: StaticString = #filePath, line: UInt = #line) {
        guard let color = color else {
            return XCTFail("expected a color, got nil", file: file, line: line)
        }
        let ui = UIColor(cgColor: color)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else {
            return XCTFail("could not extract color components", file: file, line: line)
        }
        XCTAssertEqual(r, red, accuracy: 1e-3, file: file, line: line)
        XCTAssertEqual(g, green, accuracy: 1e-3, file: file, line: line)
        XCTAssertEqual(b, blue, accuracy: 1e-3, file: file, line: line)
    }

    // MARK: Parsing

    func testColorParsed() throws {
        let style = SVGSourceStyleElement()
        try style.set(attributeDict: ["color": "#ff0000"])
        assertColor(style.color?.cgColor, red: 1, green: 0, blue: 0)
    }

    func testColorInheritLeavesNil() throws {
        let style = SVGSourceStyleElement()
        try style.set(attributeDict: ["color": "inherit"])
        XCTAssertNil(style.color)
    }

    // MARK: currentColor resolution

    func testCurrentColorUsesColorProperty() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <rect width="100" height="100" color="#00ff00" fill="currentColor"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let shape = try XCTUnwrap(findFilledShapeLayer(in: layer))
        assertColor(shape.fillColor, red: 0, green: 1, blue: 0)
    }

    func testCurrentColorDefaultsToBlack() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <rect width="100" height="100" fill="currentColor"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let shape = try XCTUnwrap(findFilledShapeLayer(in: layer))
        assertColor(shape.fillColor, red: 0, green: 0, blue: 0)
    }

    func testCurrentColorInheritedFromGroup() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <g color="#0000ff">
                <rect width="100" height="100" fill="currentColor"/>
            </g>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let shape = try XCTUnwrap(findFilledShapeLayer(in: layer))
        assertColor(shape.fillColor, red: 0, green: 0, blue: 1)
    }

    func testCurrentColorStroke() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <line x1="0" y1="0" x2="100" y2="100" stroke="currentColor" stroke-width="2" color="#ff0000"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let shape = try XCTUnwrap(findStrokedShapeLayer(in: layer))
        assertColor(shape.strokeColor, red: 1, green: 0, blue: 0)
    }

    // MARK: Re-coloring must not break

    func testOverrideWinsOverCurrentColor() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <rect id="box" width="100" height="100" fill="currentColor"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let override = SVGSourceStyleElement(fill: UIColor.blue, stroke: nil, strokeWidth: nil)
        let layer = try parser.getLayer(overrideElements: ["#box": override])
        let shape = try XCTUnwrap(findFilledShapeLayer(in: layer))
        assertColor(shape.fillColor, red: 0, green: 0, blue: 1)
    }
}
