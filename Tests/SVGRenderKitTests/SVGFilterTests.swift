import XCTest
@testable import SVGRenderKit

final class SVGFilterTests: XCTestCase {

    private func findLayerWithShadow(in layer: CALayer) -> CALayer? {
        if layer.shadowOpacity > 0 {
            return layer
        }
        for sublayer in layer.sublayers ?? [] {
            if let found = findLayerWithShadow(in: sublayer) {
                return found
            }
        }
        return nil
    }

    private func render(_ body: String) throws -> CALayer {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\">\(body)</svg>"
        return try SVGParser(svgString: svg, parsedRoot: nil).getLayer(overrideElements: nil)
    }

    private func alpha(_ layer: CALayer, at point: CGPoint, size: Int = 100) -> UInt8 {
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        guard let ctx = CGContext(data: &pixels, width: size, height: size, bitsPerComponent: 8,
                                  bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        layer.frame = CGRect(x: 0, y: 0, width: size, height: size)
        layer.render(in: ctx)
        return pixels[(Int(point.y) * size + Int(point.x)) * 4 + 3]
    }

    func testDropShadowApplied() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>
                <filter id="f"><feDropShadow dx="2" dy="2" stdDeviation="3" flood-color="#000000" flood-opacity="0.5"/></filter>
            </defs>
            <rect width="50" height="50" fill="#ff0000" filter="url(#f)"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let shadowLayer = try XCTUnwrap(findLayerWithShadow(in: layer))
        XCTAssertGreaterThan(shadowLayer.shadowRadius, 0)
    }

    func testPrimitiveChainDropShadowApplied() throws {
        // SVG 1.1 drop-shadow expressed as an feOffset + feFlood + feGaussianBlur chain.
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>
                <filter id="f">
                    <feGaussianBlur in="SourceAlpha" stdDeviation="3"/>
                    <feOffset dx="2" dy="-1"/>
                    <feFlood flood-color="#000000" flood-opacity="0.5"/>
                    <feComposite in2="SourceAlpha" operator="in"/>
                </filter>
            </defs>
            <rect width="50" height="50" fill="#ff0000" filter="url(#f)"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let shadowLayer = try XCTUnwrap(findLayerWithShadow(in: layer))
        XCTAssertEqual(shadowLayer.shadowOffset.width, 2, accuracy: 0.001)
        XCTAssertEqual(shadowLayer.shadowOffset.height, -1, accuracy: 0.001)
        XCTAssertEqual(shadowLayer.shadowRadius, 3, accuracy: 0.001)
        XCTAssertEqual(shadowLayer.shadowOpacity, 0.5, accuracy: 0.001)
    }

    func testGaussianBlurBlursTheElement() throws {
        // A 50×50 rect with ~3px blur: the band just outside the rect is partly opaque,
        // unlike the unfiltered rect. Sampling at y=50 (the rect is vertically centred)
        // avoids the raw-context y-flip.
        let blurred = try render("<defs><filter id=\"f\"><feGaussianBlur stdDeviation=\"3\"/></filter></defs><rect x=\"0\" y=\"25\" width=\"50\" height=\"50\" fill=\"#000000\" filter=\"url(#f)\"/>")
        let sharp = try render("<rect x=\"0\" y=\"25\" width=\"50\" height=\"50\" fill=\"#000000\"/>")
        XCTAssertGreaterThan(alpha(blurred, at: CGPoint(x: 53, y: 50)), 0)
        XCTAssertEqual(alpha(sharp, at: CGPoint(x: 53, y: 50)), 0)
    }

    func testGaussianBlurSpreadsFurtherWithLargerStdDeviation() throws {
        let small = try render("<defs><filter id=\"f\"><feGaussianBlur stdDeviation=\"2\"/></filter></defs><rect x=\"0\" y=\"25\" width=\"50\" height=\"50\" fill=\"#000000\" filter=\"url(#f)\"/>")
        let large = try render("<defs><filter id=\"f\"><feGaussianBlur stdDeviation=\"8\"/></filter></defs><rect x=\"0\" y=\"25\" width=\"50\" height=\"50\" fill=\"#000000\" filter=\"url(#f)\"/>")
        XCTAssertGreaterThan(alpha(large, at: CGPoint(x: 54, y: 50)), alpha(small, at: CGPoint(x: 54, y: 50)))
    }

    func testFigmaDropShadowChainApplied() throws {
        // Figma/Sketch export a drop-shadow as an feColorMatrix alpha extraction +
        // constant-color tint, preceded by feMorphology/feOffset/feGaussianBlur.
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>
                <filter id="f" filterUnits="userSpaceOnUse">
                    <feFlood flood-opacity="0" result="BackgroundImageFix"/>
                    <feColorMatrix in="SourceAlpha" type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0" result="hardAlpha"/>
                    <feMorphology radius="1.5" operator="erode" in="SourceAlpha"/>
                    <feOffset dy="-1.5"/>
                    <feGaussianBlur stdDeviation="0.375"/>
                    <feComposite in2="hardAlpha" operator="out"/>
                    <feColorMatrix type="matrix" values="0 0 0 0 0.105882 0 0 0 0 0.105882 0 0 0 0 0.164706 0 0 0 0.56 0"/>
                    <feBlend mode="normal" in2="BackgroundImageFix"/>
                    <feBlend mode="normal" in="SourceGraphic" in2="effect1"/>
                </filter>
            </defs>
            <rect width="50" height="50" fill="#ff0000" filter="url(#f)"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let shadowLayer = try XCTUnwrap(findLayerWithShadow(in: layer))
        XCTAssertEqual(shadowLayer.shadowOffset.height, -1.5, accuracy: 0.001)
        XCTAssertEqual(shadowLayer.shadowRadius, 0.375, accuracy: 0.001)
        XCTAssertEqual(shadowLayer.shadowOpacity, 0.56, accuracy: 0.001)
        // The shadow tint is #1B1B2A (0.105882/0.105882/0.164706) from the color matrix.
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(cgColor: shadowLayer.shadowColor!).getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(r, 0.105882, accuracy: 0.001)
        XCTAssertEqual(g, 0.105882, accuracy: 0.001)
        XCTAssertEqual(b, 0.164706, accuracy: 0.001)
    }

    func testMissingFilterIsSkipped() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <rect width="50" height="50" fill="#ff0000" filter="url(#missing)"/>
        </svg>
        """
        // A missing reference is logged and skipped, not failing the document (B85).
        let layer = try SVGParser(svgString: svg, parsedRoot: nil).getLayer(overrideElements: nil)
        XCTAssertEqual(layer.sublayers?.count ?? 0, 1)
    }
}
