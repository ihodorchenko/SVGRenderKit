import XCTest
import UIKit
@testable import SVGRenderKit

/// B113 — the parser cache is keyed by a full digest of the content, not a fixed-width
/// `hashValue`, so a hash collision can never return a foreign parsed tree.
final class SVGParserCacheKeyTests: XCTestCase {

    private let red = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 10 10\"><rect width=\"10\" height=\"10\" fill=\"#ff0000\"/></svg>"
    private let blue = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 10 10\"><rect width=\"10\" height=\"10\" fill=\"#0000ff\"/></svg>"

    override func setUp() {
        super.setUp()
        SVGCache.s.isSVGParserUseCache = true
    }

    func testStringCacheDoesNotReturnStaleTreeForSameName() throws {
        let name = "cache-string-\(UUID().uuidString)"
        let a = try SVGParser.getParser(svgString: red, name: name)
        let b = try SVGParser.getParser(svgString: blue, name: name)
        XCTAssertFalse(a.root === b.root)
        let again = try SVGParser.getParser(svgString: red, name: name)
        XCTAssertTrue(a.root === again.root, "identical name+content should hit the cache")
    }

    func testDataCacheDoesNotReturnStaleTreeForSameName() throws {
        let name = "cache-data-\(UUID().uuidString)"
        let a = try SVGParser.getParser(svgData: Data(red.utf8), name: name)
        let b = try SVGParser.getParser(svgData: Data(blue.utf8), name: name)
        XCTAssertFalse(a.root === b.root)
        let again = try SVGParser.getParser(svgData: Data(red.utf8), name: name)
        XCTAssertTrue(a.root === again.root, "identical name+content should hit the cache")
    }

    // B114: a color is resolved while parsing, so changing overrides must drop cached trees.
    func testColorOverrideChangeInvalidatesTheParserCache() throws {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 10 10\"><rect width=\"10\" height=\"10\" fill=\"#ff0000\"/></svg>"
        let name = "override-\(UUID().uuidString)"
        SVGColors.setOvverideColors(colors: [:])
        defer { SVGColors.setOvverideColors(colors: [:]) }
        _ = try SVGParser.getParser(svgString: svg, name: name).getLayer(overrideElements: nil)

        SVGColors.setOvverideColors(colors: ["#ff0000": "#00ff00"])
        let layer = try SVGParser.getParser(svgString: svg, name: name).getLayer(overrideElements: nil)

        let color = UIColor(cgColor: try XCTUnwrap(firstShape(in: layer)?.fillColor))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(g, 1, accuracy: 0.01)
        XCTAssertEqual(r, 0, accuracy: 0.01)
    }

    private func firstShape(in layer: CALayer) -> CAShapeLayer? {
        if let shape = layer as? CAShapeLayer, shape.path != nil { return shape }
        for sub in layer.sublayers ?? [] { if let found = firstShape(in: sub) { return found } }
        return nil
    }
}
