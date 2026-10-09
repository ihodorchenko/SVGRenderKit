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
}
