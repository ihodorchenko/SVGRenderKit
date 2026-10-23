import XCTest
@testable import SVGRenderKit

/// Document-controlled numbers must never reach `Int(_:)` unchecked: `Int(nan)`, `Int(inf)` and
/// `Int(1e308)` trap. Each of these documents used to crash the process; now the offending
/// property or element degrades.
final class SVGNumericRobustnessTests: XCTestCase {

    private func layer(_ body: String) throws -> CALayer {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\">\(body)</svg>"
        return try SVGParser(svgString: svg, parsedRoot: nil).getLayer(overrideElements: nil)
    }

    private func shapes(_ layer: CALayer) -> [CAShapeLayer] {
        ((layer as? CAShapeLayer).map { [$0] } ?? []) + (layer.sublayers ?? []).flatMap(shapes)
    }

    // MARK: animateTransform

    func testNaNAnimationValueIsIgnored() throws {
        let root = try layer("""
        <path d="M0 0h10v10z"><animateTransform attributeName="transform" type="rotate" values="nan;0" dur="1s"/></path>
        """)
        XCTAssertFalse(shapes(root).isEmpty)
    }

    func testHugeAnimationAngleIsSampledWithinTheCap() throws {
        let start = Date()
        _ = try layer("""
        <path d="M0 0h10v10z"><animateTransform attributeName="transform" type="rotate" values="0;1e9;-1e308" dur="1s"/></path>
        """)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5, "keyframe count must be capped")
    }

    // MARK: mask / pattern with a non-representable region

    func testMaskOnAnAbsurdlyLargeShapeDoesNotTrap() throws {
        let root = try layer("""
        <mask id="m"><rect width="10" height="10" fill="#fff"/></mask>
        <path d="M0 0 L1e308 1e308 L0 5z" mask="url(#m)"/>
        """)
        XCTAssertFalse(shapes(root).isEmpty)
    }

    func testPatternOnAnAbsurdlyLargeShapeDoesNotTrap() throws {
        let root = try layer("""
        <pattern id="p" width="0.5" height="0.5"><rect width="1" height="1"/></pattern>
        <path d="M0 0 L1e308 1e308 L0 5z" fill="url(#p)"/>
        """)
        XCTAssertFalse(shapes(root).isEmpty)
    }

    // MARK: font-weight

    func testNonFiniteOrHugeFontWeightDoesNotTrap() throws {
        for weight in ["1e308", "1e30", "inf", "nan"] {
            let root = try layer("<text x=\"1\" y=\"20\" font-weight=\"\(weight)\">hi</text>")
            XCTAssertNotNil(root, "font-weight=\(weight)")
        }
    }

    // MARK: pattern that cannot produce a tile

    /// A pattern tile past the bitmap cap is skipped; the shape's fill is then `none`, not the
    /// CoreAnimation default black.
    func testOversizedPatternTileLeavesTheFillCleared() throws {
        let root = try layer("""
        <pattern id="p" width="5000" height="5000" patternUnits="userSpaceOnUse"><rect width="9" height="9" fill="red"/></pattern>
        <rect width="50" height="50" fill="url(#p)"/>
        """)
        // Only layers that draw a path: the container layers carry no path, so their fill is moot.
        let all = shapes(root).filter { $0.path != nil }
        XCTAssertFalse(all.isEmpty)
        XCTAssertTrue(all.allSatisfy { $0.fillColor == nil }, "a skipped pattern must not paint the default black")
    }
}
