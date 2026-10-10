import XCTest
@testable import SVGRenderKit

final class SVGAnimationTests: XCTestCase {

    private func findLayerWithAnimation(in layer: CALayer, key: String) -> CALayer? {
        if let keys = layer.animationKeys(), keys.contains(key) {
            return layer
        }
        for sublayer in layer.sublayers ?? [] {
            if let found = findLayerWithAnimation(in: sublayer, key: key) {
                return found
            }
        }
        return nil
    }

    // MARK: Duration parsing

    func testParseDuration() {
        XCTAssertEqual(SVGAnimation.parseDuration("1s"), 1.0)
        XCTAssertEqual(SVGAnimation.parseDuration("500ms"), 0.5)
        XCTAssertEqual(SVGAnimation.parseDuration("2"), 2.0)
        XCTAssertNil(SVGAnimation.parseDuration("abc"))
    }

    // MARK: animate

    func testAnimateOpacityAddsAnimation() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <rect width="50" height="50" fill="#ff0000">
                <animate attributeName="opacity" from="0" to="1" dur="1s"/>
            </rect>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        XCTAssertNotNil(findLayerWithAnimation(in: layer, key: "opacity"))
    }

    func testAnimateFillAddsAnimation() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <rect width="50" height="50" fill="#ff0000">
                <animate attributeName="fill" from="#ff0000" to="#0000ff" dur="2s"/>
            </rect>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        XCTAssertNotNil(findLayerWithAnimation(in: layer, key: "fillColor"))
    }

    func testAnimateTransformAddsAnimation() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <rect width="50" height="50" fill="#ff0000">
                <animateTransform attributeName="transform" type="rotate" from="0" to="360" dur="2s"/>
            </rect>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        XCTAssertNotNil(findLayerWithAnimation(in: layer, key: "transform"))
    }
}
