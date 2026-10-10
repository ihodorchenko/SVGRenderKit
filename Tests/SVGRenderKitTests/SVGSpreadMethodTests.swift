import XCTest
@testable import SVGRenderKit

final class SVGSpreadMethodTests: XCTestCase {

    private func findGradientLayer(in layer: CALayer) -> CAGradientLayer? {
        if let gradientLayer = layer as? CAGradientLayer {
            return gradientLayer
        }
        for sublayer in layer.sublayers ?? [] {
            if let found = findGradientLayer(in: sublayer) {
                return found
            }
        }
        return nil
    }

    private func renderGradient(spreadMethod: String?) throws -> CAGradientLayer {
        let spreadAttr = spreadMethod.map { " spreadMethod=\"\($0)\"" } ?? ""
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>
                <linearGradient id="g" x1="0" y1="0" x2="1" y2="0"\(spreadAttr)>
                    <stop offset="0" stop-color="#ff0000"/>
                    <stop offset="1" stop-color="#0000ff"/>
                </linearGradient>
            </defs>
            <rect width="100" height="100" fill="url(#g)"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        return try XCTUnwrap(findGradientLayer(in: layer))
    }

    func testSpreadMethodDefaultPadKeepsStops() throws {
        let gradientLayer = try renderGradient(spreadMethod: nil)
        let colors = try XCTUnwrap(gradientLayer.colors)
        XCTAssertEqual(colors.count, 2)
    }

    func testSpreadMethodReflectReflectsStops() throws {
        let gradientLayer = try renderGradient(spreadMethod: "reflect")
        let colors = try XCTUnwrap(gradientLayer.colors)
        XCTAssertEqual(colors.count, 3)
    }

    func testSpreadMethodRepeatRepeatsStops() throws {
        let gradientLayer = try renderGradient(spreadMethod: "repeat")
        let colors = try XCTUnwrap(gradientLayer.colors)
        XCTAssertEqual(colors.count, 4)
    }
}
