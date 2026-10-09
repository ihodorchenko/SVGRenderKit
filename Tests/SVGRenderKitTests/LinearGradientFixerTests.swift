import XCTest
@testable import SVGRenderKit

final class LinearGradientFixerTests: XCTestCase {

    func testHorizontalGradientIsUnchanged() {
        let start = CGPoint(x: 0, y: 0)
        let end = CGPoint(x: 1, y: 0)
        let result = LinearGradientFixer.fixPoints(start: start, end: end, bounds: CGSize(width: 320, height: 60))
        XCTAssertEqual(result.0, start)
        XCTAssertEqual(result.1, end)
    }

    func testVerticalGradientIsUnchanged() {
        let start = CGPoint(x: 0, y: 0)
        let end = CGPoint(x: 0, y: 1)
        let result = LinearGradientFixer.fixPoints(start: start, end: end, bounds: CGSize(width: 320, height: 60))
        XCTAssertEqual(result.0, start)
        XCTAssertEqual(result.1, end)
    }

    func testDiagonalGradientIsCorrected() {
        let bounds = CGSize(width: 320, height: 60)
        let start = CGPoint(x: 138.5 / bounds.width, y: 11.5 / bounds.height)
        let end = CGPoint(x: 151.5 / bounds.width, y: 53.5 / bounds.height)

        let result = LinearGradientFixer.fixPoints(start: start, end: end, bounds: bounds)

        // Expected values are documented in the original algorithm's unit test.
        let expectedStart = CGPoint(x: 90.6119039567129, y: 26.3225059181603)
        let expectedEnd = CGPoint(x: 199.388096043287, y: 38.6774940818397)

        XCTAssertEqual(result.0.x * bounds.width, expectedStart.x, accuracy: 0.001)
        XCTAssertEqual(result.0.y * bounds.height, expectedStart.y, accuracy: 0.001)
        XCTAssertEqual(result.1.x * bounds.width, expectedEnd.x, accuracy: 0.001)
        XCTAssertEqual(result.1.y * bounds.height, expectedEnd.y, accuracy: 0.001)
    }

    func testNearVerticalGradientDoesNotProduceNaN() {
        let start = CGPoint(x: 0, y: 0)
        let end = CGPoint(x: 0.0000001, y: 1)
        let result = LinearGradientFixer.fixPoints(start: start, end: end, bounds: CGSize(width: 320, height: 60))

        XCTAssertTrue(result.0.x.isFinite)
        XCTAssertTrue(result.0.y.isFinite)
        XCTAssertTrue(result.1.x.isFinite)
        XCTAssertTrue(result.1.y.isFinite)
        // Near-vertical is treated as vertical and returned unchanged.
        XCTAssertEqual(result.0, start)
        XCTAssertEqual(result.1, end)
    }
}
