import XCTest
@testable import SVGRenderKit

/// B88 — document-wide identifiers and lazy gradient references:
/// multiple `<defs>`/`<style>`, a forward or cross-type gradient `href`, and a
/// reference to an element that is not on the ancestor chain.
final class SVGDocumentReferencesTests: XCTestCase {

    private func render(_ body: String) throws -> CALayer {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" viewBox=\"0 0 100 100\">\(body)</svg>"
        return try SVGParser(svgString: svg, parsedRoot: nil).getLayer(overrideElements: nil)
    }

    private func all<T>(_ type: T.Type, in layer: CALayer) -> [T] {
        var result: [T] = []
        if let match = layer as? T { result.append(match) }
        for sub in layer.sublayers ?? [] {
            result.append(contentsOf: all(type, in: sub))
        }
        return result
    }

    func testForwardGradientHrefResolves() throws {
        // `#a` references `#b`, which is defined later; this used to fail the whole parse.
        let layer = try render("""
        <defs>
          <linearGradient id="a" xlink:href="#b"/>
          <linearGradient id="b"><stop offset="0" stop-color="#ff0000"/><stop offset="1" stop-color="#0000ff"/></linearGradient>
        </defs>
        <rect width="100" height="100" fill="url(#a)"/>
        """)
        let gradient = try XCTUnwrap(all(CAGradientLayer.self, in: layer).first)
        XCTAssertEqual(gradient.colors?.count, 2)
    }

    func testCrossTypeGradientHrefInheritsStops() throws {
        // A radial gradient referencing a linear one inherits its stops.
        let layer = try render("""
        <defs>
          <linearGradient id="l"><stop offset="0" stop-color="#ff0000"/><stop offset="1" stop-color="#0000ff"/></linearGradient>
          <radialGradient id="r" xlink:href="#l"/>
        </defs>
        <rect width="100" height="100" fill="url(#r)"/>
        """)
        let gradient = try XCTUnwrap(all(RadialGradientLayer.self, in: layer).first)
        XCTAssertEqual(gradient.colors.count, 2)
    }

    func testMultipleDefsAreBothUsable() throws {
        // The second <defs> must not overwrite the first.
        let layer = try render("""
        <defs><linearGradient id="a"><stop offset="0" stop-color="#ff0000"/><stop offset="1" stop-color="#0000ff"/></linearGradient></defs>
        <defs><linearGradient id="b"><stop offset="0" stop-color="#00ff00"/><stop offset="1" stop-color="#000000"/></linearGradient></defs>
        <rect width="50" height="100" fill="url(#a)"/>
        <rect x="50" width="50" height="100" fill="url(#b)"/>
        """)
        XCTAssertEqual(all(CAGradientLayer.self, in: layer).count, 2)
    }

    func testMultipleStyleBlocksBothApply() throws {
        let layer = try render("""
        <style>.a { fill: #ff0000; }</style>
        <style>.b { fill: #0000ff; }</style>
        <rect class="a" width="50" height="100"/>
        <rect class="b" x="50" width="50" height="100"/>
        """)
        let fills = all(CAShapeLayer.self, in: layer)
            .filter { $0.path != nil }
            .compactMap { $0.fillColor }
            .map { rgb($0) }
        XCTAssertEqual(fills.count, 2)
        XCTAssertTrue(fills.contains { $0.r > 0.8 && $0.b < 0.2 }, "the first <style> must still apply")
        XCTAssertTrue(fills.contains { $0.b > 0.8 && $0.r < 0.2 }, "the second <style> must apply too")
    }

    private func rgb(_ cgColor: CGColor) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        guard let comps = cgColor.components, comps.count >= 3 else { return (0, 0, 0) }
        return (comps[0], comps[1], comps[2])
    }

    func testReferenceToElementOutsideAncestorChainResolves() throws {
        // `#box` lives inside a <g> inside <defs> — not on the <use>'s ancestor chain,
        // and the <defs> is not a direct child either.
        let layer = try render("""
        <defs><g id="container"><rect id="box" width="10" height="10" fill="#ff0000"/></g></defs>
        <use href="#box"/>
        """)
        XCTAssertFalse(all(CAShapeLayer.self, in: layer).filter { $0.path != nil }.isEmpty)
    }
}
