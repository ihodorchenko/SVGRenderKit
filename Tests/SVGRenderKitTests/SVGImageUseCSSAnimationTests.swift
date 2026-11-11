import XCTest
@testable import SVGRenderKit

/// M2 tail — CSS animations on `<image>` and `<use>` (opacity/transform).
final class SVGImageUseCSSAnimationTests: XCTestCase {

    private let png = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg=="

    private func layer(_ body: String, reduceMotion: Bool = false) throws -> CALayer {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\">\(body)</svg>"
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        parser.root.svgElement.options.reduceMotion = reduceMotion
        return try parser.getLayer(overrideElements: nil)
    }

    private func find(_ layer: CALayer, key: String) -> CALayer? {
        if layer.animationKeys()?.contains(key) == true { return layer }
        for sublayer in layer.sublayers ?? [] {
            if let found = find(sublayer, key: key) { return found }
        }
        return nil
    }

    private func layers(_ layer: CALayer) -> [CALayer] {
        var result = [layer]
        for sublayer in layer.sublayers ?? [] { result += layers(sublayer) }
        return result
    }

    // MARK: <image>

    func testImageOpacityAnimation() throws {
        let root = try layer("""
        <style>@keyframes fade{0%{opacity:0}100%{opacity:1}}</style>
        <image href="\(png)" width="10" height="10" style="animation:fade 1s linear infinite"/>
        """)
        XCTAssertNotNil(find(root, key: "opacity"))
    }

    func testImageTransformAnimationAndStaticCSSTransform() throws {
        let root = try layer("""
        <style>
            @keyframes move{0%{transform:translateX(0)}100%{transform:translateX(10px)}}
            .i{transform:translate(5px, 0);animation:move 1s linear infinite}
        </style>
        <image class="i" href="\(png)" width="10" height="10"/>
        """)
        XCTAssertNotNil(find(root, key: "transform"))
        let staticLayer = try XCTUnwrap(layers(root).first { abs($0.transform.m41 - 5) < 0.01 })
        XCTAssertEqual(staticLayer.transform.m41, 5, accuracy: 0.01, "the CSS transform replaces the attribute")
    }

    // MARK: <use>

    func testUseOpacityAnimation() throws {
        let root = try layer("""
        <style>@keyframes fade{0%{opacity:0}100%{opacity:1}}</style>
        <defs><rect id="r" width="10" height="10" fill="#f00"/></defs>
        <use href="#r" style="animation:fade 1s linear infinite"/>
        """)
        XCTAssertNotNil(find(root, key: "opacity"))
    }

    func testUseTransformAnimation() throws {
        let root = try layer("""
        <style>
            @keyframes move{0%{transform:translateX(0)}100%{transform:translateX(10px)}}
            .u{animation:move 1s linear infinite}
        </style>
        <defs><rect id="r" width="10" height="10" fill="#f00"/></defs>
        <use class="u" href="#r"/>
        """)
        XCTAssertNotNil(find(root, key: "transform"))
    }

    func testUseCSSStaticTransformReplacesTheAttribute() throws {
        let root = try layer("""
        <defs><rect id="r" width="10" height="10" fill="#f00"/></defs>
        <use href="#r" transform="translate(5, 0)" style="transform:translate(10px, 0)"/>
        """)
        let transformed = layers(root).filter { !CATransform3DIsIdentity($0.transform) }
        XCTAssertTrue(transformed.contains { abs($0.transform.m41 - 10) < 0.01 })
        XCTAssertFalse(transformed.contains { abs($0.transform.m41 - 5) < 0.01 })
    }

    func testUseAnimationsHonourReducedMotion() throws {
        let root = try layer("""
        <style>
            @keyframes fade{0%{opacity:0}100%{opacity:1}}
            .u{animation:fade 1s linear infinite}
            @media (prefers-reduced-motion: reduce){ *{animation:none !important} }
        </style>
        <defs><rect id="r" width="10" height="10" fill="#f00"/></defs>
        <use class="u" href="#r"/>
        """, reduceMotion: true)
        XCTAssertNil(find(root, key: "opacity"))
    }
}
