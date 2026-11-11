import XCTest
@testable import SVGRenderKit

/// M3.3 / M2 tail — `steps()`, `linear()` and overshooting `cubic-bezier()` easings are sampled
/// into keyframes because Core Animation cannot express them as a timing function.
final class SVGCSSEasingTests: XCTestCase {

    private func layer(_ body: String) throws -> CALayer {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\">\(body)</svg>"
        return try SVGParser(svgString: svg, parsedRoot: nil).getLayer(overrideElements: nil)
    }

    private func animation(_ root: CALayer, key: String) throws -> CAAnimation {
        func find(_ layer: CALayer) -> CALayer? {
            if layer.animationKeys()?.contains(key) == true { return layer }
            for sublayer in layer.sublayers ?? [] {
                if let found = find(sublayer) { return found }
            }
            return nil
        }
        let animated = try XCTUnwrap(find(root), "no \(key) animation")
        return try XCTUnwrap(animated.animation(forKey: key))
    }

    private func numbers(_ animation: CAAnimation) throws -> [Double] {
        if let basic = animation as? CABasicAnimation {
            return [try XCTUnwrap((basic.fromValue as? NSNumber)?.doubleValue),
                    try XCTUnwrap((basic.toValue as? NSNumber)?.doubleValue)]
        }
        let keyframe = try XCTUnwrap(animation as? CAKeyframeAnimation)
        return try XCTUnwrap(keyframe.values).map { try XCTUnwrap(($0 as? NSNumber)?.doubleValue) }
    }

    private func keyTimes(_ animation: CAAnimation) throws -> [Double] {
        return try XCTUnwrap((animation as? CAKeyframeAnimation)?.keyTimes).map(\.doubleValue)
    }

    private func opacityAnimation(_ timing: String) throws -> CAAnimation {
        return try animation(try layer("""
        <style>
            @keyframes f{0%{opacity:0}100%{opacity:1}}
            .a{animation:f 1s \(timing) infinite}
        </style>
        <path class="a" d="M0 0h10v10z" fill="#f00"/>
        """), key: "opacity")
    }

    func testStepsJumpEndIsSampled() throws {
        let animation = try opacityAnimation("steps(4, jump-end)")
        let values = try numbers(animation)
        XCTAssertEqual(try XCTUnwrap(values.last), 1, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(values.first), 0, accuracy: 1e-9)
        XCTAssertEqual(try keyTimes(animation).count, values.count)
        // Four constant steps: each value appears twice.
        XCTAssertEqual(values.filter { abs($0) < 1e-9 }.count, 3)
        XCTAssertEqual(values.filter { abs($0 - 0.25) < 1e-9 }.count, 2)
        XCTAssertEqual(values.filter { abs($0 - 0.5) < 1e-9 }.count, 2)
    }

    func testStepsJumpStartJumpsAtZero() throws {
        let animation = try opacityAnimation("steps(2, jump-start)")
        let values = try numbers(animation)
        XCTAssertEqual(values.count, 6)
        XCTAssertEqual(values[1], 0.5, accuracy: 1e-9, "the first step starts at 1/2 after the jump at 0")
        XCTAssertEqual(try XCTUnwrap(values.last), 1, accuracy: 1e-9)
    }

    func testStepsShortFormDefaultsToJumpEnd() throws {
        let animation = try opacityAnimation("steps(2)")
        let values = try numbers(animation)
        XCTAssertEqual(try XCTUnwrap(values.last), 1, accuracy: 1e-9)
        XCTAssertGreaterThan(values.count, 2)
    }

    func testInvalidStepsFallsBackToLinear() throws {
        let animation = try opacityAnimation("steps(1, jump-none)")
        let values = try numbers(animation)
        XCTAssertEqual(values.count, 2, "a single jump-none step is invalid, the fallback is a plain segment")
    }

    func testOvershootingCubicBezierIsSampled() throws {
        let animation = try opacityAnimation("cubic-bezier(0.34, 1.56, 0.64, 1)")
        let values = try numbers(animation)
        XCTAssertGreaterThan(values.count, 20)
        XCTAssertEqual(try XCTUnwrap(values.last), 1, accuracy: 1e-9)
        XCTAssertGreaterThan(values.max() ?? 0, 1.02, "the sampled curve overshoots 1")
    }

    func testLinearEasingIsSampled() throws {
        let animation = try opacityAnimation("linear(0, 0.2 25%, 1)")
        let values = try numbers(animation)
        let times = try keyTimes(animation)
        XCTAssertGreaterThan(values.count, 2)
        XCTAssertEqual(try XCTUnwrap(values.first), 0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(values.last), 1, accuracy: 1e-9)
        let quarter = times.firstIndex { abs($0 - 0.25) < 0.01 }
        XCTAssertNotNil(quarter)
        if let quarter = quarter {
            XCTAssertEqual(values[quarter], 0.2, accuracy: 0.02)
        }
    }

    func testStepsOnTransformKeepsValidMatrices() throws {
        let root = try layer("""
        <style>
            @keyframes move{0%{transform:translateX(0)}100%{transform:translateX(10px)}}
            .a{animation:move 1s steps(3) infinite}
        </style>
        <path class="a" d="M0 0h10v10z" fill="#f00"/>
        """)
        let animation = try animation(root, key: "transform")
        let keyframe = try XCTUnwrap(animation as? CAKeyframeAnimation)
        let values = try XCTUnwrap(keyframe.values)
        XCTAssertGreaterThan(values.count, 2)
        for value in values {
            let matrix = try XCTUnwrap((value as? NSValue)?.caTransform3DValue)
            XCTAssertTrue(matrix.m41.isFinite)
        }
    }
}
