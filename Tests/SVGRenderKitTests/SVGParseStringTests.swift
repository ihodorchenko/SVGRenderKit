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

    // MARK: Leading whitespace (B27)

    func testLeadingWhitespaceBeforeMoveToIsAccepted() throws {
        // SVG path data may be preceded by whitespace; it must not be rejected.
        let result = SVGParseString.parseSVGPath(pathString: "   M0 0 L10 10")
        XCTAssertNil(result.error)
        let path = try XCTUnwrap(result.path)
        XCTAssertEqual(elementCount(path), 2) // move + line
    }

    func testLeadingTabAndNewlineBeforeMoveToIsAccepted() throws {
        let result = SVGParseString.parseSVGPath(pathString: "\t\nM0 0 L10 10")
        XCTAssertNil(result.error)
        let path = try XCTUnwrap(result.path)
        XCTAssertEqual(elementCount(path), 2)
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

    // MARK: Relative first command when appending (B17)

    func testRelativeFirstCommandUsesSuppliedPathCurrentPoint() throws {
        let base = UIBezierPath()
        base.move(to: CGPoint(x: 50, y: 50))
        let result = SVGParseString.parseSVGPath(pathString: "m10 10 l5 5", forPath: base)
        XCTAssertNil(result.error)
        let path = try XCTUnwrap(result.path)
        // Relative move from (50,50) -> (60,60); relative line -> (65,65).
        XCTAssertEqual(path.currentPoint.x, 65, accuracy: 0.001)
        XCTAssertEqual(path.currentPoint.y, 65, accuracy: 0.001)
    }

    // MARK: ClosePath getGroups division by zero (B26)

    func testClosePathGetGroupsReturnsEmpty() {
        // `ClosePath` has zero required parameters; `getGroups()` must return an
        // empty list instead of dividing by zero.
        let close = ClosePath(character: "Z", pathType: .absolute)
        XCTAssertEqual(close.getGroups(), [])
    }

    func testSmoothCurveAfterClosePathDoesNotCrash() {
        // A smooth cubic (`S`) following `Z` previously divided by zero while
        // reflecting the previous command's control point. It must not crash.
        let result = SVGParseString.parseSVGPath(pathString: "M0 0 C1 1 2 2 3 3 Z S4 4 5 5")
        // Reflection against a ClosePath is not meaningful, so the parser degrades
        // to a graceful error rather than aborting.
        XCTAssertNotNil(result.error)
    }

    // MARK: Compact elliptical-arc flags (B84)

    private func assertSameGeometry(_ compact: String, _ spaced: String,
                                    file: StaticString = #filePath, line: UInt = #line) throws {
        let c = SVGParseString.parseSVGPath(pathString: compact)
        let s = SVGParseString.parseSVGPath(pathString: spaced)
        XCTAssertNil(c.error, "compact form errored: \(String(describing: c.error))", file: file, line: line)
        XCTAssertNil(s.error, file: file, line: line)
        let cp = try XCTUnwrap(c.path, file: file, line: line)
        let sp = try XCTUnwrap(s.path, file: file, line: line)
        XCTAssertEqual(elementCount(cp), elementCount(sp), file: file, line: line)
        XCTAssertEqual(cp.bounds.minX, sp.bounds.minX, accuracy: 1e-6, file: file, line: line)
        XCTAssertEqual(cp.bounds.minY, sp.bounds.minY, accuracy: 1e-6, file: file, line: line)
        XCTAssertEqual(cp.bounds.maxX, sp.bounds.maxX, accuracy: 1e-6, file: file, line: line)
        XCTAssertEqual(cp.bounds.maxY, sp.bounds.maxY, accuracy: 1e-6, file: file, line: line)
    }

    func testCompactArcFlagsParseLikeSpacedForm() throws {
        // SVGO emits the flags without separators: `a2 2 0 011 1` is
        // large-arc=0, sweep=1, then x=1, y=1 (each flag is a single character).
        try assertSameGeometry("M0 0a2 2 0 011 1", "M0 0a2 2 0 0 1 1 1")
    }

    func testCompactArcFlagFollowedByMultiDigitCoordinate() throws {
        // "0111" is large-arc=0, sweep=1, then x=11 (the coordinate is read greedily).
        try assertSameGeometry("M0 0a2 2 0 0111 1", "M0 0a2 2 0 0 1 11 1")
    }

    func testCompactArcFlagsAcrossRepeatedGroups() throws {
        try assertSameGeometry("M0 0a2 2 0 011 1 2 2 0 011 1",
                               "M0 0a2 2 0 0 1 1 1 2 2 0 0 1 1 1")
    }
}
