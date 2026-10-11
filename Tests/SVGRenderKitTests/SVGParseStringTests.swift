import XCTest
@testable import SVGRenderKit

final class SVGParseStringTests: XCTestCase {

    private func elementCount(_ path: UIBezierPath) -> Int {
        var count = 0
        path.cgPath.applyWithBlock { _ in count += 1 }
        return count
    }

    private func quadControlPoints(_ path: UIBezierPath) -> [CGPoint] {
        var points: [CGPoint] = []
        path.cgPath.applyWithBlock { element in
            if element.pointee.type == .addQuadCurveToPoint {
                points.append(element.pointee.points[0])
            }
        }
        return points
    }

    func testParsesMoveAndLine() {
        let result = SVGParseString.parseSVGPath(pathString: "M0 0 L10 10")
        XCTAssertNil(result.error)
        let path = try? XCTUnwrap(result.path)
        XCTAssertNotNil(path)
        XCTAssertEqual(elementCount(path!), 2)
    }

    func testArcWithZeroRadiusRendersLine() throws {
        let result = SVGParseString.parseSVGPath(pathString: "M0 0 A0 50 0 0 1 100 100")
        XCTAssertNil(result.error)
        let path = try XCTUnwrap(result.path)
        XCTAssertEqual(elementCount(path), 2) // M + lineto (zero-radius arc → line)
    }

    func testArcWithCoincidentEndpointsIsSkipped() throws {
        let result = SVGParseString.parseSVGPath(pathString: "M10 10 A5 5 0 0 1 10 10")
        XCTAssertNil(result.error)
        let path = try XCTUnwrap(result.path)
        XCTAssertEqual(elementCount(path), 1) // M only (coincident arc omitted)
    }

    func testParsesRelativeMoveAndLine() {
        let result = SVGParseString.parseSVGPath(pathString: "m0 0 l10 10")
        XCTAssertNil(result.error)
        XCTAssertNotNil(result.path)
    }

    func testMissingMoveToReturnsError() {
        let result = SVGParseString.parseSVGPath(pathString: "L10 10")
        XCTAssertNil(result.path)
        XCTAssertNotNil(result.error)
    }

    func testEmptyStringReturnsError() {
        let result = SVGParseString.parseSVGPath(pathString: "")
        XCTAssertNil(result.path)
        XCTAssertNotNil(result.error)
    }

    func testAppendsToSuppliedPath() {
        let base = UIBezierPath(rect: CGRect(x: 0, y: 0, width: 10, height: 10))
        let baseElementCount = elementCount(base)
        let result = SVGParseString.parseSVGPath(pathString: "M0 0 L10 10", forPath: base)
        XCTAssertNil(result.error)
        XCTAssertEqual(elementCount(result.path!), baseElementCount + 2)
    }

    // MARK: Repeated H/V/T coordinates (T52)

    func testParsesRepeatedHorizontalCoordinates() {
        let result = SVGParseString.parseSVGPath(pathString: "M0 0 H10 20 30")
        XCTAssertNil(result.error)
        let path = try? XCTUnwrap(result.path)
        XCTAssertNotNil(path)
        XCTAssertEqual(elementCount(path!), 4) // move + 3 line segments
    }

    func testParsesRepeatedVerticalCoordinates() {
        let result = SVGParseString.parseSVGPath(pathString: "M0 0 V10 20 30")
        XCTAssertNil(result.error)
        let path = try? XCTUnwrap(result.path)
        XCTAssertNotNil(path)
        XCTAssertEqual(elementCount(path!), 4) // move + 3 line segments
    }

    func testParsesRepeatedSmoothQuadraticCoordinates() {
        let result = SVGParseString.parseSVGPath(pathString: "M0 0 Q10 10 20 20 T30 30 40 40")
        XCTAssertNil(result.error)
        let path = try? XCTUnwrap(result.path)
        XCTAssertNotNil(path)
        XCTAssertEqual(elementCount(path!), 4) // move + Q + 2 smooth quads
    }

    // MARK: Smooth quadratic reflection (T68)

    func testSmoothQuadraticReflectsPreviousQuadraticControl() {
        let result = SVGParseString.parseSVGPath(pathString: "M0 0 Q10 10 20 0 T40 0")
        XCTAssertNil(result.error)
        let path = try? XCTUnwrap(result.path)
        XCTAssertNotNil(path)
        let controls = quadControlPoints(path!)
        XCTAssertEqual(controls.count, 2)
        XCTAssertEqual(controls[0].x, 10, accuracy: 0.001)
        XCTAssertEqual(controls[0].y, 10, accuracy: 0.001)
        // Reflection: 2*(20,0) - (10,10) = (30,-10)
        XCTAssertEqual(controls[1].x, 30, accuracy: 0.001)
        XCTAssertEqual(controls[1].y, -10, accuracy: 0.001)
    }

    func testSmoothQuadraticAfterSmoothQuadraticDoesNotCrash() {
        let result = SVGParseString.parseSVGPath(pathString: "M0 0 Q10 10 20 0 T40 0 T60 0")
        XCTAssertNil(result.error)
        let path = try? XCTUnwrap(result.path)
        XCTAssertNotNil(path)
        XCTAssertEqual(elementCount(path!), 4) // move + Q + T + T
        let controls = quadControlPoints(path!)
        XCTAssertEqual(controls.count, 3)
        XCTAssertEqual(controls[0].x, 10, accuracy: 0.001)
        XCTAssertEqual(controls[0].y, 10, accuracy: 0.001)
        // T1 reflects Q's control: 2*(20,0) - (10,10) = (30,-10)
        XCTAssertEqual(controls[1].x, 30, accuracy: 0.001)
        XCTAssertEqual(controls[1].y, -10, accuracy: 0.001)
        // T2 reflects T1's control: 2*(40,0) - (30,-10) = (50,10)
        XCTAssertEqual(controls[2].x, 50, accuracy: 0.001)
        XCTAssertEqual(controls[2].y, 10, accuracy: 0.001)
    }

    // MARK: Whitespace separators (T67)

    func testParsesNewlineTabAndCarriageReturnSeparators() {
        let result = SVGParseString.parseSVGPath(pathString: "M0 0\nL10 10\tL20 20\rL30 30")
        XCTAssertNil(result.error)
        let path = try? XCTUnwrap(result.path)
        XCTAssertNotNil(path)
        XCTAssertEqual(elementCount(path!), 4) // move + 3 line segments
    }

    // MARK: Scientific notation exponent (B14)

    func testParsesUppercaseExponent() throws {
        let result = SVGParseString.parseSVGPath(pathString: "M0 0 L1E2 0")
        XCTAssertNil(result.error)
        let path = try XCTUnwrap(result.path)
        XCTAssertEqual(elementCount(path), 2) // move + line
        XCTAssertEqual(path.currentPoint.x, 100, accuracy: 0.001)
    }

    func testParsesLowercaseExponent() throws {
        let result = SVGParseString.parseSVGPath(pathString: "M0 0 L1e2 0")
        XCTAssertNil(result.error)
        let path = try XCTUnwrap(result.path)
        XCTAssertEqual(path.currentPoint.x, 100, accuracy: 0.001)
    }

    // MARK: Leading-zero integer (B15)

    func testLeadingZeroIsSingleNumber() throws {
        // "05" must parse as the single coordinate 5, not as 0 and 5.
        let result = SVGParseString.parseSVGPath(pathString: "M0 0 L05 0")
        XCTAssertNil(result.error)
        let path = try XCTUnwrap(result.path)
        XCTAssertEqual(elementCount(path), 2) // move + line (not move + 2 lines)
        XCTAssertEqual(path.currentPoint.x, 5, accuracy: 0.001)
    }

    // MARK: Dangling command letter (B16)

    func testDanglingCommandPreservesPath() throws {
        // A trailing 'L' with no coordinates must not discard the preceding move.
        let result = SVGParseString.parseSVGPath(pathString: "M0 0 L")
        XCTAssertNil(result.error)
        let path = try XCTUnwrap(result.path)
        XCTAssertEqual(elementCount(path), 1) // the move is preserved
        XCTAssertEqual(path.currentPoint.x, 0, accuracy: 0.001)
        XCTAssertEqual(path.currentPoint.y, 0, accuracy: 0.001)
    }
}
