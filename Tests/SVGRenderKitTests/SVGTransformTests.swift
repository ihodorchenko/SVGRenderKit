import XCTest
@testable import SVGRenderKit

final class SVGTransformTests: XCTestCase {

    func testSkewXDoesNotCrashAndProducesExpectedMatrix() throws {
        let t = try SVGTransform.get(string: "skewX(45)")
        // skewX(45°): x' = x + tan(45°)·y, so the y-into-x coefficient is 1.
        XCTAssertEqual(t.m11, 1, accuracy: 1e-6)
        XCTAssertEqual(t.m22, 1, accuracy: 1e-6)
        XCTAssertEqual(t.m21, 1, accuracy: 1e-6)
    }

    func testSkewYDoesNotCrashAndProducesExpectedMatrix() throws {
        let t = try SVGTransform.get(string: "skewY(45)")
        // skewY(45°): y' = tan(45°)·x + y, so the x-into-y coefficient is 1.
        XCTAssertEqual(t.m11, 1, accuracy: 1e-6)
        XCTAssertEqual(t.m22, 1, accuracy: 1e-6)
        XCTAssertEqual(t.m12, 1, accuracy: 1e-6)
    }

    func testTransformListTranslateThenScale() throws {
        // translate(10 0) scale(2): the translate sets the origin in parent space,
        // so it is NOT scaled — (0,0) maps to (10,0).
        let t = try SVGTransform.get(string: "translate(10 0) scale(2)")
        let p = CGPoint(x: 0, y: 0).applying(CATransform3DGetAffineTransform(t))
        XCTAssertEqual(p.x, 10, accuracy: 1e-4)
        XCTAssertEqual(p.y, 0, accuracy: 1e-4)
    }

    func testTransformListScaleThenTranslate() throws {
        // scale(2) translate(10 0): translate is applied in the scaled space,
        // so it is doubled — (0,0) maps to (20,0).
        let t = try SVGTransform.get(string: "scale(2) translate(10 0)")
        let p = CGPoint(x: 0, y: 0).applying(CATransform3DGetAffineTransform(t))
        XCTAssertEqual(p.x, 20, accuracy: 1e-4)
        XCTAssertEqual(p.y, 0, accuracy: 1e-4)
    }
}
