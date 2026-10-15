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

    // MARK: Second pass (values / keyTimes / repeatCount / set)

    func testSetElementSetsFillColor() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <rect width="50" height="50" fill="#ff0000">
                <set attributeName="fill" to="#0000ff"/>
            </rect>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let shape = try XCTUnwrap(findFilledShapeLayer(in: layer))
        let ui = UIColor(cgColor: try XCTUnwrap(shape.fillColor))
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(r, 0, accuracy: 1e-3)
        XCTAssertEqual(b, 1, accuracy: 1e-3)
    }

    func testAnimateValuesProducesKeyframeAnimation() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <rect width="50" height="50" fill="#ff0000">
                <animate attributeName="opacity" values="0;1;0" dur="2s"/>
            </rect>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let animated = try XCTUnwrap(findLayerWithAnimation(in: layer, key: "opacity"))
        let anim = try XCTUnwrap(animated.animation(forKey: "opacity"))
        XCTAssertTrue(anim is CAKeyframeAnimation)
        XCTAssertEqual(anim.duration, 2.0)
    }

    func testRepeatCountIndefinite() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <rect width="50" height="50" fill="#ff0000">
                <animate attributeName="opacity" from="0" to="1" dur="1s" repeatCount="indefinite"/>
            </rect>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let animated = try XCTUnwrap(findLayerWithAnimation(in: layer, key: "opacity"))
        let anim = try XCTUnwrap(animated.animation(forKey: "opacity"))
        XCTAssertEqual(anim.repeatCount, .infinity)
    }

    func testBeginDelayUsesHostTime() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <rect width="50" height="50" fill="#ff0000">
                <animate attributeName="opacity" from="0" to="1" dur="1s" begin="2s"/>
            </rect>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let animated = try XCTUnwrap(findLayerWithAnimation(in: layer, key: "opacity"))
        let anim = try XCTUnwrap(animated.animation(forKey: "opacity"))
        XCTAssertGreaterThan(anim.beginTime, 2)
    }

    // MARK: B103 — rotate centre, comma-separated values, full turns

    private func transformValue(_ value: Any?) -> CATransform3D? {
        (value as? NSValue)?.caTransform3DValue
    }

    private func transformAnimation(in layer: CALayer) throws -> CAAnimation {
        let animated = try XCTUnwrap(findLayerWithAnimation(in: layer, key: "transform"))
        return try XCTUnwrap(animated.animation(forKey: "transform"))
    }

    func testRotateAboutCenterHonorsCenter() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <rect width="50" height="50" fill="#ff0000">
                <animateTransform attributeName="transform" type="rotate" from="0 12 12" to="180 12 12" dur="2s"/>
            </rect>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let basic = try XCTUnwrap(try transformAnimation(in: layer) as? CABasicAnimation)
        let to = try XCTUnwrap(transformValue(basic.toValue))
        // 180° about (12, 12): the origin maps to (24, 24).
        let point = CGPoint(x: 0, y: 0).applying(CATransform3DGetAffineTransform(to))
        XCTAssertEqual(point.x, 24, accuracy: 1e-4)
        XCTAssertEqual(point.y, 24, accuracy: 1e-4)
    }

    func testCommaSeparatedTransformValues() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <rect width="50" height="50" fill="#ff0000">
                <animateTransform attributeName="transform" type="translate" from="0,0" to="10,0" dur="2s"/>
            </rect>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let basic = try XCTUnwrap(try transformAnimation(in: layer) as? CABasicAnimation)
        let to = try XCTUnwrap(transformValue(basic.toValue))
        let point = CGPoint(x: 0, y: 0).applying(CATransform3DGetAffineTransform(to))
        XCTAssertEqual(point.x, 10, accuracy: 1e-4)
        XCTAssertEqual(point.y, 0, accuracy: 1e-4)
    }

    func testFullTurnRotateUsesKeyframes() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <rect width="50" height="50" fill="#ff0000">
                <animateTransform attributeName="transform" type="rotate" from="0" to="360" dur="2s"/>
            </rect>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let keyframe = try XCTUnwrap(try transformAnimation(in: layer) as? CAKeyframeAnimation)
        let values = try XCTUnwrap(keyframe.values)
        XCTAssertGreaterThanOrEqual(values.count, 3)
        // A whole turn must not be the identity throughout.
        let first = try XCTUnwrap(transformValue(values.first))
        let middle = try XCTUnwrap(transformValue(values[1]))
        XCTAssertFalse(CATransform3DEqualToTransform(first, middle))
    }

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
}
