import XCTest
@testable import SVGRenderKit

/// An `objectBoundingBox` gradient on a *fill* is resolved against the geometric bounding box of the
/// shape (SVG 1.1 §13.2), like a stroke gradient (B135), a mask or a clip (B133) — not against
/// `UIBezierPath.bounds`, which also counts Bézier control points and so inflates a curved shape's box.
@MainActor
final class SVGGradientFillBBoxTests: XCTestCase {

    private let size = 100

    private func render(_ body: String) throws -> [UInt8] {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\">\(body)</svg>"
        let layer = try SVGParser(svgString: svg, parsedRoot: nil).getLayer(overrideElements: nil)
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

    private func rgba(_ d: [UInt8], _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        let i = (y * size + x) * 4
        return (Int(d[i]), Int(d[i + 1]), Int(d[i + 2]), Int(d[i + 3]))
    }

    private let stops = "<stop offset=\"0\" stop-color=\"#f00\"/><stop offset=\"1\" stop-color=\"#00f\"/>"
    /// A dome: its top is y = 20 (the curve), while the control points reach y = 10.
    private let dome = "M20 50 C 20 10, 80 10, 80 50 Z"

    func testLinearFillGradientOnACurveUsesTheGeometricBox() throws {
        let geometric = try CGPath.geometricBounds(ofSVGPath: dome)
        XCTAssertEqual(geometric.minY, 20, accuracy: 0.01)

        let d = try render("""
            <defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1">\(stops)</linearGradient></defs>
            <path d="\(dome)" fill="url(#g)"/>
            """)
        let ref = try render("""
            <defs><linearGradient id="r" gradientUnits="userSpaceOnUse" x1="0" y1="\(geometric.minY)" x2="0" y2="\(geometric.maxY)">\(stops)</linearGradient></defs>
            <path d="\(dome)" fill="url(#r)"/>
            """)
        let got = rgba(d, 50, 35), want = rgba(ref, 50, 35)
        XCTAssertEqual(got.r, want.r, accuracy: 6, "got \(got), want \(want)")
        XCTAssertEqual(got.b, want.b, accuracy: 6)
    }

    func testRadialFillGradientOnACurveUsesTheGeometricBox() throws {
        let geometric = try CGPath.geometricBounds(ofSVGPath: dome)
        let d = try render("""
            <defs><radialGradient id="g" cx="0.5" cy="1" r="1" fx="0.5" fy="1">\(stops)</radialGradient></defs>
            <path d="\(dome)" fill="url(#g)"/>
            """)
        // The same circle-in-unit-square resolved by hand against the geometric box.
        let rx = geometric.width, ry = geometric.height
        let ref = try render("""
            <defs><radialGradient id="r" gradientUnits="userSpaceOnUse" cx="\(geometric.midX)" cy="\(geometric.maxY)" r="1"
                gradientTransform="translate(\(geometric.midX) \(geometric.maxY)) scale(\(rx) \(ry)) translate(-\(geometric.midX) -\(geometric.maxY))"
                fx="\(geometric.midX)" fy="\(geometric.maxY)">\(stops)</radialGradient></defs>
            <path d="\(dome)" fill="url(#r)"/>
            """)
        let got = rgba(d, 50, 30), want = rgba(ref, 50, 30)
        XCTAssertEqual(got.r, want.r, accuracy: 8, "got \(got), want \(want)")
        XCTAssertEqual(got.b, want.b, accuracy: 8)
    }
}

private extension CGPath {
    /// The geometric extent (no control points) of an SVG path string, as the kit parses it.
    static func geometricBounds(ofSVGPath d: String) throws -> CGRect {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\"><path d=\"\(d)\"/></svg>"
        let root = try SVGParser(svgString: svg, parsedRoot: nil).root
        guard let path = root?.svgElement.all.array.compactMap({ $0 as? SVGPath }).first else {
            throw SVGError.content(text: "no shape")
        }
        return path.path.cgPath.boundingBoxOfPath
    }
}
