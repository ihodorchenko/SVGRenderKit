import XCTest
@testable import SVGRenderKit

final class SVGPatternTests: XCTestCase {

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

    private func isPatternColor(_ color: CGColor?) -> Bool {
        guard let color = color else { return false }
        return color.pattern != nil
    }

    func testPatternNotRenderedDirectly() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <pattern id="p" width="10" height="10"><rect width="10" height="10" fill="#ff0000"/></pattern>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        XCTAssertEqual(layer.sublayers?.count ?? 0, 0)
    }

    func testPatternAppliedAsFill() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>
                <pattern id="p" width="10" height="10" patternUnits="userSpaceOnUse">
                    <rect width="10" height="10" fill="#ff0000"/>
                </pattern>
            </defs>
            <rect width="100" height="100" fill="url(#p)"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let shape = try XCTUnwrap(findFilledShapeLayer(in: layer))
        XCTAssertTrue(isPatternColor(shape.fillColor))
    }

    func testMissingPatternIsSkipped() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <rect width="100" height="100" fill="url(#missing)"/>
        </svg>
        """
        // A missing reference is logged and skipped, not failing the document (B85).
        let layer = try SVGParser(svgString: svg, parsedRoot: nil).getLayer(overrideElements: nil)
        XCTAssertEqual(layer.sublayers?.count ?? 0, 1)
    }
}
