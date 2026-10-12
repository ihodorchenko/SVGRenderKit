import XCTest
@testable import SVGRenderKit

final class SVGViewLifecycleTests: XCTestCase {

    private let markup = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 10 10\"><rect width=\"10\" height=\"10\"/></svg>"

    private func waitUntil(_ timeout: TimeInterval = 5, _ condition: @escaping () -> Bool) {
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
    func testInitCoderDoesNotCrash() throws {
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
