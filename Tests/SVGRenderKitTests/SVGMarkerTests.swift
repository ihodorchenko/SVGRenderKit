import XCTest
@testable import SVGRenderKit

final class SVGMarkerTests: XCTestCase {

    private func findFilledShapeLayer(in layer: CALayer) -> CAShapeLayer? {
        if let shape = layer as? CAShapeLayer, shape.path != nil, shape.fillColor != nil {
            return shape
        }
        for sublayer in layer.sublayers ?? [] {
            if let found = findFilledShapeLayer(in: sublayer) {
                return found
            }
        }
        return nil
    }

    func testMarkerNotRenderedDirectly() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <marker id="m"><path d="M0 0 L10 5 L0 10 Z" fill="#000000"/></marker>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        XCTAssertEqual(layer.sublayers?.count ?? 0, 0)
    }

    func testMarkerEndRendersMarkerContent() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>
                <marker id="arrow" markerWidth="10" markerHeight="10" refX="5" refY="5" orient="auto">
                    <path d="M0 0 L10 5 L0 10 Z" fill="#000000"/>
                </marker>
            </defs>
            <line x1="0" y1="50" x2="90" y2="50" stroke="#000000" marker-end="url(#arrow)"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let markerShape = try XCTUnwrap(findFilledShapeLayer(in: layer))
        XCTAssertNotNil(markerShape.path)
    }

    func testMissingMarkerThrows() {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <line x1="0" y1="0" x2="100" y2="0" stroke="#000000" marker-end="url(#missing)"/>
        </svg>
        """
        XCTAssertThrowsError(try SVGParser(svgString: svg, parsedRoot: nil).getLayer(overrideElements: nil))
    }

    // MARK: marker transform (T50)

    private func findNonIdentityTransformLayer(in layer: CALayer) -> CALayer? {
        if !CATransform3DIsIdentity(layer.transform) {
            return layer
        }
        for sublayer in layer.sublayers ?? [] {
            if let found = findNonIdentityTransformLayer(in: sublayer) {
                return found
            }
        }
        return nil
    }

    func testMarkerTransformMapsRefPointToPathEnd() throws {
        // A vertical line gives a non-zero tangent angle, which distinguishes the
        // correct translate(point)·rotate·translate(-ref) order from the wrong one.
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>
                <marker id="arrow" markerWidth="10" markerHeight="10" refX="5" refY="5" orient="auto">
                    <path d="M0 0 L10 5 L0 10 Z" fill="#000000"/>
                </marker>
            </defs>
            <line x1="0" y1="0" x2="0" y2="10" stroke="#000000" marker-end="url(#arrow)"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let markerLayer = try XCTUnwrap(findNonIdentityTransformLayer(in: layer))

        let affine = CATransform3DGetAffineTransform(markerLayer.transform)
        let mapped = CGPoint(x: 5, y: 5).applying(affine)
        // The ref point must land exactly on the line's end (0, 10).
        XCTAssertEqual(mapped.x, 0, accuracy: 0.001)
        XCTAssertEqual(mapped.y, 10, accuracy: 0.001)
    }
}
