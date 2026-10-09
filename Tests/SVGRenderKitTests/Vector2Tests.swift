import XCTest
@testable import SVGRenderKit

final class Vector2Tests: XCTestCase {

    func testComponentInitializer() {
        let v = Vector2(3, 4)
        XCTAssertEqual(v.x, 3)
        XCTAssertEqual(v.y, 4)
    }

    func testArrayInitializer() {
        let v = Vector2([1, 2])
        XCTAssertEqual(v, Vector2(1, 2))
    }

    func testStaticConstants() {
        XCTAssertEqual(Vector2.zero, Vector2(0, 0))
        XCTAssertEqual(Vector2.x, Vector2(1, 0))
        XCTAssertEqual(Vector2.y, Vector2(0, 1))
    }

    func testToArray() {
        XCTAssertEqual(Vector2(1, 2).toArray(), [1, 2])
    }

    func testLengthSquaredAndLength() {
        let v = Vector2(3, 4)
        XCTAssertEqual(v.lengthSquared, 25)
        XCTAssertEqual(v.length, 5)
    }

    func testInverse() {
        XCTAssertEqual(Vector2(3, -4).inverse, Vector2(-3, 4))
    }

    func testDot() {
        XCTAssertEqual(Vector2(1, 2).dot(Vector2(3, 4)), 11)
    }

    func testCross() {
        XCTAssertEqual(Vector2(1, 0).cross(Vector2(0, 1)), 1)
        XCTAssertEqual(Vector2(0, 1).cross(Vector2(1, 0)), -1)
    }

    func testNormalized() {
        let v = Vector2(3, 4).normalized()
        XCTAssertEqual(v.x, 0.6, accuracy: 1e-9)
        XCTAssertEqual(v.y, 0.8, accuracy: 1e-9)

        // Zero and unit vectors are returned unchanged.
        XCTAssertEqual(Vector2.zero.normalized(), Vector2.zero)
        XCTAssertEqual(Vector2.x.normalized(), Vector2.x)
    }

    func testRotated() {
        let v = Vector2.x.rotated(by: .pi / 2)
        XCTAssertEqual(v.x, 0, accuracy: 1e-9)
        XCTAssertEqual(v.y, 1, accuracy: 1e-9)
    }

    func testRotatedAroundPivot() {
        let v = Vector2(2, 0).rotated(by: .pi, around: Vector2(1, 0))
        XCTAssertEqual(v.x, 0, accuracy: 1e-9)
        XCTAssertEqual(v.y, 0, accuracy: 1e-9)
    }

    func testAngle() {
        let angle = Vector2.x.angle(with: Vector2.y)
        XCTAssertEqual(angle, .pi / 2, accuracy: 1e-9)

        XCTAssertEqual(Vector2.x.angle(with: Vector2.x), 0)
    }

    func testInterpolated() {
        let v = Vector2(0, 0).interpolated(with: Vector2(10, 10), by: 0.5)
        XCTAssertEqual(v, Vector2(5, 5))
    }

    func testOperators() {
        XCTAssertEqual(Vector2(1, 2) + Vector2(3, 4), Vector2(4, 6))
        XCTAssertEqual(Vector2(3, 4) - Vector2(1, 2), Vector2(2, 2))
        XCTAssertEqual(-Vector2(1, -2), Vector2(-1, 2))

        XCTAssertEqual(Vector2(1, 2) + 10, Vector2(11, 12))
        XCTAssertEqual(Vector2(10, 20) - 5, Vector2(5, 15))

        XCTAssertEqual(Vector2(2, 3) * Vector2(4, 5), Vector2(8, 15))
        XCTAssertEqual(Vector2(2, 3) * 4, Vector2(8, 12))

        XCTAssertEqual(Vector2(8, 15) / Vector2(4, 3), Vector2(2, 5))
        XCTAssertEqual(Vector2(8, 12) / 4, Vector2(2, 3))
    }

    func testApproximateEquality() {
        XCTAssertTrue(Vector2(0.1, 0.2) ~= Vector2(0.1, 0.2))
        XCTAssertFalse(Vector2(0.1, 0.2) ~= Vector2(0.3, 0.4))
    }

    func testPointConversion() {
        let p = Vector2(1.5, 2.5).point
        XCTAssertEqual(p, CGPoint(x: 1.5, y: 2.5))
    }

    func testDescription() {
        XCTAssertEqual(Vector2(1, 2).description, "(x:1.0; y:2.0)")
    }
}
