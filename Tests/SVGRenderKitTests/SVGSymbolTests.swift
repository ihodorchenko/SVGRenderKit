import XCTest
@testable import SVGRenderKit

final class SVGSymbolTests: XCTestCase {

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

    private func findTransformedLayer(in layer: CALayer) -> CALayer? {
        if !CATransform3DIsIdentity(layer.transform) {
            return layer
        }
        for sublayer in layer.sublayers ?? [] {
            if let found = findTransformedLayer(in: sublayer) {
                return found
            }
        }
        return nil
    }

    func testSymbolNotRenderedDirectly() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <symbol id="s" viewBox="0 0 10 10"><rect width="10" height="10" fill="#ff0000"/></symbol>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        XCTAssertEqual(layer.sublayers?.count ?? 0, 0)
    }

    func testUseRendersSymbolContent() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <symbol id="s" viewBox="0 0 10 10"><rect width="10" height="10" fill="#ff0000"/></symbol>
            <use href="#s" x="10" y="10" width="10" height="10"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let shape = try XCTUnwrap(findFilledShapeLayer(in: layer))
        XCTAssertNotNil(shape.path)
    }

    func testUseScalesSymbolByViewBox() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <symbol id="s" viewBox="0 0 10 10"><rect width="10" height="10" fill="#ff0000"/></symbol>
            <use href="#s" width="20" height="20"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let transformed = try XCTUnwrap(findTransformedLayer(in: layer))
        XCTAssertEqual(transformed.transform.m11, 2, accuracy: 0.0001)
        XCTAssertEqual(transformed.transform.m22, 2, accuracy: 0.0001)
    }

    func testUseMissingTargetIsSkipped() throws {
        // A broken reference must not fail the document (B119-5): the `<use>` is logged
        // and dropped, everything else still renders.
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <use href="#missing"/>
            <rect width="10" height="10" fill="#ff0000"/>
        </svg>
        """
        let layer = try SVGParser(svgString: svg, parsedRoot: nil).getLayer(overrideElements: nil)
        XCTAssertNotNil(findFilledShapeLayer(in: layer))
    }

    func testUseXYIsScaledByUseTransform() throws {
        // Per SVG 1.1 §5.6 the generated content for `<use>` is
        // `<g transform="[transform] translate(x,y)">`: the x/y translate is
        // appended to the right of the transform and is scaled by it, so with
        // transform="scale(2)" the content lands at x=20, not x=10.
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs><rect id="r" width="10" height="10" fill="#000000"/></defs>
            <use href="#r" x="10" transform="scale(2)"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let transformed = try XCTUnwrap(findTransformedLayer(in: layer))
        let affine = CATransform3DGetAffineTransform(transformed.transform)
        let mapped = CGPoint(x: 0, y: 0).applying(affine)
        XCTAssertEqual(mapped.x, 20, accuracy: 0.001)
        XCTAssertEqual(mapped.y, 0, accuracy: 0.001)
    }

    func testUseSymbolXYIsScaledByUseTransform() throws {
        // Same rule when the reference is a `<symbol>`: the viewBox fit is
        // innermost, then the use's x/y translate, then its transform.
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <symbol id="s" viewBox="0 0 10 10"><rect width="10" height="10" fill="#ff0000"/></symbol>
            <use href="#s" x="10" width="10" height="10" transform="scale(2)"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let transformed = try XCTUnwrap(findTransformedLayer(in: layer))
        let affine = CATransform3DGetAffineTransform(transformed.transform)
        let mapped = CGPoint(x: 0, y: 0).applying(affine)
        XCTAssertEqual(mapped.x, 20, accuracy: 0.001)
        XCTAssertEqual(mapped.y, 0, accuracy: 0.001)
    }
}
