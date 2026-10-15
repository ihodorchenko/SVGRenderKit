import XCTest
import UIKit
@testable import SVGRenderKit

/// B107 — assorted spec divergences: `fill-rule: inherit`, `visibility` overrides,
/// and a dashed gradient stroke.
final class SVGSpecDivergenceTests: XCTestCase {

    private func shapeLayers(in layer: CALayer) -> [CAShapeLayer] {
        var result: [CAShapeLayer] = []
        if let shape = layer as? CAShapeLayer { result.append(shape) }
        for sublayer in layer.sublayers ?? [] { result.append(contentsOf: shapeLayers(in: sublayer)) }
        return result
    }

    private func hasHiddenAncestor(_ layer: CALayer) -> Bool {
        var current: CALayer? = layer
        while let node = current {
            if node.isHidden { return true }
            current = node.superlayer
        }
        return false
    }

    private func moveToCount(_ path: CGPath) -> Int {
        var count = 0
        path.applyWithBlock { element in
            if element.pointee.type == .moveToPoint { count += 1 }
        }
        return count
    }

    private func gradientMaskPath(in layer: CALayer) -> CGPath? {
        if let gradient = layer as? CAGradientLayer, let shape = gradient.mask as? CAShapeLayer {
            return shape.path
        }
        for sublayer in layer.sublayers ?? [] {
            if let found = gradientMaskPath(in: sublayer) { return found }
        }
        return nil
    }

    func testPathVerticesClosesEachSubpathAtItsOwnStart() {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 10, y: 0))
        path.close()
        path.move(to: CGPoint(x: 20, y: 20))
        path.addLine(to: CGPoint(x: 30, y: 20))
        path.close()

        let vertices = SVGUtils.pathVertices(path: path)
        XCTAssertEqual(vertices.count, 6)
        // The second subpath closes on (20, 20), not on the path's first vertex.
        XCTAssertEqual(vertices[5].x, 20, accuracy: 1e-6)
        XCTAssertEqual(vertices[5].y, 20, accuracy: 1e-6)
    }

    func testFillRuleInheritKeepsParentEvenOdd() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <g fill-rule="evenodd">
                <path fill-rule="inherit" d="M0 0 H50 V50 H0 Z M10 10 H40 V40 H10 Z"/>
            </g>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let shape = try XCTUnwrap(shapeLayers(in: layer).first { $0.path != nil })
        XCTAssertEqual(shape.fillRule, .evenOdd)
    }

    func testHiddenGroupDoesNotHideVisibleChild() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <g visibility="hidden">
                <rect width="10" height="10" fill="#ff0000" visibility="visible"/>
            </g>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let shape = try XCTUnwrap(shapeLayers(in: layer).first { $0.path != nil })
        XCTAssertFalse(hasHiddenAncestor(shape), "a descendant may override a hidden group")
    }

    func testHiddenGroupHidesDefaultChild() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <g visibility="hidden"><rect width="10" height="10" fill="#ff0000"/></g>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let shape = try XCTUnwrap(shapeLayers(in: layer).first { $0.path != nil })
        XCTAssertTrue(hasHiddenAncestor(shape), "`visibility` is inherited")
    }

    func testDashedGradientStrokeIsDashed() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>
                <linearGradient id="g" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="100" y2="0">
                    <stop offset="0" stop-color="#ff0000"/>
                    <stop offset="1" stop-color="#0000ff"/>
                </linearGradient>
            </defs>
            <path d="M10 50 H90" fill="none" stroke="url(#g)" stroke-width="4" stroke-dasharray="10 5"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let maskPath = try XCTUnwrap(gradientMaskPath(in: layer))
        XCTAssertGreaterThan(moveToCount(maskPath), 1, "the gradient stroke must follow the dash pattern")
    }
}
