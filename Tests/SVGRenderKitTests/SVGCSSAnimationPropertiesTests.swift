import XCTest
@testable import SVGRenderKit

/// M2 — the runtime CSS Animations property set: `opacity`, `fill`, `stroke` and `transform`
/// (plus `stroke-dashoffset`, covered by `SVGCSSDashoffsetAnimationTests`).
final class SVGCSSAnimationPropertiesTests: XCTestCase {

    // MARK: Helpers

    private func layer(_ body: String) throws -> CALayer {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\">\(body)</svg>"
        return try SVGParser(svgString: svg, parsedRoot: nil).getLayer(overrideElements: nil)
    }

    private func find(_ layer: CALayer, key: String) -> CALayer? {
        if layer.animationKeys()?.contains(key) == true { return layer }
        for sublayer in layer.sublayers ?? [] {
            if let found = find(sublayer, key: key) { return found }
        }
        return nil
    }

    private func animation(_ layer: CALayer, key: String) throws -> CAAnimation {
        let animated = try XCTUnwrap(find(layer, key: key), "no \(key) animation attached")
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

    private func matrices(_ animation: CAAnimation) throws -> [CATransform3D] {
        if let basic = animation as? CABasicAnimation {
            return [try XCTUnwrap((basic.fromValue as? NSValue)?.caTransform3DValue),
                    try XCTUnwrap((basic.toValue as? NSValue)?.caTransform3DValue)]
        }
        let keyframe = try XCTUnwrap(animation as? CAKeyframeAnimation)
        return try XCTUnwrap(keyframe.values).map {
            try XCTUnwrap(($0 as? NSValue)?.caTransform3DValue)
        }
    }

    private func keyTimes(_ animation: CAAnimation) throws -> [Double] {
        return try XCTUnwrap((animation as? CAKeyframeAnimation)?.keyTimes).map(\.doubleValue)
    }

    private func assertColor(_ color: CGColor, _ r: CGFloat, _ g: CGFloat, _ b: CGFloat,
                             file: StaticString = #filePath, line: UInt = #line) {
        let converted = UIColor(cgColor: color)
        var rr: CGFloat = 0, gg: CGFloat = 0, bb: CGFloat = 0, aa: CGFloat = 0
        converted.getRed(&rr, green: &gg, blue: &bb, alpha: &aa)
        XCTAssertEqual(rr, r, accuracy: 0.02, file: file, line: line)
        XCTAssertEqual(gg, g, accuracy: 0.02, file: file, line: line)
        XCTAssertEqual(bb, b, accuracy: 0.02, file: file, line: line)
    }

    // MARK: Opacity

    func testOpacityAnimation() throws {
        let animation = try animation(try layer("""
        <style>@keyframes fade{0%{opacity:0}100%{opacity:1}}</style>
        <path d="M0 0h10v10z" fill="#f00" style="animation:fade 2s linear infinite"/>
        """), key: "opacity")
        XCTAssertEqual(animation.duration, 2, accuracy: 1e-9)
        XCTAssertEqual(animation.repeatCount, .infinity)
        XCTAssertEqual(try numbers(animation), [0, 1])
    }

    func testOpacityImplicitEndpointsFromBase() throws {
        let animation = try animation(try layer("""
        <style>@keyframes dim{50%{opacity:.5}}</style>
        <path d="M0 0h10v10z" fill="#f00" opacity=".8" style="animation:dim 1s linear infinite"/>
        """), key: "opacity")
        let values = try numbers(animation)
        XCTAssertEqual(values.count, 3)
        XCTAssertEqual(values[0], 0.8, accuracy: 1e-5)
        XCTAssertEqual(values[1], 0.5, accuracy: 1e-5)
        XCTAssertEqual(values[2], 0.8, accuracy: 1e-5)
        XCTAssertEqual(try keyTimes(animation), [0, 0.5, 1])
    }

    func testFiniteAlternateIsExpanded() throws {
        let animation = try animation(try layer("""
        <style>@keyframes blink{0%{opacity:0}100%{opacity:1}}</style>
        <path d="M0 0h10v10z" fill="#f00" style="animation:blink 1s linear 2 alternate"/>
        """), key: "opacity")
        XCTAssertEqual(animation.repeatCount, 1)
        XCTAssertEqual(animation.duration, 2, accuracy: 1e-9)
        XCTAssertEqual(try numbers(animation), [0, 1, 0])
        XCTAssertEqual(try keyTimes(animation), [0, 0.5, 1])
    }

    func testPerKeyframeTimingFunctions() throws {
        let animation = try animation(try layer("""
        <style>@keyframes stepped{0%{opacity:0;animation-timing-function:ease-in}50%{opacity:.5}100%{opacity:1}}</style>
        <path d="M0 0h10v10z" fill="#f00" style="animation:stepped 1s linear infinite"/>
        """), key: "opacity")
        let keyframe = try XCTUnwrap(animation as? CAKeyframeAnimation)
        XCTAssertEqual(keyframe.timingFunctions?.count, 2)
        XCTAssertEqual(keyframe.timingFunctions?[0], CAMediaTimingFunction(name: .easeIn))
    }

    // MARK: Fill and stroke

    func testFillAnimation() throws {
        let animation = try animation(try layer("""
        <style>@keyframes paint{0%{fill:#ff0000}100%{fill:#0000ff}}</style>
        <path d="M0 0h10v10z" style="animation:paint 1s linear infinite"/>
        """), key: "fillColor")
        let values = try XCTUnwrap((animation as? CABasicAnimation))
        assertColor(try XCTUnwrap(values.fromValue) as! CGColor, 1, 0, 0)
        assertColor(try XCTUnwrap(values.toValue) as! CGColor, 0, 0, 1)
    }

    func testStrokeAnimation() throws {
        let animation = try animation(try layer("""
        <style>@keyframes ink{0%{stroke:#00ff00}100%{stroke:#0000ff}}</style>
        <path d="M0 0h10v10z" fill="none" stroke="#00ff00" stroke-width="2" style="animation:ink 1s linear infinite"/>
        """), key: "strokeColor")
        XCTAssertEqual(animation.duration, 1, accuracy: 1e-9)
    }

    func testFillOnAGradientIsSkipped() throws {
        let root = try layer("""
        <defs><linearGradient id="g"><stop offset="0" stop-color="#f00"/><stop offset="1" stop-color="#00f"/></linearGradient></defs>
        <style>@keyframes paint{0%{fill:#ff0000}100%{fill:#0000ff}}</style>
        <path d="M0 0h10v10z" fill="url(#g)" style="animation:paint 1s linear infinite"/>
        """)
        XCTAssertNil(find(root, key: "fillColor"),
                     "a paint server and a color are not interpolable, so the animation is skipped")
    }

    // MARK: Transform

    func testTransformTranslate() throws {
        let animation = try animation(try layer("""
        <style>@keyframes move{0%{transform:translateX(0)}100%{transform:translateX(10px)}}</style>
        <path d="M0 0h10v10z" fill="#f00" style="animation:move 1s linear infinite"/>
        """), key: "transform")
        let matrices = try matrices(animation)
        XCTAssertEqual(matrices[0].m41, 0, accuracy: 1e-6)
        XCTAssertEqual(matrices[1].m41, 10, accuracy: 1e-6)
    }

    func testTransformImplicitEndpointFromTheAttribute() throws {
        let animation = try animation(try layer("""
        <style>@keyframes move{50%{transform:translate(20px, 0)}}</style>
        <path d="M0 0h10v10z" fill="#f00" transform="translate(5, 0)" style="animation:move 1s linear infinite"/>
        """), key: "transform")
        let matrices = try matrices(animation)
        XCTAssertEqual(matrices.count, 3)
        XCTAssertEqual(matrices[0].m41, 5, accuracy: 1e-6, "0% comes from the transform attribute")
        XCTAssertEqual(matrices[1].m41, 20, accuracy: 1e-6)
        XCTAssertEqual(matrices[2].m41, 5, accuracy: 1e-6)
    }

    func testTransformListIsComposed() throws {
        let animation = try animation(try layer("""
        <style>@keyframes grow{0%{transform:translate(0, 0) scale(1)}100%{transform:translate(10px, 0) scale(2)}}</style>
        <path d="M0 0h10v10z" fill="#f00" style="animation:grow 1s linear infinite"/>
        """), key: "transform")
        let matrices = try matrices(animation)
        XCTAssertEqual(matrices[0].m11, 1, accuracy: 1e-6)
        XCTAssertEqual(matrices[1].m11, 2, accuracy: 1e-6)
        XCTAssertEqual(matrices[1].m41, 10, accuracy: 1e-6)
    }

    func testMultipleAnimatedPropertiesInOneAnimation() throws {
        let root = try layer("""
        <style>@keyframes combo{0%{opacity:0;transform:translateX(0)}100%{opacity:1;transform:translateX(10px)}}</style>
        <path d="M0 0h10v10z" fill="#f00" style="animation:combo 1s linear infinite"/>
        """)
        XCTAssertNotNil(find(root, key: "opacity"))
        XCTAssertNotNil(find(root, key: "transform"))
    }

    // MARK: Groups

    func testGroupOpacityAnimation() throws {
        let animation = try animation(try layer("""
        <style>@keyframes fade{0%{opacity:0}100%{opacity:1}}</style>
        <g style="animation:fade 1s linear infinite"><path d="M0 0h10v10z" fill="#f00"/></g>
        """), key: "opacity")
        XCTAssertEqual(try numbers(animation), [0, 1])
    }

    func testGroupFillAnimationIsSkipped() throws {
        let root = try layer("""
        <style>@keyframes paint{0%{fill:#ff0000}100%{fill:#0000ff}}</style>
        <g style="animation:paint 1s linear infinite"><path d="M0 0h10v10z"/></g>
        """)
        XCTAssertNil(find(root, key: "fillColor"),
                     "fill is inherited and cannot be animated on a group layer")
    }

    // MARK: Degradation

    func testUnsupportedPropertyIsSkipped() throws {
        let root = try layer("""
        <style>@keyframes thick{0%{stroke-width:1}100%{stroke-width:5}}</style>
        <path d="M0 0h10v10z" fill="none" stroke="#000" style="animation:thick 1s linear infinite"/>
        """)
        for key in ["opacity", "fillColor", "strokeColor", "transform", "lineDashPhase"] {
            XCTAssertNil(find(root, key: key), "\(key) must not be animated")
        }
    }

    func testImportantAnimationDeclarationBeatsNormalInlineStyle() throws {
        let root = try layer("""
        <style>
            .a{animation: slow 1s linear infinite !important}
            @keyframes slow{0%{opacity:0}100%{opacity:1}}
        </style>
        <path class="a" d="M0 0h10v10z" fill="#f00" style="animation:slow 5s linear infinite"/>
        """)
        let animation = try animation(root, key: "opacity")
        XCTAssertEqual(animation.duration, 1, accuracy: 1e-9, "!important wins over the inline shorthand")
    }
}
