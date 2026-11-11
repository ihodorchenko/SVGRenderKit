import XCTest
@testable import SVGRenderKit

/// M2 tail — `animation-play-state: paused` shows the frame at t = 0 instead of skipping the
/// animation.
final class SVGCSSPausedAnimationTests: XCTestCase {

    private func layer(_ body: String) throws -> CALayer {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\">\(body)</svg>"
        return try SVGParser(svgString: svg, parsedRoot: nil).getLayer(overrideElements: nil)
    }

    private func mainLayer(_ root: CALayer) throws -> CALayer {
        func firstShape(_ layer: CALayer) -> CAShapeLayer? {
            if let shape = layer as? CAShapeLayer, shape.path != nil { return shape }
            for sublayer in layer.sublayers ?? [] {
                if let found = firstShape(sublayer) { return found }
            }
            return nil
        }
        return try XCTUnwrap(try XCTUnwrap(firstShape(root)).superlayer)
    }

    private func animationKeys(_ root: CALayer) -> Int {
        var count = (root.animationKeys() ?? []).count
        for sublayer in root.sublayers ?? [] { count += animationKeys(sublayer) }
        return count
    }

    func testPausedOpacityShowsTheFirstFrameWithoutAnAnimation() throws {
        let root = try layer("""
        <style>
            @keyframes fade{0%{opacity:0}100%{opacity:1}}
            .a{animation:fade 2s linear infinite paused}
        </style>
        <path class="a" d="M0 0h10v10z" fill="#f00"/>
        """)
        XCTAssertEqual(try mainLayer(root).opacity, 0, accuracy: 0.01)
        XCTAssertEqual(animationKeys(root), 0, "a paused animation is written statically, not attached")
    }

    func testPausedReverseUsesTheLastFrame() throws {
        let root = try layer("""
        <style>
            @keyframes fade{0%{opacity:0}100%{opacity:1}}
            .a{animation:fade 2s linear 1 reverse paused}
        </style>
        <path class="a" d="M0 0h10v10z" fill="#f00"/>
        """)
        XCTAssertEqual(try mainLayer(root).opacity, 1, accuracy: 0.01)
    }

    func testPausedBeforeTheActivePhaseWithoutBackwardsFillHasNoEffect() throws {
        let root = try layer("""
        <style>
            @keyframes fade{0%{opacity:0}100%{opacity:1}}
            .a{animation:fade 2s linear 1 paused;animation-delay:1s}
        </style>
        <path class="a" d="M0 0h10v10z" fill="#f00"/>
        """)
        XCTAssertEqual(try mainLayer(root).opacity, 1, accuracy: 0.01)
    }

    func testPausedBeforeTheActivePhaseWithBackwardsFillShowsTheFirstFrame() throws {
        let root = try layer("""
        <style>
            @keyframes fade{0%{opacity:.2}100%{opacity:1}}
            .a{animation:fade 2s linear 1 paused backwards;animation-delay:1s}
        </style>
        <path class="a" d="M0 0h10v10z" fill="#f00"/>
        """)
        XCTAssertEqual(try mainLayer(root).opacity, 0.2, accuracy: 0.01)
    }

    func testPausedTransformShowsTheFirstFrame() throws {
        let root = try layer("""
        <style>
            @keyframes move{0%{transform:translateX(5px)}100%{transform:translateX(20px)}}
            .a{animation:move 1s linear infinite paused}
        </style>
        <path class="a" d="M0 0h10v10z" fill="#f00"/>
        """)
        let transform = try mainLayer(root).transform
        XCTAssertEqual(transform.m41, 5, accuracy: 0.01)
    }
}
