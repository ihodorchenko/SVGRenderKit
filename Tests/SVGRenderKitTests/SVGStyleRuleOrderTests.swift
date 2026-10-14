import XCTest
@testable import SVGRenderKit

/// B90 — a `<style>` block keeps rule order, accumulates repeated selectors, strips
/// `/* … */` comments and skips `@media`; it is no longer a `[String: String]`.
final class SVGStyleRuleOrderTests: XCTestCase {

    private func render(_ body: String) throws -> CALayer {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\">\(body)</svg>"
        return try SVGParser(svgString: svg, parsedRoot: nil).getLayer(overrideElements: nil)
    }

    private func firstShape(_ layer: CALayer) -> CAShapeLayer? {
        if let shape = layer as? CAShapeLayer, shape.path != nil { return shape }
        for sub in layer.sublayers ?? [] {
            if let found = firstShape(sub) { return found }
        }
        return nil
    }

    private func rgb(_ cgColor: CGColor?) -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
        guard let cgColor = cgColor, let comps = cgColor.components, comps.count >= 3 else { return nil }
        return (comps[0], comps[1], comps[2])
    }

    private func allFills(_ layer: CALayer) -> [CGColor] {
        var result: [CGColor] = []
        if let shape = layer as? CAShapeLayer, shape.path != nil, let fill = shape.fillColor { result.append(fill) }
        for sub in layer.sublayers ?? [] { result.append(contentsOf: allFills(sub)) }
        return result
    }

    func testRepeatedSelectorAccumulatesDeclarations() throws {
        // The second `.a` rule only sets fill; the first rule's stroke must survive.
        let layer = try render("""
        <style>.a { stroke: #0000ff; } .a { fill: #00ff00; }</style>
        <rect class="a" x="10" y="10" width="20" height="20"/>
        """)
        let shape = try XCTUnwrap(firstShape(layer))
        let fill = try XCTUnwrap(rgb(shape.fillColor))
        let stroke = try XCTUnwrap(rgb(shape.strokeColor))
        XCTAssertEqual(fill.g, 1, accuracy: 0.01)
        XCTAssertEqual(stroke.b, 1, accuracy: 0.01)
    }

    func testLaterRuleWinsForSameProperty() throws {
        let layer = try render("""
        <style>.a { fill: #ff0000; } .a { fill: #0000ff; }</style>
        <rect class="a" x="10" y="10" width="20" height="20"/>
        """)
        let fill = try XCTUnwrap(rgb(try XCTUnwrap(firstShape(layer)).fillColor))
        XCTAssertEqual(fill.b, 1, accuracy: 0.01)
        XCTAssertEqual(fill.r, 0, accuracy: 0.01)
    }

    func testCommentsAreStripped() throws {
        let layer = try render("""
        <style>/* banner */ .a { fill: #ff0000; } /* trailing */</style>
        <rect class="a" x="10" y="10" width="20" height="20"/>
        """)
        let fill = try XCTUnwrap(rgb(try XCTUnwrap(firstShape(layer)).fillColor))
        XCTAssertEqual(fill.r, 1, accuracy: 0.01)
    }

    func testAtMediaBlockIsSkipped() throws {
        let layer = try render("""
        <style>@media (min-width: 10px) { .a { fill: #0000ff; } } .a { fill: #ff0000; }</style>
        <rect class="a" x="10" y="10" width="20" height="20"/>
        """)
        let fill = try XCTUnwrap(rgb(try XCTUnwrap(firstShape(layer)).fillColor))
        XCTAssertEqual(fill.r, 1, accuracy: 0.01)
        XCTAssertEqual(fill.b, 0, accuracy: 0.01)
    }

    func testCommaSelectorAppliesToBoth() throws {
        let layer = try render("""
        <style>.a, .b { fill: #00ff00; }</style>
        <rect class="a" x="0" y="0" width="20" height="20"/>
        <rect class="b" x="40" y="0" width="20" height="20"/>
        """)
        let fills = allFills(layer).compactMap { rgb($0) }
        XCTAssertEqual(fills.count, 2)
        XCTAssertTrue(fills.allSatisfy { $0.g > 0.8 })
    }
}
