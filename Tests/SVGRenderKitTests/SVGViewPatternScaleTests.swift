import XCTest
@testable import SVGRenderKit

@MainActor
final class SVGViewPatternScaleTests: XCTestCase {

    private let patternSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
      <defs><pattern id="p" width="2" height="2" patternUnits="userSpaceOnUse"><rect width="1" height="1" fill="#f00"/></pattern></defs>
      <rect width="10" height="10" fill="url(#p)"/>
    </svg>
    """
    private let plainSVG = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 10 10\"><rect width=\"10\" height=\"10\"/></svg>"

    private func waitUntil(_ timeout: TimeInterval = 30, _ condition: @escaping () -> Bool) {
        wait(for: [expectation(for: NSPredicate { _, _ in condition() }, evaluatedWith: nil)], timeout: timeout)
    }

    // B75: a view loaded before it has a size must re-render patterns once laid out.
    func testPatternReRenderedAfterZeroSizeLayout() {
        let view = SVGView(frame: .zero)
        view.svgString = patternSVG
        waitUntil { view.shapeLayer != nil }
        XCTAssertTrue(view.rendersScaledPaint)
        XCTAssertNil(view.renderedScale)

        view.frame = CGRect(x: 0, y: 0, width: 200, height: 200)
        view.layoutIfNeeded()
        waitUntil { (view.renderedScale ?? 0) >= 19.9 }
    }

    func testPatternReRenderedWhenViewGrows() {
        let view = SVGView(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
        view.svgString = patternSVG
        waitUntil { view.renderedScale != nil }
        XCTAssertEqual(view.renderedScale ?? 0, 2, accuracy: 0.01)

        view.frame = CGRect(x: 0, y: 0, width: 200, height: 200)
        view.layoutIfNeeded()
        waitUntil { (view.renderedScale ?? 0) >= 19.9 }
    }

    func testDocumentsWithoutPatternsAreNotReloadedOnLayout() {
        let view = SVGView(frame: .zero)
        view.svgString = plainSVG
        waitUntil { view.shapeLayer != nil }
        let layer = view.shapeLayer
        view.frame = CGRect(x: 0, y: 0, width: 200, height: 200)
        view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCTAssertFalse(view.rendersScaledPaint)
        XCTAssertTrue(view.shapeLayer === layer)
    }

    // B75/B76: loads of the same cached document at different sizes must not interfere.
    func testSameCachedDocumentInDifferentSizedViews() {
        SVGCache.s.resetCache()
        let small = SVGView(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
        let large = SVGView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        small.set(svgString: patternSVG, name: "shared", fillColors: nil)
        large.set(svgString: patternSVG, name: "shared", fillColors: nil)
        waitUntil { small.renderedScale != nil && large.renderedScale != nil }
        XCTAssertEqual(small.renderedScale ?? 0, 2, accuracy: 0.01)
        XCTAssertEqual(large.renderedScale ?? 0, 20, accuracy: 0.01)
    }

    func testManyViewsLoadWithBoundedQueue() {
        let views = (0..<60).map { _ in SVGView(frame: CGRect(x: 0, y: 0, width: 24, height: 24)) }
        views.forEach { $0.svgString = plainSVG }
        waitUntil(10) { views.allSatisfy { $0.shapeLayer != nil } }
    }

    // B131: a re-render of the same source (resize) must not restart the SMIL timeline, while loading a
    // new source must. Checked on the view's timeline epoch: the layer animation itself is not a reliable
    // probe, a headless CI simulator drops it from a layer that is not on screen.
    func testReRenderKeepsAnimationBeginTime() {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
          <defs><pattern id="p" width="2" height="2" patternUnits="userSpaceOnUse"><rect width="1" height="1" fill="#f00"/></pattern></defs>
          <rect width="10" height="10" fill="url(#p)"><animate attributeName="opacity" from="0" to="1" dur="5s"/></rect>
        </svg>
        """
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        let view = SVGView(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
        window.addSubview(view)
        window.makeKeyAndVisible()
        view.svgString = svg
        waitUntil { view.renderedScale != nil }
        let first = view.animationEpoch
        Thread.sleep(forTimeInterval: 0.3)

        view.frame = CGRect(x: 0, y: 0, width: 200, height: 200)
        view.layoutIfNeeded()
        waitUntil { (view.renderedScale ?? 0) >= 19.9 }
        XCTAssertEqual(view.animationEpoch, first, accuracy: 1e-9, "a resize re-render restarted the timeline")

        view.svgString = svg + " "
        waitUntil { view.animationEpoch > first }
        XCTAssertGreaterThan(view.animationEpoch, first, "loading a new source must restart the timeline")
    }
}
