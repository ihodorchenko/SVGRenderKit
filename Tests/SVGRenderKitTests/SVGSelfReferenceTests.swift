import XCTest
@testable import SVGRenderKit

/// B125 — a paint server / mask / clip / marker / filter that references itself must not recurse
/// forever (stack overflow on untrusted SVG); the document still renders.
@MainActor
final class SVGSelfReferenceTests: XCTestCase {

    private func layer(_ body: String) throws -> CALayer {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" viewBox=\"0 0 100 100\">\(body)</svg>"
        return try SVGParser(svgString: svg, parsedRoot: nil).getLayer(overrideElements: nil)
    }

    private func alpha(_ layer: CALayer, _ x: Int, _ y: Int) -> UInt8 {
        let size = 100
        var data = [UInt8](repeating: 0, count: size * size * 4)
        guard let ctx = CGContext(data: &data, width: size, height: size, bitsPerComponent: 8,
                                  bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        ctx.translateBy(x: 0, y: CGFloat(size)); ctx.scaleBy(x: 1, y: -1)
        layer.frame = CGRect(x: 0, y: 0, width: size, height: size)
        layer.render(in: ctx)
        return data[(y * size + x) * 4 + 3]
    }

    private func assertRendersPlainRect(_ defs: String, rectAttrs: String = "", file: StaticString = #filePath, line: UInt = #line) throws {
        let l = try layer("\(defs)<rect x=\"50\" y=\"50\" width=\"40\" height=\"40\" fill=\"#000\" \(rectAttrs)/>"
                          + "<rect x=\"0\" y=\"0\" width=\"20\" height=\"20\" fill=\"#000\"/>")
        XCTAssertEqual(alpha(l, 10, 10), 255, "unrelated element still renders", file: file, line: line)
    }

    func testMaskReferencingItselfDoesNotRecurse() throws {
        try assertRendersPlainRect("<defs><mask id=\"m\"><rect width=\"100\" height=\"100\" fill=\"#fff\" mask=\"url(#m)\"/></mask></defs>",
                                   rectAttrs: "mask=\"url(#m)\"")
    }

    func testPatternReferencingItselfDoesNotRecurse() throws {
        try assertRendersPlainRect("<defs><pattern id=\"p\" width=\"10\" height=\"10\" patternUnits=\"userSpaceOnUse\"><rect width=\"5\" height=\"5\" fill=\"url(#p)\"/></pattern></defs>",
                                   rectAttrs: "")
        try assertRendersPlainRect("<defs><pattern id=\"p\" width=\"10\" height=\"10\" patternUnits=\"userSpaceOnUse\"><rect width=\"5\" height=\"5\" fill=\"url(#p)\"/></pattern></defs>",
                                   rectAttrs: "stroke=\"url(#p)\"")
    }

    func testPatternCycleThroughTwoPatternsDoesNotRecurse() throws {
        try assertRendersPlainRect("""
        <defs>
        <pattern id="a" width="10" height="10" patternUnits="userSpaceOnUse"><rect width="5" height="5" fill="url(#b)"/></pattern>
        <pattern id="b" width="10" height="10" patternUnits="userSpaceOnUse"><rect width="5" height="5" fill="url(#a)"/></pattern>
        </defs>
        """, rectAttrs: "")
        // and the element that actually uses it
        _ = try layer("""
        <defs>
        <pattern id="a" width="10" height="10" patternUnits="userSpaceOnUse"><rect width="5" height="5" fill="url(#b)"/></pattern>
        <pattern id="b" width="10" height="10" patternUnits="userSpaceOnUse"><rect width="5" height="5" fill="url(#a)"/></pattern>
        </defs><rect width="50" height="50" fill="url(#a)"/>
        """)
    }

    func testMaskCycleThroughTwoMasksDoesNotRecurse() throws {
        _ = try layer("""
        <defs>
        <mask id="a"><rect width="100" height="100" fill="#fff" mask="url(#b)"/></mask>
        <mask id="b"><rect width="100" height="100" fill="#fff" mask="url(#a)"/></mask>
        </defs><rect width="50" height="50" mask="url(#a)"/>
        """)
    }

    func testClipPathReferencingItselfDoesNotRecurse() throws {
        _ = try layer("<defs><clipPath id=\"c\"><rect width=\"50\" height=\"50\" clip-path=\"url(#c)\"/></clipPath></defs><rect width=\"80\" height=\"80\" clip-path=\"url(#c)\"/>")
        _ = try layer("<defs><clipPath id=\"c\" clip-path=\"url(#c)\"><rect width=\"50\" height=\"50\"/></clipPath></defs><rect width=\"80\" height=\"80\" clip-path=\"url(#c)\"/>")
    }

    func testMarkerReferencingItselfDoesNotRecurse() throws {
        _ = try layer("<defs><marker id=\"k\" markerWidth=\"5\" markerHeight=\"5\"><path d=\"M0 0L5 5\" stroke=\"#000\" marker-end=\"url(#k)\"/></marker></defs><path d=\"M10 10L90 90\" stroke=\"#000\" marker-end=\"url(#k)\"/>")
    }

    func testFilterReferencingItselfDoesNotRecurse() throws {
        _ = try layer("<defs><filter id=\"f\"><feGaussianBlur stdDeviation=\"2\"/></filter><g id=\"g\" filter=\"url(#f)\"><rect width=\"20\" height=\"20\" filter=\"url(#f)\"/></g></defs><rect width=\"80\" height=\"80\" filter=\"url(#f)\"/>")
    }

    func testUseFanOutDoesNotExplodeContentBounds() throws {
        var body = "<defs><g id=\"u0\"><rect width=\"1\" height=\"1\"/></g>"
        for i in 1...30 { body += "<g id=\"u\(i)\"><use href=\"#u\(i-1)\"/><use href=\"#u\(i-1)\"/></g>" }
        body += "</defs><use href=\"#u30\" mask=\"url(#nothing)\" opacity=\"0.5\"/>"
        let start = Date()
        _ = try layer(body)
        XCTAssertLessThan(Date().timeIntervalSince(start), 10, "fan-out DAG must not take 2^n time")
    }
}
