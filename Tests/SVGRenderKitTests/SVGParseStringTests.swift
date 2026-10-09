import XCTest
@testable import SVGRenderKit

final class SVGParseStringTests: XCTestCase {

    private func elementCount(_ path: UIBezierPath) -> Int {
        var count = 0
        path.cgPath.applyWithBlock { _ in count += 1 }
        return count
    }

    func testParsesMoveAndLine() {
        let result = SVGParseString.parseSVGPath(pathString: "M0 0 L10 10")
        XCTAssertNil(result.error)
        let path = try? XCTUnwrap(result.path)
        XCTAssertNotNil(path)
        XCTAssertEqual(elementCount(path!), 2)
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
}
