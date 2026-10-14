import XCTest
import UIKit
@testable import SVGRenderKit

/// B93 — an `objectBoundingBox` radial gradient is defined in the element's unit
/// square and mapped onto the bounding box non-uniformly, so its radius is the
/// ellipse `r·w × r·h` (not a circle), and `gradientTransform` applies in that square.
final class SVGRadialGradientGeometryTests: XCTestCase {

    private func render(_ body: String, viewBox: String = "0 0 200 100") throws -> CALayer {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"\(viewBox)\">\(body)</svg>"
        return try SVGParser(svgString: svg, parsedRoot: nil).getLayer(overrideElements: nil)
    }

    private func firstRadial(_ layer: CALayer) -> RadialGradientLayer? {
        if let r = layer as? RadialGradientLayer { return r }
        for sub in layer.sublayers ?? [] {
            if let found = firstRadial(sub) { return found }
        }
        return nil
    }

    func testObjectBoundingBoxIsElliptical() throws {
        // A 200×100 box: r=0.5 spans 0.5·200 by 0.5·100, i.e. 100 × 50, not a circle.
        let layer = try render("""
        <defs><radialGradient id="g"><stop offset="0" stop-color="#f00"/><stop offset="1" stop-color="#00f"/></radialGradient></defs>
        <rect width="200" height="100" fill="url(#g)"/>
        """)
        let g = try XCTUnwrap(firstRadial(layer))
        let center = g.center.applying(g.gradientTransform)
        XCTAssertEqual(center.x, 100, accuracy: 0.001)
        XCTAssertEqual(center.y, 50, accuracy: 0.001)
        // Semi-axes of the ellipse the radius maps to.
        XCTAssertEqual(g.gradientTransform.a * g.radius, 100, accuracy: 0.001)
        XCTAssertEqual(g.gradientTransform.d * g.radius, 50, accuracy: 0.001)
    }

    func testSquareBoxStaysCircular() throws {
        let layer = try render("""
        <defs><radialGradient id="g" r="50%"><stop offset="0" stop-color="#f00"/><stop offset="1" stop-color="#00f"/></radialGradient></defs>
        <rect width="100" height="100" fill="url(#g)"/>
        """, viewBox: "0 0 100 100")
        let g = try XCTUnwrap(firstRadial(layer))
        XCTAssertEqual(g.gradientTransform.a * g.radius, g.gradientTransform.d * g.radius, accuracy: 0.001)
        XCTAssertEqual(g.gradientTransform.a * g.radius, 50, accuracy: 0.001)
    }

    func testGradientTransformIsInUnitSpace() throws {
        // translate(0.25, 0) shifts the center by a quarter of the box, not by 0.25 units.
        let layer = try render("""
        <defs><radialGradient id="g" gradientTransform="translate(0.25 0)"><stop offset="0" stop-color="#f00"/><stop offset="1" stop-color="#00f"/></radialGradient></defs>
        <rect width="200" height="100" fill="url(#g)"/>
        """)
        let g = try XCTUnwrap(firstRadial(layer))
        let center = g.center.applying(g.gradientTransform)
        XCTAssertEqual(center.x, 150, accuracy: 0.001)
        XCTAssertEqual(center.y, 50, accuracy: 0.001)
    }
}
