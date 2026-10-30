import XCTest
import UIKit
@testable import SVGRenderKit

/// A document loaded before the view is in a window used to lose its SMIL animations:
/// Core Animation drops the animations of a layer tree that is committed while the tree has
/// no window ancestor, and they never come back when the view is attached later. Every view
/// fed from `viewDidLoad` — or a collection view cell configured before being enqueued —
/// hits that order, so animated documents were silently static in the most common usage.
@MainActor
final class SVGViewAnimationAttachTests: XCTestCase {

    private let animatedMarkup = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
      <rect width="10" height="10" fill="#00f">
        <animateTransform attributeName="transform" type="translate" values="0 0;0 4" dur="2s" repeatCount="indefinite"/>
      </rect>
    </svg>
    """

    private func waitUntil(_ timeout: TimeInterval = 30, _ condition: @escaping () -> Bool) {
        wait(for: [expectation(for: NSPredicate { _, _ in condition() }, evaluatedWith: nil)], timeout: timeout)
    }

    private func pump(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func animatedLayerCount(_ layer: CALayer) -> Int {
        var count = layer.animationKeys()?.count ?? 0
        for sublayer in layer.sublayers ?? [] { count += animatedLayerCount(sublayer) }
        return count
    }

    private func transformAnimatedLayer(_ layer: CALayer) -> CALayer? {
        if (layer.animationKeys() ?? []).contains("transform") { return layer }
        for sublayer in layer.sublayers ?? [] {
            if let found = transformAnimatedLayer(sublayer) { return found }
        }
        return nil
    }

    /// The regression: render first (no window yet), attach to a window afterwards, and the
    /// animation must both survive and actually run.
    func testAnimationsSurviveRenderingBeforeTheViewIsInAWindow() {
        let view = SVGView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        view.svgString = animatedMarkup
        waitUntil { view.shapeLayer != nil }

        // A run-loop turn commits the windowless layer tree — this is where Core Animation
        // used to drop the animations.
        pump(0.1)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 80, height: 80))
        window.addSubview(view)
        window.makeKeyAndVisible()
        pump(0.3)

        let shapeLayer = try? XCTUnwrap(view.shapeLayer)
        XCTAssertNotNil(shapeLayer)
        guard let shapeLayer = shapeLayer else { return }
        XCTAssertGreaterThan(
            animatedLayerCount(shapeLayer), 0,
            "the document's CAAnimations were dropped because it was rendered before the view had a window")

        guard let animated = transformAnimatedLayer(shapeLayer) else {
            XCTFail("the transform animation is not attached to any layer")
            return
        }
        let before = (animated.presentation() ?? animated).transform.m42
        pump(0.4)
        let after = (animated.presentation() ?? animated).transform.m42
        XCTAssertNotEqual(before, after, accuracy: 0.01, "the animation is attached but does not run")
    }

    /// The ordinary order (source set when the view is already in a window) must keep working.
    func testAnimationsSurviveWhenTheViewIsAlreadyInAWindow() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 80, height: 80))
        let view = SVGView(frame: window.bounds)
        window.addSubview(view)
        window.makeKeyAndVisible()
        // Let the window's render tree come up: a document committed in the same run-loop turn
        // as the first visible window is a test-environment race, not the app's ordering.
        pump(0.2)
        view.svgString = animatedMarkup
        waitUntil { view.shapeLayer != nil }
        pump(0.3)

        guard let shapeLayer = view.shapeLayer else {
            XCTFail("no layer built")
            return
        }
        XCTAssertGreaterThan(animatedLayerCount(shapeLayer), 0)
    }

    /// A static document must not trigger the window-attach rebuild at all.
    func testStaticDocumentIsNotRebuiltOnWindowAttach() {
        let staticMarkup = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><rect width="10" height="10" fill="#f00"/></svg>
        """
        let view = SVGView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        view.svgString = staticMarkup
        waitUntil { view.shapeLayer != nil }
        let firstLayer = view.shapeLayer
        pump(0.1)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 80, height: 80))
        window.addSubview(view)
        window.makeKeyAndVisible()
        pump(0.3)
        XCTAssertTrue(view.shapeLayer === firstLayer, "a document without animations was needlessly rebuilt")
    }
}
