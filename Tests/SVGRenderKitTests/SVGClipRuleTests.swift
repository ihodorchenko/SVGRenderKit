import XCTest
@testable import SVGRenderKit

final class SVGClipRuleTests: XCTestCase {

    private func findMaskedLayer(in layer: CALayer) -> CALayer? {
        if layer.mask != nil {
            return layer
        }
        for sublayer in layer.sublayers ?? [] {
            if let found = findMaskedLayer(in: sublayer) {
                return found
            }
        }
        return nil
    }

    // MARK: Parsing

    func testClipRuleParsed() throws {
        let style = SVGSourceStyleElement()
        try style.set(attributeDict: ["clip-rule": "evenodd"])
        let rule = try XCTUnwrap(style.clipRule)
        XCTAssertEqual(rule, .evenodd)
    }

    func testClipRuleDefaultIsNil() throws {
        let style = SVGSourceStyleElement()
        try style.set(attributeDict: ["fill": "#ff0000"])
        XCTAssertNil(style.clipRule)
    }

    private func pathLayers(in layer: CALayer) -> [CAShapeLayer] {
        var out: [CAShapeLayer] = []
        if let s = layer as? CAShapeLayer, s.path != nil { out.append(s) }
        for sub in layer.sublayers ?? [] { out += pathLayers(in: sub) }
        return out
    }

    // MARK: Applied to mask

    func testClipRuleOnClipPathChildAppliedToMask() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>
                <clipPath id="c"><rect x="0" y="0" width="50" height="50" clip-rule="evenodd"/></clipPath>
            </defs>
            <rect width="100" height="100" fill="#ff0000" clip-path="url(#c)"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let masked = try XCTUnwrap(findMaskedLayer(in: layer))
        let mask = try XCTUnwrap(masked.mask)
        // `clip-rule` on a clipPath child drives that child's winding rule.
        let paths = pathLayers(in: mask)
        XCTAssertFalse(paths.isEmpty)
        for p in paths { XCTAssertEqual(p.fillRule.rawValue, CAShapeLayerFillRule.evenOdd.rawValue) }
    }

    func testClipRuleDefaultsToNonZero() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>
                <clipPath id="c"><rect x="0" y="0" width="50" height="50"/></clipPath>
            </defs>
            <rect width="100" height="100" fill="#ff0000" clip-path="url(#c)"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let masked = try XCTUnwrap(findMaskedLayer(in: layer))
        let mask = try XCTUnwrap(masked.mask)
        let paths = pathLayers(in: mask)
        XCTAssertFalse(paths.isEmpty)
        for p in paths { XCTAssertEqual(p.fillRule.rawValue, CAShapeLayerFillRule.nonZero.rawValue) }
    }
}
