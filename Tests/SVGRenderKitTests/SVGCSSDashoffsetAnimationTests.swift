import XCTest
@testable import SVGRenderKit

/// C (runtime) for `stroke-dashoffset`: the CSS `@keyframes`/`animation` subset the runtime plays,
/// and the SMIL `attributeName="stroke-dashoffset"` path the converter emits.
final class SVGCSSDashoffsetAnimationTests: XCTestCase {

    // MARK: Helpers

    private func layer(_ svg: String) throws -> CALayer {
        try SVGParser(svgString: svg, parsedRoot: nil).getLayer(overrideElements: nil)
    }

    private func findLayerWithAnimation(_ layer: CALayer, key: String) -> CALayer? {
        if layer.animationKeys()?.contains(key) == true { return layer }
        for sublayer in layer.sublayers ?? [] {
            if let found = findLayerWithAnimation(sublayer, key: key) { return found }
        }
        return nil
    }

    private func dashoffsetAnimation(_ root: CALayer) throws -> CAAnimation {
        let animated = try XCTUnwrap(findLayerWithAnimation(root, key: "lineDashPhase"),
                                     "no lineDashPhase animation was attached")
        return try XCTUnwrap(animated.animation(forKey: "lineDashPhase"))
    }

    private func numbers(_ animation: CAAnimation) throws -> [Double] {
        if let basic = animation as? CABasicAnimation {
            let from = try XCTUnwrap((basic.fromValue as? NSNumber)?.doubleValue)
            let to = try XCTUnwrap((basic.toValue as? NSNumber)?.doubleValue)
            return [from, to]
        }
        let keyframe = try XCTUnwrap(animation as? CAKeyframeAnimation)
        return try XCTUnwrap(keyframe.values).map {
            try XCTUnwrap(($0 as? NSNumber)?.doubleValue)
        }
    }

    private func keyTimes(_ animation: CAAnimation) throws -> [Double] {
        let keyframe = try XCTUnwrap(animation as? CAKeyframeAnimation)
        return try XCTUnwrap(keyframe.keyTimes).map(\.doubleValue)
    }

    // MARK: - CSS Animations

    func testInlineAnimationAnimatesTheDashPhase() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
            <style>@keyframes draw{0%{stroke-dashoffset:0}100%{stroke-dashoffset:-122px}}</style>
            <path d="M0 0h10v10z" fill="none" stroke="#000" stroke-dasharray="10 10"
                  style="animation:draw 2s linear infinite both"/>
        </svg>
        """
        let animation = try dashoffsetAnimation(try layer(svg))
        XCTAssertEqual(animation.duration, 2, accuracy: 1e-9)
        XCTAssertEqual(animation.repeatCount, .infinity)
        XCTAssertTrue(animation.autoreverses == false)
        XCTAssertEqual(try numbers(animation), [0, -122])
    }

    func testKeyframeAnimationUsesTheClassRuleAndKeyTimes() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
            <style>
                .spin{animation: move 3s linear infinite}
                @keyframes move{0%{stroke-dashoffset:0}25%{stroke-dashoffset:10}100%{stroke-dashoffset:40}}
            </style>
            <path class="spin" d="M0 0h10v10z" fill="none" stroke="#000" stroke-dasharray="5 5"/>
        </svg>
        """
        let animation = try dashoffsetAnimation(try layer(svg))
        XCTAssertEqual(try numbers(animation), [0, 10, 40])
        XCTAssertEqual(try keyTimes(animation), [0, 0.25, 1])
        XCTAssertEqual(animation.repeatCount, .infinity)
        XCTAssertEqual((animation as? CAKeyframeAnimation)?.timingFunctions?.count, 2)
    }

    func testMissingEndpointsComeFromTheBaseDashoffset() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
            <style>@keyframes pulse{50%{stroke-dashoffset:20}}</style>
            <path d="M0 0h10v10z" fill="none" stroke="#000" stroke-dashoffset="5"
                  stroke-dasharray="5 5" style="animation:pulse 1s linear infinite"/>
        </svg>
        """
        let animation = try dashoffsetAnimation(try layer(svg))
        XCTAssertEqual(try numbers(animation), [5, 20, 5], "implicit 0%/100% come from the attribute")
        XCTAssertEqual(try keyTimes(animation), [0, 0.5, 1])
    }

    func testReverseDirectionReversesValuesAndTimes() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
            <style>@keyframes back{0%{stroke-dashoffset:0}50%{stroke-dashoffset:10}100%{stroke-dashoffset:20}}</style>
            <path d="M0 0h10v10z" fill="none" stroke="#000" stroke-dasharray="5 5"
                  style="animation:back 1s linear infinite reverse"/>
        </svg>
        """
        let animation = try dashoffsetAnimation(try layer(svg))
        XCTAssertEqual(try numbers(animation), [20, 10, 0])
        XCTAssertEqual(try keyTimes(animation), [0, 0.5, 1])
    }

    func testAlternateInfiniteUsesAutoreverses() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
            <style>@keyframes alt{0%{stroke-dashoffset:0}100%{stroke-dashoffset:12}}</style>
            <path d="M0 0h10v10z" fill="none" stroke="#000" stroke-dasharray="5 5"
                  style="animation:alt 1s linear infinite alternate"/>
        </svg>
        """
        let animation = try dashoffsetAnimation(try layer(svg))
        XCTAssertEqual(animation.repeatCount, .infinity)
        XCTAssertTrue(animation.autoreverses)
        XCTAssertEqual(try numbers(animation), [0, 12])
    }

    func testAlternateReverseInfiniteStartsAtTheFarKeyframe() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
            <style>@keyframes altR{0%{stroke-dashoffset:0}100%{stroke-dashoffset:12}}</style>
            <path d="M0 0h10v10z" fill="none" stroke="#000" stroke-dasharray="5 5"
                  style="animation:altR 1s linear infinite alternate-reverse"/>
        </svg>
        """
        let animation = try dashoffsetAnimation(try layer(svg))
        XCTAssertTrue(animation.autoreverses)
        XCTAssertEqual(try numbers(animation), [12, 0])
    }

    func testFiniteAlternateIsExpandedIntoTimeline() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
            <style>@keyframes pair{0%{stroke-dashoffset:0}100%{stroke-dashoffset:10}}</style>
            <path d="M0 0h10v10z" fill="none" stroke="#000" stroke-dasharray="5 5"
                  style="animation:pair 1s linear 2 alternate both"/>
        </svg>
        """
        let animation = try dashoffsetAnimation(try layer(svg))
        XCTAssertEqual(animation.repeatCount, 1)
        XCTAssertEqual(animation.duration, 2, accuracy: 1e-9, "two 1 s iterations are baked")
        XCTAssertEqual(try numbers(animation), [0, 10, 0])
        XCTAssertEqual(try keyTimes(animation), [0, 0.5, 1])
        XCTAssertTrue(animation.autoreverses == false)
        XCTAssertEqual((animation as? CAKeyframeAnimation)?.fillMode, .both)
    }

    func testDelayFromALonghandAndShorthandCascade() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
            <style>
                .one{animation: d 2s linear infinite}
                .two{animation-delay:1.5s}
                @keyframes d{0%{stroke-dashoffset:0}100%{stroke-dashoffset:10}}
            </style>
            <path class="one two" d="M0 0h10v10z" fill="none" stroke="#000" stroke-dasharray="5 5"/>
        </svg>
        """
        let before = CACurrentMediaTime()
        let animation = try dashoffsetAnimation(try layer(svg))
        let begin = animation.beginTime - before
        XCTAssertEqual(begin, 1.5, accuracy: 0.5, "animation-delay from the later rule")
        XCTAssertEqual(animation.duration, 2, accuracy: 1e-9)
    }

    func testOpacityKeyframesDoNotCreateADashPhaseAnimation() throws {
        // `opacity` is part of the M2 property set, but it must not turn into a dash-phase animation.
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
            <style>@keyframes fade{0%{opacity:0}100%{opacity:1}}</style>
            <path d="M0 0h10v10z" fill="#f00" style="animation:fade 1s linear infinite"/>
        </svg>
        """
        let root = try layer(svg)
        XCTAssertNil(findLayerWithAnimation(root, key: "lineDashPhase"))
        XCTAssertNotNil(findLayerWithAnimation(root, key: "opacity"))
    }

    func testDescendantSelectorAnimationApplies() throws {
        // M1: the document-wide stylesheet matches descendant selectors, so an animation declared
        // as `#root path{...}` reaches the path (this is what `anim.svg` needs at runtime).
        let svg = """
        <svg id="root" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
            <style>
                #root path{animation: d 1s linear infinite}
                @keyframes d{0%{stroke-dashoffset:0}100%{stroke-dashoffset:10}}
            </style>
            <path d="M0 0h10v10z" fill="none" stroke="#000" stroke-dasharray="5 5"/>
        </svg>
        """
        let animation = try dashoffsetAnimation(try layer(svg))
        XCTAssertEqual(animation.duration, 1, accuracy: 1e-9)
        XCTAssertEqual(try numbers(animation), [0, 10])
    }

    func testSpecParsingCoversTheShorthand() {
        let specs = SVGCSSAnimations.specs(from: [
            (property: "animation", value: "lock 1s cubic-bezier(1,-.43,0,1.29) both infinite alternate-reverse"),
        ])
        XCTAssertEqual(specs.count, 1)
        XCTAssertEqual(specs[0].name, "lock")
        XCTAssertEqual(specs[0].duration, 1, accuracy: 1e-9)
        XCTAssertEqual(specs[0].timingFunction, "cubic-bezier(1,-.43,0,1.29)")
        XCTAssertEqual(specs[0].fillMode, "both")
        XCTAssertEqual(specs[0].iterationCount, .infinity)
        XCTAssertEqual(specs[0].direction, "alternate-reverse")

        let indexed = SVGCSSAnimations.specs(from: [
            (property: "animation", value: "a 2s linear infinite, b 3s ease-in 2 both"),
            (property: "animation-delay", value: "0.5s, 1s"),
        ])
        XCTAssertEqual(indexed.map(\.name), ["a", "b"])
        XCTAssertEqual(indexed.map(\.duration), [2, 3])
        XCTAssertEqual(indexed.map(\.delay), [0.5, 1])
        XCTAssertEqual(indexed.map(\.fillMode), ["none", "both"])
    }

    // MARK: - SMIL

    func testSMILDashoffsetAnimationAnimatesTheDashPhase() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
            <path d="M0 0h10v10z" fill="none" stroke="#000" stroke-dasharray="5 5">
                <animate attributeName="stroke-dashoffset" values="0;10" dur="1s" repeatCount="indefinite"/>
            </path>
        </svg>
        """
        let animation = try dashoffsetAnimation(try layer(svg))
        XCTAssertEqual(animation.duration, 1, accuracy: 1e-9)
        XCTAssertEqual(animation.repeatCount, .infinity)
        XCTAssertEqual(try numbers(animation), [0, 10])
    }
}
