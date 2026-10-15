import XCTest
@testable import SVGRenderKit

/// B119 — reproduction of the re-audit findings for the closed B82–B96 fixes.
///
/// Every test asserts the behaviour required by the SVG spec. A RED test = the audit finding is
/// confirmed (the bug exists); a GREEN test = the finding is not reproduced. Tests are named
/// `testB119_<item>_<what>`. The item numbers refer to the list in Task.md (B119).
/// Nothing here is marked as an expected failure on purpose.
@MainActor
final class SVGAuditB119Tests: XCTestCase {

    // MARK: Helpers

    private let size = 100

    private func svg(_ body: String, viewBox: String = "0 0 100 100") -> String {
        "<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" viewBox=\"\(viewBox)\">\(body)</svg>"
    }

    private func layer(_ body: String, viewBox: String = "0 0 100 100") throws -> CALayer {
        try SVGParser(svgString: svg(body, viewBox: viewBox), parsedRoot: nil).getLayer(overrideElements: nil)
    }

    private func root(_ body: String) throws -> SVGRoot {
        try SVGParser(svgString: svg(body), parsedRoot: nil).root
    }

    private func all<T: CALayer>(_ type: T.Type, in l: CALayer) -> [T] {
        var out: [T] = []
        if let t = l as? T { out.append(t) }
        for s in l.sublayers ?? [] { out += all(type, in: s) }
        return out
    }

    struct Pixel { var r: UInt8, g: UInt8, b: UInt8, a: UInt8 }

    /// Renders the layer into a 100×100 bitmap with a y-down (UIKit-like) orientation, so that
    /// SVG point (x, y) is bitmap point (x, y). Orientation is pinned by `testB119_0_helperOrientation`.
    private func pixels(_ layer: CALayer) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: size * size * 4)
        guard let ctx = CGContext(data: &data, width: size, height: size, bitsPerComponent: 8,
                                  bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return data }
        ctx.translateBy(x: 0, y: CGFloat(size))
        ctx.scaleBy(x: 1, y: -1)
        layer.frame = CGRect(x: 0, y: 0, width: size, height: size)
        layer.render(in: ctx)
        return data
    }

    private func pixel(_ data: [UInt8], _ x: Int, _ y: Int) -> Pixel {
        let i = (y * size + x) * 4
        return Pixel(r: data[i], g: data[i + 1], b: data[i + 2], a: data[i + 3])
    }

    private func pixel(_ layer: CALayer, _ x: Int, _ y: Int) -> Pixel {
        pixel(pixels(layer), x, y)
    }

    private func waitUntil(_ timeout: TimeInterval = 5, _ condition: @escaping () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return condition()
    }

    // MARK: 0 — control: the helper's orientation

    func testB119_0_helperOrientation() throws {
        let l = try layer("<rect x=\"0\" y=\"0\" width=\"20\" height=\"20\" fill=\"#000\"/>")
        let data = pixels(l)
        XCTAssertEqual(pixel(data, 10, 10).a, 255, "top-left square must be at top-left of the bitmap")
        XCTAssertEqual(pixel(data, 10, 90).a, 0)
        XCTAssertEqual(pixel(data, 90, 10).a, 0)
    }

    // MARK: 1 — <use opacity> is applied twice

    func testB119_1_useOpacityOnGroupAppliedOnce() throws {
        let l = try layer("""
        <defs><g id="g"><rect width="100" height="100" fill="#000"/></g></defs>
        <use xlink:href="#g" opacity="0.5"/>
        """)
        // Opacity .5 over an opaque black rect → alpha ≈ 128 (not 64).
        XCTAssertEqual(Double(pixel(l, 50, 50).a), 128, accuracy: 4)
    }

    func testB119_1_useOpacityOnShapeAppliedOnce() throws {
        let l = try layer("""
        <defs><rect id="r" width="100" height="100" fill="#000"/></defs>
        <use xlink:href="#r" opacity="0.5"/>
        """)
        XCTAssertEqual(Double(pixel(l, 50, 50).a), 128, accuracy: 4)
    }

    func testB119_1_useOpacityCombinesWithReferencedOpacity() throws {
        let l = try layer("""
        <defs><g id="g" opacity="0.5"><rect width="100" height="100" fill="#000"/></g></defs>
        <use xlink:href="#g" opacity="0.5"/>
        """)
        // .5 · .5 = .25 → alpha ≈ 64.
        XCTAssertEqual(Double(pixel(l, 50, 50).a), 64, accuracy: 4)
    }

    // MARK: 2 — <use> overwrites the transform of the referenced element

    func testB119_2_useXYKeepsReferencedShapeTransform() throws {
        let l = try layer("""
        <defs><rect id="r" width="20" height="20" fill="#000" transform="translate(50 0)"/></defs>
        <use xlink:href="#r" x="10"/>
        """)
        // translate(10) · translate(50) → square at x 60…80.
        let data = pixels(l)
        XCTAssertEqual(pixel(data, 70, 10).a, 255, "referenced transform lost")
        XCTAssertEqual(pixel(data, 15, 10).a, 0)
    }

    func testB119_2_useTransformKeepsReferencedShapeTransform() throws {
        let l = try layer("""
        <defs><rect id="r" width="20" height="20" fill="#000" transform="translate(50 0)"/></defs>
        <use xlink:href="#r" transform="translate(10 0)"/>
        """)
        let data = pixels(l)
        XCTAssertEqual(pixel(data, 70, 10).a, 255, "referenced transform lost")
        XCTAssertEqual(pixel(data, 15, 10).a, 0)
    }

    func testB119_2_useXYKeepsReferencedGroupTransform() throws {
        let l = try layer("""
        <defs><g id="g" transform="translate(50 0)"><rect width="20" height="20" fill="#000"/></g></defs>
        <use xlink:href="#g" x="10"/>
        """)
        let data = pixels(l)
        XCTAssertEqual(pixel(data, 70, 10).a, 255, "referenced group transform lost")
        XCTAssertEqual(pixel(data, 15, 10).a, 0)
    }

    // MARK: 3 — <use> erases clip-path / mask of the referenced <g>

    func testB119_3_useKeepsReferencedGroupClipPath() throws {
        let l = try layer("""
        <defs>
          <clipPath id="c"><rect width="50" height="100"/></clipPath>
          <g id="g" clip-path="url(#c)"><rect width="100" height="100" fill="#000"/></g>
        </defs>
        <use xlink:href="#g"/>
        """)
        let data = pixels(l)
        XCTAssertEqual(pixel(data, 25, 50).a, 255)
        XCTAssertEqual(pixel(data, 75, 50).a, 0, "clip-path of the referenced <g> was erased")
    }

    func testB119_3_useKeepsReferencedGroupClipPathWithPlainHref() throws {
        let l = try layer("""
        <defs>
          <clipPath id="c"><rect width="50" height="100"/></clipPath>
          <g id="g" clip-path="url(#c)"><rect width="100" height="100" fill="#000"/></g>
        </defs>
        <use href="#g"/>
        """)
        XCTAssertEqual(pixel(l, 75, 50).a, 0)
    }

    func testB119_3_useKeepsReferencedGroupMask() throws {
        let l = try layer("""
        <defs>
          <mask id="m"><rect width="50" height="100" fill="#fff"/></mask>
          <g id="g" mask="url(#m)"><rect width="100" height="100" fill="#000"/></g>
        </defs>
        <use xlink:href="#g"/>
        """)
        let data = pixels(l)
        XCTAssertEqual(pixel(data, 25, 50).a, 255)
        XCTAssertEqual(pixel(data, 75, 50).a, 0, "mask of the referenced <g> was erased")
    }

    func testB119_3_useOwnClipIntersectsReferencedClip() throws {
        let l = try layer("""
        <defs>
          <clipPath id="left"><rect width="50" height="100"/></clipPath>
          <clipPath id="right"><rect x="25" width="75" height="100"/></clipPath>
          <g id="g" clip-path="url(#left)"><rect width="100" height="100" fill="#000"/></g>
        </defs>
        <use xlink:href="#g" clip-path="url(#right)"/>
        """)
        // left ∩ right = x 25…50.
        let data = pixels(l)
        XCTAssertEqual(pixel(data, 10, 50).a, 0, "outside the use's clip")
        XCTAssertEqual(pixel(data, 40, 50).a, 255)
        XCTAssertEqual(pixel(data, 75, 50).a, 0, "outside the referenced clip")
    }

    func testB119_3_useOwnMaskIntersectsReferencedMask() throws {
        let l = try layer("""
        <defs>
          <mask id="left"><rect width="50" height="100" fill="#fff"/></mask>
          <mask id="right"><rect x="25" width="75" height="100" fill="#fff"/></mask>
          <g id="g" mask="url(#left)"><rect width="100" height="100" fill="#000"/></g>
        </defs>
        <use xlink:href="#g" mask="url(#right)"/>
        """)
        let data = pixels(l)
        XCTAssertEqual(pixel(data, 10, 50).a, 0)
        XCTAssertEqual(pixel(data, 40, 50).a, 255)
        XCTAssertEqual(pixel(data, 75, 50).a, 0)
    }

    // MARK: 4 — ancestor style does not reach <use> content

    func testB119_4_groupFillInheritedThroughUse() throws {
        let l = try layer("""
        <defs><rect id="p" width="100" height="100"/></defs>
        <g fill="#ff0000"><use xlink:href="#p"/></g>
        """)
        let p = pixel(l, 50, 50)
        XCTAssertEqual(p.a, 255)
        XCTAssertGreaterThan(p.r, 200, "fill of the ancestor <g> did not reach the referenced element")
        XCTAssertLessThan(p.b, 50)
    }

    func testB119_4_useFillInheritedByReferencedGroup() throws {
        let l = try layer("""
        <defs><g id="g"><rect width="100" height="100"/></g></defs>
        <use xlink:href="#g" fill="#ff0000"/>
        """)
        let p = pixel(l, 50, 50)
        XCTAssertGreaterThan(p.r, 200)
        XCTAssertLessThan(p.b, 50)
    }

    func testB119_4_svgRootFillInheritedThroughUse() throws {
        let l = try layer("""
        <defs><rect id="p" width="100" height="100"/></defs>
        <g fill="#ff0000"><g><use xlink:href="#p"/></g></g>
        """)
        let p = pixel(l, 50, 50)
        XCTAssertGreaterThan(p.r, 200, "fill of grand-ancestor did not reach the referenced element")
        XCTAssertLessThan(p.b, 50)
    }

    // MARK: 5 — graceful degradation (B85)

    func testB119_5_fillTransparentIsTransparent() throws {
        let l = try layer("<rect width=\"100\" height=\"100\" fill=\"transparent\"/>")
        XCTAssertEqual(pixel(l, 50, 50).a, 0)
    }

    func testB119_5_fillMissingUrlReferenceIsNone() throws {
        let l = try layer("<rect width=\"100\" height=\"100\" fill=\"url(#nope)\"/>")
        XCTAssertEqual(pixel(l, 50, 50).a, 0, "SVG2: a reference to a missing paint server without fallback is `none`")
    }

    func testB119_5_missingUrlWithFallbackUsesFallback() throws {
        let l = try layer("<rect width=\"100\" height=\"100\" fill=\"url(#nope) #00ff00\"/>")
        let p = pixel(l, 50, 50)
        XCTAssertEqual(p.a, 255)
        XCTAssertGreaterThan(p.g, 200)
        XCTAssertLessThan(p.r, 50)
    }

    func testB119_5_percentOpacity() throws {
        let l = try layer("<rect width=\"100\" height=\"100\" fill=\"#000\" opacity=\"50%\"/>")
        XCTAssertEqual(Double(pixel(l, 50, 50).a), 128, accuracy: 4)
    }

    func testB119_5_opacityAboveOneIsClamped() throws {
        let l = try layer("<rect width=\"100\" height=\"100\" fill=\"#000\" opacity=\"2\"/>")
        XCTAssertEqual(pixel(l, 50, 50).a, 255)
    }

    func testB119_5_negativeOpacityIsClampedToZero() throws {
        let l = try layer("<rect width=\"100\" height=\"100\" fill=\"#000\" opacity=\"-1\"/>")
        XCTAssertEqual(pixel(l, 50, 50).a, 0)
    }

    func testB119_5_fillOpacityPercentAndClamp() throws {
        let l = try layer("<rect width=\"100\" height=\"100\" fill=\"#000\" fill-opacity=\"50%\"/>")
        XCTAssertEqual(Double(pixel(l, 50, 50).a), 128, accuracy: 4)
    }

    /// Renders `body` plus a sentinel rect; the whole document must survive a broken element.
    private func assertSurvives(_ body: String, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        var l: CALayer?
        XCTAssertNoThrow(l = try layer(body + "<rect x=\"80\" width=\"20\" height=\"100\" fill=\"#000\"/>"),
                         message, file: file, line: line)
        if let l = l {
            XCTAssertEqual(pixel(l, 90, 50).a, 255, "sentinel rect must still render: \(message)", file: file, line: line)
        }
    }

    func testB119_5_gradientWithoutStopsDoesNotFailDocument() {
        assertSurvives("""
        <defs><linearGradient id="g"/></defs>
        <rect width="50" height="100" fill="url(#g)"/>
        """, "linearGradient without stops")
    }

    func testB119_5_radialGradientWithoutStopsDoesNotFailDocument() {
        assertSurvives("""
        <defs><radialGradient id="g"/></defs>
        <rect width="50" height="100" fill="url(#g)"/>
        """, "radialGradient without stops")
    }

    func testB119_5_useWithMissingHrefTargetDoesNotFailDocument() {
        assertSurvives("<use xlink:href=\"#nope\"/>", "<use> with a missing target")
    }

    func testB119_5_useWithExternalHrefDoesNotFailDocument() {
        assertSurvives("<use xlink:href=\"http://example.com/a.svg#x\"/>", "<use> with an external href")
    }

    func testB119_5_useCycleDoesNotFailDocument() {
        assertSurvives("""
        <defs><g id="a"><use xlink:href="#a"/></g></defs>
        <use xlink:href="#a"/>
        """, "<use> reference cycle")
    }

    func testB119_5_oddPointsRendersUpToLastPair() throws {
        // SVG 2: an odd trailing coordinate is dropped, the rest renders.
        let l = try layer("<polygon points=\"10,10 90,10 90,90 10,90 50\" fill=\"#000\"/>")
        XCTAssertEqual(pixel(l, 50, 50).a, 255, "odd `points` skipped the whole element")
    }

    // MARK: 5b — B87: mask/clipPath children

    func testB119_5b_maskChildrenRenderedInDocumentOrder() throws {
        let l = try layer("""
        <defs><mask id="m">
          <rect width="100" height="100" fill="#fff"/>
          <g><rect width="50" height="100" fill="#000"/></g>
        </mask></defs>
        <rect width="100" height="100" fill="#000" mask="url(#m)"/>
        """)
        // The black group comes after the white rect and covers the left half.
        let data = pixels(l)
        XCTAssertEqual(pixel(data, 25, 50).a, 0, "later black <g> must cover the earlier white rect")
        XCTAssertEqual(pixel(data, 75, 50).a, 255)
    }

    func testB119_5b_maskShapeAfterGroupWins() throws {
        let l = try layer("""
        <defs><mask id="m">
          <g><rect width="100" height="100" fill="#fff"/></g>
          <rect width="50" height="100" fill="#000"/>
        </mask></defs>
        <rect width="100" height="100" fill="#000" mask="url(#m)"/>
        """)
        let data = pixels(l)
        XCTAssertEqual(pixel(data, 25, 50).a, 0)
        XCTAssertEqual(pixel(data, 75, 50).a, 255)
    }

    func testB119_5b_maskUseThenShapeOrder() throws {
        let l = try layer("""
        <defs>
          <rect id="w" width="100" height="100" fill="#fff"/>
          <mask id="m">
            <rect width="50" height="100" fill="#000"/>
            <use xlink:href="#w"/>
          </mask>
        </defs>
        <rect width="100" height="100" fill="#000" mask="url(#m)"/>
        """)
        // Document order: black rect first, white <use> on top → fully visible.
        // By-type order (uses → shapes) would paint the black rect last.
        XCTAssertEqual(pixel(l, 25, 50).a, 255)
    }

    func testB119_5b_groupInsideClipPathIsIgnored() throws {
        // SVG 1.1 §14.3.5: only shapes, text and <use> are allowed in <clipPath>; <g> contributes nothing.
        let l = try layer("""
        <defs><clipPath id="c"><g><rect width="100" height="100"/></g></clipPath></defs>
        <rect width="100" height="100" fill="#000" clip-path="url(#c)"/>
        """)
        XCTAssertEqual(pixel(l, 50, 50).a, 0)
    }

    func testB119_5b_clipPathDisplayNoneChildDoesNotContribute() throws {
        let l = try layer("""
        <defs><clipPath id="c">
          <rect width="100" height="100" display="none"/>
          <rect width="50" height="100"/>
        </clipPath></defs>
        <rect width="100" height="100" fill="#000" clip-path="url(#c)"/>
        """)
        let data = pixels(l)
        XCTAssertEqual(pixel(data, 25, 50).a, 255)
        XCTAssertEqual(pixel(data, 75, 50).a, 0, "display:none child was revived inside clipPath")
    }

    func testB119_5b_maskDisplayNoneChildDoesNotContribute() throws {
        let l = try layer("""
        <defs><mask id="m">
          <rect width="100" height="100" fill="#fff" display="none"/>
          <rect width="50" height="100" fill="#fff"/>
        </mask></defs>
        <rect width="100" height="100" fill="#000" mask="url(#m)"/>
        """)
        let data = pixels(l)
        XCTAssertEqual(pixel(data, 25, 50).a, 255)
        XCTAssertEqual(pixel(data, 75, 50).a, 0, "display:none child was revived inside mask")
    }

    func testB119_5b_clipPathUseOpacityIgnored() throws {
        // Opacity does not affect a clip shape: a clip is binary.
        let l = try layer("""
        <defs>
          <rect id="r" width="50" height="100"/>
          <clipPath id="c"><use xlink:href="#r" opacity="0"/></clipPath>
        </defs>
        <rect width="100" height="100" fill="#000" clip-path="url(#c)"/>
        """)
        XCTAssertEqual(pixel(l, 25, 50).a, 255)
    }

    func testB119_5b_clipRuleOfShapeInClipPathHonoured() throws {
        let l = try layer("""
        <defs><clipPath id="c">
          <path clip-rule="evenodd" d="M0 0H100V100H0Z M25 25H75V75H25Z"/>
        </clipPath></defs>
        <rect width="100" height="100" fill="#000" clip-path="url(#c)"/>
        """)
        XCTAssertEqual(pixel(l, 50, 50).a, 0, "evenodd hole must stay a hole")
        XCTAssertEqual(pixel(l, 10, 50).a, 255)
    }

    // MARK: 6 — B92: mask resolution

    private func maskedLayer(in layer: CALayer) -> CALayer? {
        if layer.mask != nil { return layer }
        for s in layer.sublayers ?? [] { if let f = maskedLayer(in: s) { return f } }
        return nil
    }

    /// Pixels of the mask bitmap per SVG unit of its frame.
    private func maskDensity(_ mask: CALayer) -> CGFloat? {
        guard let contents = mask.contents, CFGetTypeID(contents as CFTypeRef) == CGImage.typeID else { return nil }
        let image = contents as! CGImage
        return CGFloat(image.width) / max(mask.frame.width, 1)
    }

    private let maskDoc = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
      <defs><mask id="m"><rect width="50" height="50" fill="#fff"/></mask></defs>
      <rect width="100" height="100" fill="#f00" mask="url(#m)"/>
    </svg>
    """

    func testB119_6_maskResolutionIncludesScreenScale() throws {
        let view = SVGView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        view.svgString = maskDoc
        XCTAssertTrue(waitUntil { view.shapeLayer != nil })
        let shape = try XCTUnwrap(view.shapeLayer)
        let masked = try XCTUnwrap(maskedLayer(in: shape))
        let density = try XCTUnwrap(maskDensity(try XCTUnwrap(masked.mask)))
        // The view maps 1 unit to 1 pt; the mask must be rasterized at ≥ the screen scale.
        let screenScale = view.window?.screen.scale ?? UIScreen.main.scale
        XCTAssertGreaterThanOrEqual(density, screenScale - 0.01,
                                    "mask is \(density) px/unit on a \(screenScale)x screen")
    }

    func testB119_6_maskRerenderedWhenViewGetsSizeAfterZeroSizeLoad() throws {
        let view = SVGView(frame: .zero)
        view.svgString = maskDoc
        XCTAssertTrue(waitUntil { view.shapeLayer != nil })

        view.frame = CGRect(x: 0, y: 0, width: 400, height: 400)
        view.layoutIfNeeded()
        // 4 pt per unit: after the view got its size the mask must have ≥ 4 px/unit.
        let sharp = waitUntil(3) {
            guard let shape = view.shapeLayer, let masked = self.maskedLayer(in: shape),
                  let mask = masked.mask, let d = self.maskDensity(mask) else { return false }
            return d >= 4
        }
        XCTAssertTrue(sharp, "mask stayed at its load-time (zero-size) resolution")
    }

    func testB119_6_maskNotDroppedWhenScaledBeyondPixelLimit() throws {
        let parser = try SVGParser(svgString: maskDoc, parsedRoot: nil)
        parser.root.getSvgOptions().renderScale = 100   // 100 units · 100 = 10000 px > 4096 limit
        let l = try parser.getLayer(overrideElements: nil)
        let masked = try XCTUnwrap(maskedLayer(in: l), "mask silently removed instead of downscaling the raster")
        XCTAssertNotNil(masked.mask)
    }

    func testB119_6_nestedGroupScaleCountedInMaskResolution() throws {
        let doc = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
          <defs><mask id="m"><rect width="5" height="5" fill="#fff"/></mask></defs>
          <g transform="scale(10)"><rect width="10" height="10" fill="#f00" mask="url(#m)"/></g>
        </svg>
        """
        let parser = try SVGParser(svgString: doc, parsedRoot: nil)
        parser.root.getSvgOptions().renderScale = 1
        let l = try parser.getLayer(overrideElements: nil)
        let masked = try XCTUnwrap(maskedLayer(in: l))
        let density = try XCTUnwrap(maskDensity(try XCTUnwrap(masked.mask)))
        // The group scales the mask 10×; at renderScale 1 it should be rasterized at ≈10 px/unit.
        XCTAssertGreaterThanOrEqual(density, 9.9, "ancestor scale ignored: \(density) px/unit")
    }

    // MARK: 7 — B90: CSS

    func testB119_7_classOrderFollowsRuleOrderNotClassAttribute() throws {
        let l = try layer("""
        <style>.a{fill:#ff0000}.b{fill:#0000ff}</style>
        <rect width="100" height="100" class="b a"/>
        """)
        // Equal specificity → the later rule (.b) wins regardless of the class attribute order.
        let p = pixel(l, 50, 50)
        XCTAssertGreaterThan(p.b, 200, "got r=\(p.r) b=\(p.b)")
        XCTAssertLessThan(p.r, 50)
    }

    func testB119_7_atImportWithoutBlockDoesNotEatNextRule() throws {
        let l = try layer("""
        <style>@import url("x.css"); .a{fill:#ff0000}</style>
        <rect width="100" height="100" class="a"/>
        """)
        let p = pixel(l, 50, 50)
        XCTAssertGreaterThan(p.r, 200, "rule after @import was swallowed")
    }

    func testB119_7_atCharsetWithoutBlockDoesNotEatNextRule() throws {
        let l = try layer("""
        <style>@charset "UTF-8"; .a{fill:#ff0000}</style>
        <rect width="100" height="100" class="a"/>
        """)
        XCTAssertGreaterThan(pixel(l, 50, 50).r, 200, "rule after @charset was swallowed")
    }

    func testB119_7_laterRuleOverridesEarlierForSameClassAndId() throws {
        let l = try layer("""
        <style>.a{fill:#ff0000}.a{fill:#0000ff}</style>
        <rect width="100" height="100" class="a"/>
        """)
        XCTAssertGreaterThan(pixel(l, 50, 50).b, 200)
    }

    func testB119_7_tagVsClassOrderPreservedAcrossSelectorKinds() throws {
        // Equal specificity is not required to reproduce: `rect` (type) vs `.a` (class): class wins
        // by specificity; the repo does not implement specificity ("CSS cascade" is out of scope),
        // so this only pins that the document order wins between same-kind selectors.
        let l = try layer("""
        <style>.b{fill:#0000ff}.a{fill:#ff0000}</style>
        <rect width="100" height="100" class="a b"/>
        """)
        // .a is the later rule → red.
        XCTAssertGreaterThan(pixel(l, 50, 50).r, 200)
    }

    // MARK: 8 — B94: bounds

    func testB119_8_contentBoundsOfRotatedCircleIsTight() throws {
        let r = try root("<g><circle cx=\"0\" cy=\"0\" r=\"10\" transform=\"rotate(45)\"/></g>")
        let group = try XCTUnwrap(r.svgElement.layerElements.array.compactMap { $0 as? SVGGTag }.first)
        // A circle is rotation invariant: bbox stays 20×20.
        XCTAssertEqual(group.contentBounds.width, 20, accuracy: 0.05, "AABB of AABB: \(group.contentBounds)")
        XCTAssertEqual(group.contentBounds.height, 20, accuracy: 0.05)
    }

    func testB119_8_contentBoundsOfRotateThenCounterRotateIsTight() throws {
        let r = try root("""
        <g><g transform="rotate(-45)"><g transform="rotate(45)"><rect width="10" height="10"/></g></g></g>
        """)
        let group = try XCTUnwrap(r.svgElement.layerElements.array.compactMap { $0 as? SVGGTag }.first)
        XCTAssertEqual(group.contentBounds.width, 10, accuracy: 0.05, "nested rotations inflate the box: \(group.contentBounds)")
        XCTAssertEqual(group.contentBounds.height, 10, accuracy: 0.05)
    }

    func testB119_8_skewedChildBoundsAreTight() throws {
        let r = try root("<g><path d=\"M0 0 L10 10\" transform=\"rotate(-45)\"/></g>")
        let group = try XCTUnwrap(r.svgElement.layerElements.array.compactMap { $0 as? SVGGTag }.first)
        // A diagonal 10·√2 line rotated onto the x axis: 14.14 × 0.
        XCTAssertEqual(group.contentBounds.height, 0, accuracy: 0.05, "got \(group.contentBounds)")
    }

    func testB119_8_useXOffsetNotAppliedTwiceToObjectBoundingBoxClip() throws {
        let l = try layer("""
        <defs>
          <rect id="r" width="20" height="20" fill="#000"/>
          <clipPath id="c" clipPathUnits="objectBoundingBox"><rect width="0.5" height="1"/></clipPath>
        </defs>
        <use xlink:href="#r" x="40" clip-path="url(#c)"/>
        """)
        // The clone spans x 40…60; the left half of its bbox is 40…50.
        let data = pixels(l)
        XCTAssertEqual(pixel(data, 45, 10).a, 255, "left half missing")
        XCTAssertEqual(pixel(data, 55, 10).a, 0, "right half must be clipped")
    }

    func testB119_8_useXOffsetNotAppliedTwiceToObjectBoundingBoxMask() throws {
        let l = try layer("""
        <defs>
          <rect id="r" width="20" height="20" fill="#000"/>
          <mask id="m" maskContentUnits="objectBoundingBox"><rect width="0.5" height="1" fill="#fff"/></mask>
        </defs>
        <use xlink:href="#r" x="40" mask="url(#m)"/>
        """)
        let data = pixels(l)
        XCTAssertEqual(pixel(data, 45, 10).a, 255)
        XCTAssertEqual(pixel(data, 55, 10).a, 0)
    }

    func testB119_8_symbolUseHasBoundsForObjectBoundingBoxClip() throws {
        let l = try layer("""
        <defs>
          <symbol id="s" viewBox="0 0 10 10"><rect width="10" height="10" fill="#000"/></symbol>
          <clipPath id="c" clipPathUnits="objectBoundingBox"><rect width="0.5" height="1"/></clipPath>
        </defs>
        <use xlink:href="#s" width="100" height="100" clip-path="url(#c)"/>
        """)
        let data = pixels(l)
        XCTAssertEqual(pixel(data, 25, 50).a, 255, "symbol <use> has no bbox: clip dropped everything")
        XCTAssertEqual(pixel(data, 75, 50).a, 0, "right half must be clipped")
    }

    // MARK: 9 — B88

    func testB119_9_duplicateIdFirstInDocumentWins() throws {
        let l = try layer("""
        <defs>
          <rect id="r" width="100" height="100" fill="#ff0000"/>
          <rect id="r" width="100" height="100" fill="#0000ff"/>
        </defs>
        <use xlink:href="#r"/>
        """)
        let p = pixel(l, 50, 50)
        XCTAssertGreaterThan(p.r, 200, "first element with the id must win (r=\(p.r) b=\(p.b))")
    }

    func testB119_9_useCanReferenceElementInsideMask() throws {
        let l = try layer("""
        <defs><mask id="m"><rect id="inner" width="100" height="100" fill="#0000ff"/></mask></defs>
        <use xlink:href="#inner"/>
        """)
        XCTAssertEqual(pixel(l, 50, 50).a, 255, "id inside <mask> is not in the id map")
    }

    func testB119_9_useCanReferenceElementInsideClipPath() throws {
        let l = try layer("""
        <defs><clipPath id="c"><rect id="inner" width="100" height="100"/></clipPath></defs>
        <use xlink:href="#inner"/>
        """)
        XCTAssertEqual(pixel(l, 50, 50).a, 255, "id inside <clipPath> is not in the id map")
    }

    func testB119_9_concurrentGetLayerOnSharedParserWithHrefChain() throws {
        let parser = try SVGParser(svgString: svg("""
        <defs>
          <linearGradient id="g1"><stop offset="0" stop-color="#f00"/><stop offset="1" stop-color="#00f"/></linearGradient>
          <linearGradient id="g2" xlink:href="#g1"/>
          <linearGradient id="g3" xlink:href="#g2"/>
          <linearGradient id="g4" xlink:href="#g3"/>
        </defs>
        <rect width="100" height="100" fill="url(#g4)"/>
        """), parsedRoot: nil)
        let failures = NSLock()
        nonisolated(unsafe) var failed = 0
        nonisolated(unsafe) var emptyStops = 0
        // `concurrentPerform` takes a `@Sendable` closure; the parser is only read here and the
        // lock guards the counters, so the check is as safe as the concurrent callers it models.
        nonisolated(unsafe) let sharedParser = parser
        DispatchQueue.concurrentPerform(iterations: 400) { _ in
            do {
                let l = try sharedParser.getLayer(overrideElements: nil)
                let stops = (l.sublayers ?? []).flatMap { s -> [CAGradientLayer] in
                    var out: [CAGradientLayer] = []
                    func walk(_ x: CALayer) {
                        if let g = x as? CAGradientLayer { out.append(g) }
                        x.sublayers?.forEach(walk)
                    }
                    walk(s)
                    return out
                }
                if stops.contains(where: { ($0.colors?.count ?? 0) < 2 }) {
                    failures.lock(); emptyStops += 1; failures.unlock()
                }
            } catch {
                failures.lock(); failed += 1; failures.unlock()
            }
        }
        XCTAssertEqual(failed, 0)
        XCTAssertEqual(emptyStops, 0, "href-inherited stops observed half-resolved")
    }

    // MARK: 10 — B96: reload after error

    func testB119_10_reloadAfterFailedLoadRetriesSource() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("b119-\(UUID().uuidString).svg")
        defer { try? FileManager.default.removeItem(at: url) }

        let view = SVGView(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
        var reported: Error?
        view.onLoadError = { reported = $0 }
        view.set(svgURL: url)   // file does not exist yet
        XCTAssertTrue(waitUntil { reported != nil })

        try svg("<rect width=\"100\" height=\"100\"/>").write(to: url, atomically: true, encoding: .utf8)
        view.updateSvg()   // what the reload notification does
        XCTAssertTrue(waitUntil { view.shapeLayer != nil },
                      "reload after a failed load did nothing: the source was forgotten")
    }

    // MARK: 11 — B93: gradients

    func testB119_11_focalRadiusFrIsSupported() throws {
        let l = try layer("""
        <defs><radialGradient id="g" gradientUnits="userSpaceOnUse" cx="50" cy="50" r="50" fr="25">
          <stop offset="0" stop-color="#f00"/><stop offset="1" stop-color="#00f"/></radialGradient></defs>
        <rect width="100" height="100" fill="url(#g)"/>
        """)
        // Inside the focal radius the colour is the first stop (pure red).
        let p = pixel(l, 60, 50)
        XCTAssertGreaterThan(p.r, 245, "fr ignored: r=\(p.r) b=\(p.b)")
        XCTAssertLessThan(p.b, 10)
    }

    func testB119_11_focalPointOutsideCircleIsClamped() throws {
        let l = try layer("""
        <defs><radialGradient id="g" gradientUnits="userSpaceOnUse" cx="50" cy="50" r="25" fx="95" fy="50">
          <stop offset="0" stop-color="#f00"/><stop offset="1" stop-color="#00f"/></radialGradient></defs>
        <rect width="100" height="100" fill="url(#g)"/>
        """)
        // Pad spreading covers the whole rect once the focal point is clamped to the circle.
        let data = pixels(l)
        for (x, y) in [(5, 50), (50, 5), (50, 95), (95, 50), (20, 20)] {
            XCTAssertEqual(pixel(data, x, y).a, 255, "hole at (\(x),\(y)) in a pad-spread radial gradient")
        }
    }

    func testB119_11_linearGradientTransformSkew() throws {
        let l = try layer("""
        <defs><linearGradient id="g" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="100" y2="0" gradientTransform="skewX(45)">
          <stop offset="0" stop-color="#f00"/><stop offset="1" stop-color="#00f"/></linearGradient></defs>
        <rect width="100" height="100" fill="url(#g)"/>
        """)
        let data = pixels(l)
        // `gradientTransform` maps the gradient's level lines (SVG 1.1 §13.2.1), so the colour
        // depends on x − y: points on the same line x − y = const share a colour, x − y < 0 is
        // the pure first stop, and x − y = 40 holds the same colour as x = 40 of the same
        // gradient without the skew. The absolute mid-gradient value is deliberately not pinned:
        // it depends on the renderer's interpolation space (WebKit mixes stops in sRGB,
        // CoreAnimation — and CoreSVG — in a wider space; see B121 in Task.md), while the
        // geometry does not.
        let low = pixel(data, 50, 90)        // x − y = −40 → clamped to the first stop
        let high = pixel(data, 50, 10)       // x − y = 40
        let sameLine = pixel(data, 70, 30)   // x − y = 40
        let further = pixel(data, 90, 10)    // x − y = 80
        XCTAssertGreaterThan(low.r, 245, "x − y < 0 must be the pure first stop: (\(low.r),\(low.b))")
        XCTAssertEqual(Double(high.r), Double(sameLine.r), accuracy: 2,
                       "equal x − y must paint the same colour: (50,10)=(\(high.r),\(high.b)) vs (70,30)=(\(sameLine.r),\(sameLine.b))")
        XCTAssertEqual(Double(high.b), Double(sameLine.b), accuracy: 2,
                       "equal x − y must paint the same colour: (50,10)=(\(high.r),\(high.b)) vs (70,30)=(\(sameLine.r),\(sameLine.b))")
        XCTAssertLessThan(further.r, high.r - 8,
                          "the gradient must keep advancing along x − y: (90,10)=\(further.r) vs (50,10)=\(high.r)")

        // The same gradient without the skew: its x = 40 point is the skewed field's
        // x − y = 40 point, which pins the axis itself, not only its direction.
        let flat = try layer("""
        <defs><linearGradient id="g" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="100" y2="0">
          <stop offset="0" stop-color="#f00"/><stop offset="1" stop-color="#00f"/></linearGradient></defs>
        <rect width="100" height="100" fill="url(#g)"/>
        """)
        let flatPoint = pixel(flat, 40, 50)
        XCTAssertEqual(Double(high.r), Double(flatPoint.r), accuracy: 2,
                       "skewed (50,10)=(\(high.r),\(high.b)) must hold the untransformed x = 40 colour (\(flatPoint.r),\(flatPoint.b))")
        XCTAssertEqual(Double(high.b), Double(flatPoint.b), accuracy: 2,
                       "skewed (50,10)=(\(high.r),\(high.b)) must hold the untransformed x = 40 colour (\(flatPoint.r),\(flatPoint.b))")
    }

    // MARK: 12 — B83 / B91 / B95

    func testB119_12_objectBoundingBoxClipPathTransformOrder() throws {
        let l = try layer("""
        <defs><clipPath id="c" clipPathUnits="objectBoundingBox" transform="translate(0.5 0)">
          <rect width="0.5" height="1"/></clipPath></defs>
        <rect width="100" height="100" fill="#000" clip-path="url(#c)"/>
        """)
        // Clip rect 0…0.5 shifted by 0.5 bbox units → right half.
        let data = pixels(l)
        XCTAssertEqual(pixel(data, 25, 50).a, 0)
        XCTAssertEqual(pixel(data, 75, 50).a, 255)
    }

    func testB119_12_objectBoundingBoxClipPathScaleTransform() throws {
        let l = try layer("""
        <defs><clipPath id="c" clipPathUnits="objectBoundingBox" transform="translate(0.5 0) scale(0.5 1)">
          <rect width="1" height="1"/></clipPath></defs>
        <rect width="100" height="100" fill="#000" clip-path="url(#c)"/>
        """)
        // translate(.5)·scale(.5): unit square → x 0.5…1.0.
        let data = pixels(l)
        XCTAssertEqual(pixel(data, 25, 50).a, 0)
        XCTAssertEqual(pixel(data, 75, 50).a, 255)
    }

    func testB119_12_classSelectorAppliesToUse() throws {
        let l = try layer("""
        <style>.a{fill:#ff0000}</style>
        <defs><rect id="r" width="100" height="100"/></defs>
        <use xlink:href="#r" class="a"/>
        """)
        XCTAssertGreaterThan(pixel(l, 50, 50).r, 200, "class selector ignored on <use>")
    }

    func testB119_12_idSelectorAppliesToUse() throws {
        let l = try layer("""
        <style>#u{fill:#ff0000}</style>
        <defs><rect id="r" width="100" height="100"/></defs>
        <use id="u" xlink:href="#r"/>
        """)
        XCTAssertGreaterThan(pixel(l, 50, 50).r, 200, "id selector ignored on <use>")
    }

    func testB119_12_classSelectorAppliesToImageOpacity() throws {
        // 1×1 red PNG
        let png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        let l = try layer("""
        <style>.a{opacity:0.5}</style>
        <image class="a" width="100" height="100" xlink:href="data:image/png;base64,\(png)"/>
        """)
        let a = pixel(l, 50, 50).a
        XCTAssertEqual(Double(a), 128, accuracy: 6, "class selector ignored on <image>: a=\(a)")
    }

    func testB119_12_useClipPathIsInUseUserSpaceNotShifted() throws {
        let l = try layer("""
        <defs>
          <rect id="r" width="40" height="100" fill="#000"/>
          <clipPath id="c"><rect width="70" height="100"/></clipPath>
        </defs>
        <use xlink:href="#r" x="50" clip-path="url(#c)"/>
        """)
        // Content spans 50…90; the clip (user space of <use>, not shifted by x) is 0…70 → visible 50…70.
        let data = pixels(l)
        XCTAssertEqual(pixel(data, 60, 50).a, 255)
        XCTAssertEqual(pixel(data, 80, 50).a, 0, "clip was shifted together with the x offset")
    }
}
