import XCTest
@testable import SVGRenderKit

final class SVGBasicShapesTests: XCTestCase {

    /// Collects the bounding boxes of every concrete path in the layer tree.
    /// Each shape contributes its `pathLayer` sublayer, which holds the resolved
    /// `UIBezierPath` built from the parsed geometry.
    private func pathBounds(in layer: CALayer) -> [CGRect] {
        var result: [CGRect] = []
        if let shape = layer as? CAShapeLayer, let path = shape.path {
            result.append(path.boundingBox)
        }
        for sub in layer.sublayers ?? [] {
            result.append(contentsOf: pathBounds(in: sub))
        }
        return result
    }

    private func render(_ svg: String) throws -> [CGRect] {
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        return pathBounds(in: layer)
    }

    func testRectPercentWidthResolvesAgainstViewBox() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <rect x="10" y="10" width="50%" height="20" fill="#ff0000"/>
        </svg>
        """
        let bounds = try render(svg)
        XCTAssertTrue(bounds.contains { abs($0.width - 50) < 0.001 && abs($0.height - 20) < 0.001 },
                      "expected 50x20 rect, got \(bounds)")
    }

    func testRectPxResolvesToUserUnits() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <rect x="10" y="10" width="50px" height="20px" fill="#ff0000"/>
        </svg>
        """
        let bounds = try render(svg)
        XCTAssertTrue(bounds.contains { abs($0.width - 50) < 0.001 && abs($0.height - 20) < 0.001 },
                      "expected 50x20 rect, got \(bounds)")
    }

    func testRectRelativeUnitDegradesGracefully() throws {
        // Relative units (`em`) are out of scope; they must not fail the parse.
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <rect x="10" y="10" width="2em" height="20" fill="#ff0000"/>
        </svg>
        """
        _ = try render(svg) // must not throw
    }

    func testCircleRadiusPercentResolvesAgainstDiagonal() throws {
        // r="25%" resolves against the normalized diagonal sqrt((w²+h²)/2) = 100.
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <circle cx="50" cy="50" r="25%" fill="#ff0000"/>
        </svg>
        """
        let bounds = try render(svg)
        XCTAssertTrue(bounds.contains { abs($0.width - 50) < 0.001 && abs($0.height - 50) < 0.001 },
                      "expected 50x50 circle bounds, got \(bounds)")
    }

    func testLinePercentResolvesAgainstViewBox() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <line x1="10" y1="10" x2="50%" y2="90" stroke="#ff0000" stroke-width="4"/>
        </svg>
        """
        let bounds = try render(svg)
        // Line spans x=10..50, y=10..90.
        XCTAssertTrue(bounds.contains { abs($0.maxX - 50) < 0.001 && abs($0.maxY - 90) < 0.001 },
                      "expected line ending at (50,90), got \(bounds)")
    }

    func testPolylinePolygonAcceptWhitespaceSeparators() throws {
        // The `points` list may separate coordinates with newlines and tabs, not
        // just spaces and commas.
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <polyline points="0,0 10,10
        20,0" fill="none" stroke="#ff0000" stroke-width="2"/>
            <polygon points="0,0\t10,10 20,0" fill="#00ff00"/>
        </svg>
        """
        let bounds = try render(svg)
        // Both shapes span x=0..20, y=0..10.
        XCTAssertTrue(bounds.contains { abs($0.maxX - 20) < 0.001 && abs($0.maxY - 10) < 0.001 },
                      "expected a path spanning (0,0)-(20,10), got \(bounds)")
    }
}
