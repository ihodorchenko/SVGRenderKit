import XCTest
@testable import SVGRenderKit

final class SVGClipRuleCacheTests: XCTestCase {

    /// Pixel alpha at the center of a 100x100 render.
    private func centerAlpha(_ svg: String) throws -> UInt8 {
        let layer = try SVGParser(svgString: svg, parsedRoot: nil).getLayer(overrideElements: nil)
        let size = 100
        var pixel = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x: -CGFloat(size / 2), y: -CGFloat(size / 2))
        layer.frame = CGRect(x: 0, y: 0, width: size, height: size)
        layer.render(in: ctx)
        return pixel[3]
    }

    // Two nested squares drawn as one self-intersecting path: the inner one is a hole under evenodd.
    private func svg(clipRuleOnShape: String?, clipRuleOnClipPath: String? = nil) -> String {
        let shapeAttr = clipRuleOnShape.map { " clip-rule=\"\($0)\"" } ?? ""
        let cpAttr = clipRuleOnClipPath.map { " clip-rule=\"\($0)\"" } ?? ""
        return """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
          <defs><clipPath id="c"\(cpAttr)>
            <path\(shapeAttr) d="M0 0H100V100H0Z M25 25H75V75H25Z"/>
          </clipPath></defs>
          <rect width="100" height="100" fill="#000" clip-path="url(#c)"/>
        </svg>
        """
    }

    func testClipRuleNonZeroFillsTheHole() throws {
        XCTAssertGreaterThan(try centerAlpha(svg(clipRuleOnShape: nil)), 200)
    }

    func testClipRuleEvenOddOnClipPathChildCutsTheHole() throws {
        XCTAssertEqual(try centerAlpha(svg(clipRuleOnShape: "evenodd")), 0)
    }

    func testClipRuleEvenOddInheritedFromClipPath() throws {
        XCTAssertEqual(try centerAlpha(svg(clipRuleOnShape: nil, clipRuleOnClipPath: "evenodd")), 0)
    }

    func testFillRuleDoesNotAffectClipPath() throws {
        let s = svg(clipRuleOnShape: nil).replacingOccurrences(of: "<path d", with: "<path fill-rule=\"evenodd\" d")
        XCTAssertGreaterThan(try centerAlpha(s), 200)
    }

    func testCacheDoesNotReturnStaleTreeForSameName() throws {
        let a = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 10 10\"><rect width=\"10\" height=\"10\" fill=\"#ff0000\"/></svg>"
        let b = a.replacingOccurrences(of: "#ff0000", with: "#0000ff")
        let name = "cache-test-\(UUID().uuidString)"
        let pa = try SVGParser.getParser(svgString: a, name: name)
        let pb = try SVGParser.getParser(svgString: b, name: name)
        XCTAssertFalse(pa.root === pb.root)
        let pa2 = try SVGParser.getParser(svgString: a, name: name)
        XCTAssertTrue(pa.root === pa2.root, "identical name+content should still hit the cache")
    }
}
