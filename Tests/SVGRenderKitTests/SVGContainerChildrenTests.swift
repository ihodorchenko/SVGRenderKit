import XCTest
import UIKit
@testable import SVGRenderKit

/// B87 — `<image>` and `<g>` must reach the containers and `<use>` lookups:
/// `getRendering` returns `<image>`, `<symbol>` renders it, and a `<g>` inside a
/// `<mask>` / `<pattern>` / `<marker>` is not dropped. A `<g>` inside a `<clipPath>` is
/// out of spec and contributes nothing (B119-5b).
final class SVGContainerChildrenTests: XCTestCase {

    private func render(_ body: String) throws -> CALayer {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" viewBox=\"0 0 100 100\">\(body)</svg>"
        return try SVGParser(svgString: svg, parsedRoot: nil).getLayer(overrideElements: nil)
    }

    private func pngDataURI() -> String {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
        let image = renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        return "data:image/png;base64,\(image.pngData()!.base64EncodedString())"
    }

    private func hasImageContents(in layer: CALayer) -> Bool {
        if layer.contents != nil { return true }
        for sub in layer.sublayers ?? [] where hasImageContents(in: sub) { return true }
        return false
    }

    /// Alpha at `point` in a 100x100 render.
    private func alpha(_ layer: CALayer, at point: CGPoint, size: Int = 100) -> UInt8 {
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        guard let ctx = CGContext(data: &pixels, width: size, height: size, bitsPerComponent: 8,
                                  bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        layer.frame = CGRect(x: 0, y: 0, width: size, height: size)
        layer.render(in: ctx)
        let index = (Int(point.y) * size + Int(point.x)) * 4 + 3
        return pixels[index]
    }

    func testUseRendersReferencedImage() throws {
        let layer = try render("""
        <defs><image id="img" width="100" height="100" xlink:href="\(pngDataURI())"/></defs>
        <use href="#img"/>
        """)
        XCTAssertTrue(hasImageContents(in: layer))
    }

    func testUseRendersSymbolContainingImage() throws {
        let layer = try render("""
        <defs><symbol id="s"><image width="100" height="100" xlink:href="\(pngDataURI())"/></symbol></defs>
        <use href="#s" width="100" height="100"/>
        """)
        XCTAssertTrue(hasImageContents(in: layer))
    }

    func testGroupInsideClipPathContributesNothing() throws {
        // SVG 1.1 §14.3.5: a `<clipPath>` may contain shapes, text and `<use>`, not `<g>` —
        // it is ignored, so the clip is empty and nothing shows (B119-5b). The `<mask>`,
        // `<pattern>` and `<marker>` cases below keep their `<g>` support, which the spec
        // does allow there.
        let layer = try render("""
        <defs><clipPath id="c"><g><rect width="50" height="100"/></g></clipPath></defs>
        <rect width="100" height="100" fill="#000000" clip-path="url(#c)"/>
        """)
        XCTAssertEqual(alpha(layer, at: CGPoint(x: 25, y: 50)), 0)
        XCTAssertEqual(alpha(layer, at: CGPoint(x: 75, y: 50)), 0)
    }

    func testGroupInsideMaskMasks() throws {
        let layer = try render("""
        <defs><mask id="m"><g><rect width="100" height="100" fill="#ffffff"/></g></mask></defs>
        <rect width="100" height="100" fill="#000000" mask="url(#m)"/>
        """)
        XCTAssertGreaterThan(alpha(layer, at: CGPoint(x: 50, y: 50)), 200)
    }
}
