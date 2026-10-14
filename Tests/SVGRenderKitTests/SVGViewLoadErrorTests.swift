import XCTest
@testable import SVGRenderKit

/// B96 — a failed load must not leave the previous document on screen (a reused cell
/// would show a foreign icon) and must be observable, not just logged.
@MainActor
final class SVGViewLoadErrorTests: XCTestCase {

    private let markup = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 10 10\"><rect width=\"10\" height=\"10\"/></svg>"

    private func waitUntil(_ timeout: TimeInterval = 30, _ condition: @escaping () -> Bool) {
        wait(for: [expectation(for: NSPredicate { _, _ in condition() }, evaluatedWith: nil)], timeout: timeout)
    }

    private func makeView() -> SVGView { SVGView(frame: CGRect(x: 0, y: 0, width: 20, height: 20)) }

    func testFailedLoadDropsStaleContentAndReportsError() {
        let view = makeView()
        view.svgString = markup
        waitUntil { view.shapeLayer != nil }

        var reported: Error?
        view.onLoadError = { reported = $0 }
        view.svgString = "this is not svg"
        waitUntil { reported != nil }

        XCTAssertNotNil(reported)
        XCTAssertNil(view.shapeLayer, "a failed load must not keep the previous document")
        XCTAssertNil(view.parser)
        XCTAssertEqual(view.contentView.layer.sublayers?.count ?? 0, 0)
        XCTAssertNil(view.svgString, "the reported source must match what is drawn (nothing)")
    }

    func testFailedInitialLoadReportsError() {
        let view = makeView()
        var reported: Error?
        view.onLoadError = { reported = $0 }
        view.svgString = "%%%not xml%%%"
        waitUntil { reported != nil }

        XCTAssertNotNil(reported)
        XCTAssertNil(view.shapeLayer)
    }

    func testSuccessfulLoadDoesNotReportError() {
        let view = makeView()
        var reported: Error?
        view.onLoadError = { reported = $0 }
        view.svgString = markup
        waitUntil { view.shapeLayer != nil }

        XCTAssertNotNil(view.shapeLayer)
        XCTAssertNil(reported)
    }
}
