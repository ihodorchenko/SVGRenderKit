import XCTest
@testable import SVGRenderKit

/// M3.3 — CSS `filter: drop-shadow(…)` on shapes and groups.
final class SVGDropShadowTests: XCTestCase {

    private func layer(_ body: String) throws -> CALayer {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\">\(body)</svg>"
        return try SVGParser(svgString: svg, parsedRoot: nil).getLayer(overrideElements: nil)
    }

    private func mainLayer(_ root: CALayer) throws -> CALayer {
        func firstShape(_ layer: CALayer) -> CAShapeLayer? {
            if let shape = layer as? CAShapeLayer, shape.path != nil { return shape }
            for sublayer in layer.sublayers ?? [] {
                if let found = firstShape(sublayer) { return found }
            }
            return nil
        }
        return try XCTUnwrap(try XCTUnwrap(firstShape(root)).superlayer)
    }

    func testDropShadowOnAShape() throws {
        let layer = try mainLayer(try layer("""
        <style>.r{filter:drop-shadow(2px 4px 6px rgba(0, 0, 0, 0.5))}</style>
        <rect class="r" width="20" height="20"/>
        """))
        XCTAssertEqual(layer.shadowOffset.width, 2, accuracy: 0.01)
        XCTAssertEqual(layer.shadowOffset.height, 4, accuracy: 0.01)
        XCTAssertEqual(layer.shadowRadius, 6, accuracy: 0.01)
        let color = try XCTUnwrap(layer.shadowColor)
        XCTAssertEqual(color.alpha, 0.5, accuracy: 0.01)
        XCTAssertEqual(layer.shadowOpacity, 1, accuracy: 0.01)
    }

    func testDropShadowCurrentColorAndDefaults() throws {
        let layer = try mainLayer(try layer("""
        <style>.r{color:#00ff00;filter:drop-shadow(1px 2px)}</style>
        <rect class="r" width="20" height="20"/>
        """))
        XCTAssertEqual(layer.shadowRadius, 0, accuracy: 0.01)
        let color = UIColor(cgColor: try XCTUnwrap(layer.shadowColor))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(g, 1, accuracy: 0.02, "a missing color is currentColor")
    }

    func testDropShadowOnAGroup() throws {
        let root = try layer("""
        <style>.g{filter:drop-shadow(0 3px 4px #000000)}</style>
        <g class="g"><rect width="20" height="20"/></g>
        """)
        let groupLayer = try XCTUnwrap(root.sublayers?.first)
        XCTAssertEqual(groupLayer.shadowOffset.height, 3, accuracy: 0.01)
        XCTAssertEqual(groupLayer.shadowRadius, 4, accuracy: 0.01)
    }

    func testDropShadowIsNotInherited() throws {
        let root = try layer("""
        <style>.g{filter:drop-shadow(0 3px 4px #000000)}</style>
        <g class="g"><rect width="20" height="20"/></g>
        """)
        let shape = try mainLayer(root)
        XCTAssertEqual(shape.shadowOpacity, 0, accuracy: 0.01,
                       "the shadow must not be applied by the child too")
    }

    func testInlineDropShadowReplacesTheURLFilter() throws {
        let layer = try mainLayer(try layer("""
        <defs><filter id="f"><feGaussianBlur stdDeviation="1"/></filter></defs>
        <rect filter="url(#f)" style="filter:drop-shadow(5px 0 0 #f00)" width="20" height="20"/>
        """))
        XCTAssertEqual(layer.shadowOffset.width, 5, accuracy: 0.01)
    }

    func testFilterNoneClearsTheDropShadow() throws {
        let layer = try mainLayer(try layer("""
        <rect style="filter:drop-shadow(5px 0 0 #f00);filter:none" width="20" height="20"/>
        """))
        XCTAssertEqual(layer.shadowOpacity, 0, accuracy: 0.01)
    }

    func testInvalidDropShadowIsIgnored() throws {
        let layer = try mainLayer(try layer("""
        <rect style="filter:drop-shadow(nope)" width="20" height="20"/>
        """))
        XCTAssertEqual(layer.shadowOpacity, 0, accuracy: 0.01)
    }
}
