import XCTest
@testable import SVGRenderKit

/// M3.1 — `@media (prefers-color-scheme)` and `@media (prefers-reduced-motion)` are evaluated for
/// the appearance/motion the render was asked for, and the public API forwards that state.
final class SVGMediaQueryTests: XCTestCase {

    // MARK: Helpers

    private func layer(_ svg: String, appearance: SVGAppearance = .light,
                       reduceMotion: Bool = false) throws -> CALayer {
        let parser = try SVGParser(svgString: "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\">\(svg)</svg>",
                                   parsedRoot: nil)
        parser.root.svgElement.options.appearance = appearance
        parser.root.svgElement.options.reduceMotion = reduceMotion
        return try parser.getLayer(overrideElements: nil)
    }

    private func shapes(_ layer: CALayer) -> [CAShapeLayer] {
        var result: [CAShapeLayer] = []
        if let shape = layer as? CAShapeLayer, shape.path != nil { result.append(shape) }
        for sublayer in layer.sublayers ?? [] { result += shapes(sublayer) }
        return result
    }

    private func fill(_ layer: CALayer) throws -> UIColor {
        let shape = try XCTUnwrap(shapes(layer).first)
        return UIColor(cgColor: try XCTUnwrap(shape.fillColor))
    }

    private func assertColor(_ color: UIColor, _ r: CGFloat, _ g: CGFloat, _ b: CGFloat,
                             file: StaticString = #filePath, line: UInt = #line) {
        var rr: CGFloat = 0, gg: CGFloat = 0, bb: CGFloat = 0, aa: CGFloat = 0
        color.getRed(&rr, green: &gg, blue: &bb, alpha: &aa)
        XCTAssertEqual(rr, r, accuracy: 0.02, file: file, line: line)
        XCTAssertEqual(gg, g, accuracy: 0.02, file: file, line: line)
        XCTAssertEqual(bb, b, accuracy: 0.02, file: file, line: line)
    }

    private func find(_ layer: CALayer, key: String) -> CALayer? {
        if layer.animationKeys()?.contains(key) == true { return layer }
        for sublayer in layer.sublayers ?? [] {
            if let found = find(sublayer, key: key) { return found }
        }
        return nil
    }

    /// The main layer of the first shape; a shape's `opacity` is applied to its parent layer.
    private func shapeOpacity(_ layer: CALayer) throws -> Float {
        let shape = try XCTUnwrap(shapes(layer).first)
        return shape.superlayer?.opacity ?? shape.opacity
    }

    // MARK: prefers-color-scheme

    func testDarkMediaPaletteAppliesOnlyInDarkAppearance() throws {
        let svg = """
        <style>
            .icon{fill:#112233}
            @media (prefers-color-scheme: dark){.icon{fill:#ddeeff}}
        </style>
        <path class="icon" d="M0 0h10v10z"/>
        """
        let lightFill = try fill(try layer(svg, appearance: .light))
        let darkFill = try fill(try layer(svg, appearance: .dark))
        assertColor(lightFill, CGFloat(0x11) / 255, CGFloat(0x22) / 255, CGFloat(0x33) / 255)
        assertColor(darkFill, CGFloat(0xdd) / 255, CGFloat(0xee) / 255, CGFloat(0xff) / 255)
    }

    func testLightMediaAppliesOnlyInLightAppearance() throws {
        let svg = """
        <style>
            @media (prefers-color-scheme: light){.icon{fill:#ff0000}}
        </style>
        <path class="icon" d="M0 0h10v10z"/>
        """
        assertColor(try fill(try layer(svg, appearance: .light)), 1, 0, 0)
        assertColor(try fill(try layer(svg, appearance: .dark)), 0, 0, 0)
    }

    func testCommaSeparatedAlternativesAreAnOr() throws {
        let svg = """
        <style>
            @media (min-width: 500px), (prefers-color-scheme: dark){.icon{fill:#0000ff}}
        </style>
        <path class="icon" d="M0 0h10v10z"/>
        """
        assertColor(try fill(try layer(svg, appearance: .light)), 0, 0, 0)
        assertColor(try fill(try layer(svg, appearance: .dark)), 0, 0, 1)
    }

    func testUnsupportedMediaFeatureNeverMatches() throws {
        let svg = """
        <style>@media (min-width: 100px){.icon{fill:#00ff00}}</style>
        <path class="icon" d="M0 0h10v10z"/>
        """
        assertColor(try fill(try layer(svg, appearance: .dark)), 0, 0, 0)
    }

    func testCombinedAndCondition() throws {
        let svg = """
        <style>
            @media (prefers-color-scheme: dark) and (prefers-reduced-motion: reduce){.icon{fill:#00ff00}}
        </style>
        <path class="icon" d="M0 0h10v10z"/>
        """
        assertColor(try fill(try layer(svg, appearance: .dark, reduceMotion: false)), 0, 0, 0)
        assertColor(try fill(try layer(svg, appearance: .dark, reduceMotion: true)), 0, 1, 0)
    }

    func testNestedMediaBlocksAreConjoined() throws {
        let svg = """
        <style>
            @media (prefers-color-scheme: dark){
                @media (prefers-reduced-motion: reduce){.icon{fill:#ff00ff}}
            }
        </style>
        <path class="icon" d="M0 0h10v10z"/>
        """
        assertColor(try fill(try layer(svg, appearance: .light, reduceMotion: true)), 0, 0, 0)
        assertColor(try fill(try layer(svg, appearance: .dark, reduceMotion: false)), 0, 0, 0)
        assertColor(try fill(try layer(svg, appearance: .dark, reduceMotion: true)), 1, 0, 1)
    }

    // MARK: prefers-reduced-motion

    func testReducedMotionRuleDisablesAnimations() throws {
        let svg = """
        <style>
            @keyframes fade{0%{opacity:0}100%{opacity:1}}
            .a{animation:fade 1s linear infinite}
            @media (prefers-reduced-motion: reduce){ *{animation:none !important} }
        </style>
        <path class="a" d="M0 0h10v10z" fill="#f00"/>
        """
        XCTAssertNotNil(find(try layer(svg, reduceMotion: false), key: "opacity"))
        XCTAssertNil(find(try layer(svg, reduceMotion: true), key: "opacity"),
                     "the reduced-motion `animation:none !important` rule wins")
    }

    func testNoPreferenceMediaAppliesWhenMotionIsAllowed() throws {
        let svg = """
        <style>
            @media (prefers-reduced-motion: no-preference){.a{opacity:.3}}
        </style>
        <path class="a" d="M0 0h10v10z" fill="#f00"/>
        """
        XCTAssertEqual(try shapeOpacity(try layer(svg, reduceMotion: false)), 0.3, accuracy: 0.01)
        XCTAssertEqual(try shapeOpacity(try layer(svg, reduceMotion: true)), 1, accuracy: 0.01)
    }

    func testKeyframesInsideMediaAreConditional() throws {
        let svg = """
        <style>
            @media (prefers-reduced-motion: no-preference){
                @keyframes fade{0%{opacity:0}100%{opacity:1}}
            }
            .a{animation:fade 1s linear infinite}
        </style>
        <path class="a" d="M0 0h10v10z" fill="#f00"/>
        """
        XCTAssertNotNil(find(try layer(svg, reduceMotion: false), key: "opacity"))
        XCTAssertNil(find(try layer(svg, reduceMotion: true), key: "opacity"),
                     "without matching media the @keyframes block is not defined")
    }

    // MARK: Public API

    @MainActor
    func testViewExposesAppearanceAndMotionPreference() {
        let view = SVGView()
        XCTAssertNil(view.appearanceOverride, "the default follows the trait collection")
        XCTAssertEqual(view.motionPreference, .system)
        view.appearanceOverride = .dark
        view.motionPreference = .allow
        XCTAssertEqual(view.appearanceOverride, .dark)
        XCTAssertEqual(view.motionPreference, .allow)
        view.motionPreference = .system
        view.appearanceOverride = nil
    }

    func testRendererAppearanceChangesTheRaster() async throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16">
            <style>
                .x{fill:#ff0000}
                @media (prefers-color-scheme: dark){.x{fill:#0000ff}}
            </style>
            <rect class="x" width="16" height="16"/>
        </svg>
        """
        let size = CGSize(width: 16, height: 16)
        let light = try await SVGRenderer.render(.string(svg, name: "media-light"), size: size,
                                                 format: .png, appearance: .light)
        let dark = try await SVGRenderer.render(.string(svg, name: "media-dark"), size: size,
                                                format: .png, appearance: .dark)
        XCTAssertNotEqual(light, dark, "the dark media rule changes the rendered pixels")
    }

    func testRendererReducedMotionIsAccepted() async throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16">
            <style>
                @media (prefers-reduced-motion: reduce){.x{fill:#00ff00}}
            </style>
            <rect class="x" width="16" height="16"/>
        </svg>
        """
        let size = CGSize(width: 8, height: 8)
        let full = try await SVGRenderer.render(.string(svg, name: "motion-full"), size: size,
                                                format: .png, reduceMotion: false)
        let reduced = try await SVGRenderer.render(.string(svg, name: "motion-reduced"), size: size,
                                                   format: .png, reduceMotion: true)
        XCTAssertNotEqual(full, reduced)
    }
}
