import XCTest
import UIKit
@testable import SVGRenderKit

/// B93 — `gradientTransform` must apply in the gradient's own coordinate system.
/// For `objectBoundingBox` that is the element's unit square, so a transform moves
/// the gradient axis by a fraction of the box, not by absolute userspace units.
final class SVGLinearGradientGeometryTests: XCTestCase {

    private func render(_ body: String) throws -> CALayer {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 200 100\">\(body)</svg>"
        return try SVGParser(svgString: svg, parsedRoot: nil).getLayer(overrideElements: nil)
    }

    private func firstLinear(_ layer: CALayer) -> CAGradientLayer? {
        if let g = layer as? CAGradientLayer { return g }
        for sub in layer.sublayers ?? [] {
            if let found = firstLinear(sub) { return found }
        }
        return nil
    }

    func testObjectBoundingBoxGradientTransformIsInUnitSpace() throws {
        // x1..x2 = 0..1 in unit space, then translate(0.5) → 0.5..1.5 in unit space.
        let layer = try render("""
        <defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="0" gradientTransform="translate(0.5 0)"><stop offset="0" stop-color="#f00"/><stop offset="1" stop-color="#00f"/></linearGradient></defs>
        <rect width="200" height="100" fill="url(#g)"/>
        """)
        let g = try XCTUnwrap(firstLinear(layer))
        XCTAssertEqual(g.startPoint.x, 0.5, accuracy: 1e-6)
        XCTAssertEqual(g.endPoint.x, 1.5, accuracy: 1e-6)
    }

    func testObjectBoundingBoxWithoutTransformIsUnchanged() throws {
        let layer = try render("""
        <defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#f00"/><stop offset="1" stop-color="#00f"/></linearGradient></defs>
        <rect width="200" height="100" fill="url(#g)"/>
        """)
        let g = try XCTUnwrap(firstLinear(layer))
        XCTAssertEqual(g.startPoint.x, 0, accuracy: 1e-6)
        XCTAssertEqual(g.endPoint.x, 1, accuracy: 1e-6)
    }
}
