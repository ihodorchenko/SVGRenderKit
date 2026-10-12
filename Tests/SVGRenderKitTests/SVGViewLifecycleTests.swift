import XCTest
@testable import SVGRenderKit

@MainActor
final class SVGViewLifecycleTests: XCTestCase {

    private let markup = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 10 10\"><rect width=\"10\" height=\"10\"/></svg>"

    private func waitUntil(_ timeout: TimeInterval = 30, _ condition: @escaping () -> Bool) {
        wait(for: [expectation(for: NSPredicate { _, _ in condition() }, evaluatedWith: nil)], timeout: timeout)
    }

    private func makeView() -> SVGView { SVGView(frame: CGRect(x: 0, y: 0, width: 20, height: 20)) }

    // B80: theme-change reload must also cover views fed through `svgString` / `svgData`.
    func testUpdateReloadsSvgStringView() {
        let view = makeView()
        view.svgString = markup
        waitUntil { view.parser != nil }

        view.parser = nil
        view.shapeLayer = nil
        view.updateSvg()
        waitUntil { view.parser != nil && view.shapeLayer != nil }
    }

    func testUpdateReloadsSvgDataViewAndLastSourceWins() {
        let view = makeView()
        view.svgString = markup
        view.set(svgData: Data(markup.utf8), overrideElements: nil)
        XCTAssertNil(view.svgString, "a newer source must replace the previous string source")
        waitUntil { view.parser != nil }

        view.parser = nil
        view.updateSvg()
        waitUntil { view.parser != nil }
    }

    // B78: assigning nil clears the rendered content and invalidates an in-flight load.
    func testNilSvgStringClearsView() {
        let view = makeView()
        view.svgString = markup
        waitUntil { view.shapeLayer != nil }

        view.svgString = nil
        XCTAssertNil(view.shapeLayer)
        XCTAssertNil(view.parser)
        XCTAssertEqual(view.contentView.layer.sublayers?.count ?? 0, 0)

        view.updateSvg()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCTAssertNil(view.shapeLayer, "nothing to reload after clear")
    }

    func testNilSVGNameClearsView() {
        let view = makeView()
        view.svgString = markup
        waitUntil { view.shapeLayer != nil }
        view.SVGName = nil   // inactive property: must not clear the string source
        XCTAssertNotNil(view.shapeLayer)

        view.SVGName = "missing.svg"
        view.SVGName = nil
        XCTAssertNil(view.shapeLayer)
    }

    func testNilDuringInFlightLoadDiscardsResult() {
        let view = makeView()
        view.svgString = markup
        view.svgString = nil
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCTAssertNil(view.shapeLayer)
    }

    // B79: nib/storyboard decoding must not crash.
    @MainActor func testInitCoderDoesNotCrash() throws {
        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        makeView().encode(with: archiver)
        archiver.finishEncoding()
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: archiver.encodedData)
        unarchiver.requiresSecureCoding = false
        let view = SVGView(coder: unarchiver)
        XCTAssertNotNil(view)
        view?.svgString = markup
        waitUntil { view?.shapeLayer != nil }
    }
}

// B73/B74: thread-safety.
@MainActor
final class SVGThreadSafetyTests: XCTestCase {
    private let markup = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 10 10\"><rect width=\"10\" height=\"10\"/></svg>"

    private struct UncheckedSendable<Value>: @unchecked Sendable {
        let value: Value
    }

    /// Runs `body` on a background queue. The main-actor isolation is erased on purpose:
    /// these tests verify that the public API is safe to call from any thread.
    private func runOffMain(_ body: @escaping @MainActor () -> Void) {
        let erased = UncheckedSendable(value: unsafeBitCast(body, to: (() -> Void).self))
        DispatchQueue.global().async { erased.value() }
    }

    func testLoadRequestedFromBackgroundThreadRenders() {
        let view = SVGView(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
        let markup = self.markup
        runOffMain { view.svgString = markup }
        wait(for: [expectation(for: NSPredicate { _, _ in view.shapeLayer != nil }, evaluatedWith: nil)], timeout: 5)
    }

    func testLastBackgroundRequestWinsOverStale() {
        let view = SVGView(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
        let done = expectation(description: "bg")
        let markup = self.markup
        runOffMain {
            view.svgString = markup
            view.svgString = nil
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCTAssertNil(view.shapeLayer)
    }

    func testCacheFlagAndResetAreSafeUnderConcurrency() {
        let original = SVGConfiguration.shared.isParserCacheEnabled
        defer { SVGConfiguration.shared.isParserCacheEnabled = original }
        let markup = self.markup
        DispatchQueue.concurrentPerform(iterations: 2000) { i in
            switch i % 4 {
            case 0: SVGConfiguration.shared.isParserCacheEnabled = (i % 8 == 0)
            case 1: _ = SVGConfiguration.shared.isParserCacheEnabled
            case 2: SVGCache.s.resetCache()
            default: _ = try? SVGParser.getParser(svgString: markup, name: "k\(i % 5)")
            }
        }
    }
}
