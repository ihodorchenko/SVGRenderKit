import XCTest
@testable import SVGRenderKit

/// B91 — class/id/tag selectors must target a container (`<g>`), not only a shape.
/// Illustrator output such as `<g class="st0">` + `.st0{fill:…}` must style the group
/// and be inherited by its children, exactly like the group's presentation attributes.
final class SVGGroupSelectorTests: XCTestCase {

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

    private func allFills(_ layer: CALayer) -> [CGColor] {
        var result: [CGColor] = []
        if let shape = layer as? CAShapeLayer, shape.path != nil, let fill = shape.fillColor { result.append(fill) }
        for sub in layer.sublayers ?? [] { result.append(contentsOf: allFills(sub)) }
        return result
    }

    private func rgb(_ cgColor: CGColor?) -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
        guard let cgColor = cgColor, let comps = cgColor.components, comps.count >= 3 else { return nil }
        return (comps[0], comps[1], comps[2])
    }

    private func fill(_ layer: CALayer) throws -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        return try XCTUnwrap(rgb(try XCTUnwrap(firstShape(layer)).fillColor))
    }

    // MARK: - The reported case

    func testGroupClassSelectorIsInheritedByChild() throws {
        let layer = try render("""
        <style>.st0 { fill: #ff0000; }</style>
        <g class="st0"><rect x="10" y="10" width="20" height="20"/></g>
        """)
        let c = try fill(layer)
        XCTAssertEqual(c.r, 1, accuracy: 0.01)
        XCTAssertEqual(c.g, 0, accuracy: 0.01)
        XCTAssertEqual(c.b, 0, accuracy: 0.01)
    }

    // MARK: - Other selector kinds on a group

    func testGroupIdSelectorIsInheritedByChild() throws {
        let layer = try render("""
        <style>#g1 { fill: #0000ff; }</style>
        <g id="g1"><rect x="10" y="10" width="20" height="20"/></g>
        """)
        XCTAssertEqual(try fill(layer).b, 1, accuracy: 0.01)
    }

    func testGroupTagSelectorIsInheritedByChild() throws {
        let layer = try render("""
        <style>g { fill: #00ff00; }</style>
        <g><rect x="10" y="10" width="20" height="20"/></g>
        """)
        XCTAssertEqual(try fill(layer).g, 1, accuracy: 0.01)
    }

    // MARK: - Cascade

    func testGroupSelectorBeatsGroupPresentationAttribute() throws {
        // Same element: a CSS rule outranks a presentation attribute.
        let layer = try render("""
        <style>.st0 { fill: #ff0000; }</style>
        <g class="st0" fill="#0000ff"><rect x="10" y="10" width="20" height="20"/></g>
        """)
        let c = try fill(layer)
        XCTAssertEqual(c.r, 1, accuracy: 0.01)
        XCTAssertEqual(c.b, 0, accuracy: 0.01)
    }

    func testChildPresentationAttributeBeatsInheritedGroupSelector() throws {
        // The child's own presentation attribute outranks a value inherited from the group.
        let layer = try render("""
        <style>.st0 { fill: #ff0000; }</style>
        <g class="st0"><rect fill="#00ff00" x="10" y="10" width="20" height="20"/></g>
        """)
        let c = try fill(layer)
        XCTAssertEqual(c.g, 1, accuracy: 0.01)
        XCTAssertEqual(c.r, 0, accuracy: 0.01)
    }

    func testChildClassSelectorBeatsInheritedGroupSelector() throws {
        let layer = try render("""
        <style>.st0 { fill: #ff0000; } .st1 { fill: #0000ff; }</style>
        <g class="st0"><rect class="st1" x="10" y="10" width="20" height="20"/></g>
        """)
        let c = try fill(layer)
        XCTAssertEqual(c.b, 1, accuracy: 0.01)
        XCTAssertEqual(c.r, 0, accuracy: 0.01)
    }

    // MARK: - Nesting / multiple children

    func testGroupSelectorAppliesToEveryChild() throws {
        let layer = try render("""
        <style>.st0 { fill: #ff0000; }</style>
        <g class="st0">
          <rect x="0" y="0" width="20" height="20"/>
          <circle cx="50" cy="50" r="10"/>
        </g>
        """)
        let fills = allFills(layer).compactMap { rgb($0) }
        XCTAssertEqual(fills.count, 2)
        XCTAssertTrue(fills.allSatisfy { $0.r > 0.8 && $0.g < 0.2 && $0.b < 0.2 })
    }

    func testInnerGroupSelectorBeatsOuterGroupSelector() throws {
        let layer = try render("""
        <style>.outer { fill: #ff0000; } .inner { fill: #0000ff; }</style>
        <g class="outer"><g class="inner"><rect x="10" y="10" width="20" height="20"/></g></g>
        """)
        let c = try fill(layer)
        XCTAssertEqual(c.b, 1, accuracy: 0.01)
        XCTAssertEqual(c.r, 0, accuracy: 0.01)
    }
}
