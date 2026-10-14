import XCTest
@testable import SVGRenderKit

/// B86 — a `<use>` element passes its style into the referenced content as an
/// *inherited* base (SVG 1.1 §5.6): the referenced element's own properties win,
/// and the `use`'s opacity / clip-path / mask / filter composite the content.
final class SVGUseStyleTests: XCTestCase {

    private func render(_ body: String) throws -> CALayer {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" viewBox=\"0 0 10 10\">\(body)</svg>"
        return try SVGParser(svgString: svg, parsedRoot: nil).getLayer(overrideElements: nil)
    }

    private func filledShape(in layer: CALayer) -> CAShapeLayer? {
        if let shape = layer as? CAShapeLayer, shape.path != nil, shape.fillColor != nil {
            return shape
        }
        for sub in layer.sublayers ?? [] {
            if let found = filledShape(in: sub) { return found }
        }
        return nil
    }

    private func rgba(_ cgColor: CGColor?) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        guard let c = cgColor, let comps = c.components else { return (0, 0, 0, 0) }
        if comps.count >= 4 { return (comps[0], comps[1], comps[2], comps[3]) }
        if comps.count == 2 { return (comps[0], comps[0], comps[0], comps[1]) }
        return (0, 0, 0, 0)
    }

    private func containsLayer(withOpacity opacity: Float, in layer: CALayer) -> Bool {
        if abs(layer.opacity - opacity) < 0.001 { return true }
        for sub in layer.sublayers ?? [] where containsLayer(withOpacity: opacity, in: sub) { return true }
        return false
    }

    func testUseFillDoesNotOverrideReferencedShapeFill() throws {
        // The referenced rect has its own fill; the use's fill is only inherited.
        let layer = try render("""
        <defs><rect id="r" width="10" height="10" fill="#0000ff"/></defs>
        <use href="#r" fill="#ff0000"/>
        """)
        let c = rgba(try XCTUnwrap(filledShape(in: layer)).fillColor)
        XCTAssertEqual(c.b, 1, accuracy: 0.01)
        XCTAssertEqual(c.r, 0, accuracy: 0.01)
    }

    func testUseFillIsInheritedByUnfilledContent() throws {
        let layer = try render("""
        <defs><rect id="r" width="10" height="10"/></defs>
        <use href="#r" fill="#ff0000"/>
        """)
        let c = rgba(try XCTUnwrap(filledShape(in: layer)).fillColor)
        XCTAssertEqual(c.r, 1, accuracy: 0.01)
        XCTAssertEqual(c.b, 0, accuracy: 0.01)
    }

    func testUseFillReachesSymbolContent() throws {
        // A `<symbol>` ignores its own style context; it must still inherit the use's.
        let layer = try render("""
        <defs><symbol id="s"><rect width="10" height="10"/></symbol></defs>
        <use href="#s" width="10" height="10" fill="#00ff00"/>
        """)
        let c = rgba(try XCTUnwrap(filledShape(in: layer)).fillColor)
        XCTAssertEqual(c.g, 1, accuracy: 0.01)
    }

    func testUseColorReachesSymbolCurrentColor() throws {
        let layer = try render("""
        <defs><symbol id="s"><rect width="10" height="10" fill="currentColor"/></symbol></defs>
        <use href="#s" width="10" height="10" color="#00ff00"/>
        """)
        let c = rgba(try XCTUnwrap(filledShape(in: layer)).fillColor)
        XCTAssertEqual(c.g, 1, accuracy: 0.01)
    }

    func testUseOpacityCompositesReferencedContent() throws {
        let layer = try render("""
        <defs><rect id="r" width="10" height="10" fill="#000000"/></defs>
        <use href="#r" opacity="0.5"/>
        """)
        XCTAssertTrue(containsLayer(withOpacity: 0.5, in: layer))
    }
}
