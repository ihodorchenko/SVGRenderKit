import XCTest
@testable import SVGRenderKit

/// B133(ж) — the objectBoundingBox of a curved shape is its geometric bounds, not the box of its
/// control points.
final class SVGShapeBoundsTests: XCTestCase {

    private func curve() -> UIBezierPath {
        let p = UIBezierPath()
        p.move(to: .zero)
        p.addCurve(to: CGPoint(x: 100, y: 0), controlPoint1: CGPoint(x: 0, y: 100), controlPoint2: CGPoint(x: 100, y: 100))
        return p
    }

    func testBoundsOfACurveExcludeControlPoints() {
        // The curve peaks at y = 75 (3/4 of the control height).
        XCTAssertEqual(curve().svgBounds(transformedBy: nil).height, 75, accuracy: 0.5)
    }

    func testBoundsOfATransformedCurveExcludeControlPoints() {
        let t = CATransform3DMakeTranslation(10, 20, 0)
        let b = curve().svgBounds(transformedBy: t)
        XCTAssertEqual(b.height, 75, accuracy: 0.5)
        XCTAssertEqual(b.minY, 20, accuracy: 0.5)
    }

    func testObjectBoundingBoxClipOnACurvedShapeUsesTheTightBox() throws {
        // Clip = lower half of the bbox (y 0.5…1). Tight bbox height is 75 → clip starts at y 37.5.
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
        <defs><clipPath id="c" clipPathUnits="objectBoundingBox"><rect x="0" y="0.5" width="1" height="0.5"/></clipPath></defs>
        <path d="M0 0 C 0 100 100 100 100 0 Z" fill="#000" clip-path="url(#c)"/></svg>
        """
        let layer = try SVGParser(svgString: svg, parsedRoot: nil).getLayer(overrideElements: nil)
        func clipLayer(_ l: CALayer) -> CALayer? {
            if let m = l.mask { return m }
            for s in l.sublayers ?? [] { if let f = clipLayer(s) { return f } }
            return nil
        }
        let mask = try XCTUnwrap(clipLayer(layer))
        // The clip rect is scaled by the bbox height: its scale-y is the bbox height.
        XCTAssertEqual(mask.transform.m22, 75, accuracy: 0.5)
    }
}
