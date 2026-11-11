import XCTest
@testable import SVGRenderKit

/// M3.2 — the CSS `transform` property with `transform-origin` and `transform-box`.
final class SVGTransformStyleTests: XCTestCase {

    // MARK: Helpers

    private func layer(_ body: String, viewBox: String = "0 0 100 100") throws -> CALayer {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"\(viewBox)\">\(body)</svg>"
        return try SVGParser(svgString: svg, parsedRoot: nil).getLayer(overrideElements: nil)
    }

    /// The main layer of the first shape (its parent), where the shape's transform lives.
    private func mainLayer(_ root: CALayer) throws -> CALayer {
        func firstShape(_ layer: CALayer) -> CAShapeLayer? {
            if let shape = layer as? CAShapeLayer, shape.path != nil { return shape }
            for sublayer in layer.sublayers ?? [] {
                if let found = firstShape(sublayer) { return found }
            }
            return nil
        }
        let shape = try XCTUnwrap(firstShape(root))
        return try XCTUnwrap(shape.superlayer)
    }

    private func mainLayers(_ root: CALayer) -> [CALayer] {
        var result: [CALayer] = []
        if let shape = root as? CAShapeLayer, shape.path != nil, let parent = shape.superlayer {
            result.append(parent)
        }
        for sublayer in root.sublayers ?? [] { result += mainLayers(sublayer) }
        return result
    }

    private func point(_ transform: CATransform3D, _ x: CGFloat, _ y: CGFloat) -> CGPoint {
        return CGPoint(x: x, y: y).applying(CATransform3DGetAffineTransform(transform))
    }

    private func animation(_ layer: CALayer, key: String) throws -> CAAnimation {
        func find(_ layer: CALayer) -> CALayer? {
            if layer.animationKeys()?.contains(key) == true { return layer }
            for sublayer in layer.sublayers ?? [] {
                if let found = find(sublayer) { return found }
            }
            return nil
        }
        let animated = try XCTUnwrap(find(layer), "no \(key) animation")
        return try XCTUnwrap(animated.animation(forKey: key))
    }

    private func matrices(_ animation: CAAnimation) throws -> [CATransform3D] {
        if let basic = animation as? CABasicAnimation {
            return [try XCTUnwrap((basic.fromValue as? NSValue)?.caTransform3DValue),
                    try XCTUnwrap((basic.toValue as? NSValue)?.caTransform3DValue)]
        }
        let keyframe = try XCTUnwrap(animation as? CAKeyframeAnimation)
        return try XCTUnwrap(keyframe.values).map { try XCTUnwrap(($0 as? NSValue)?.caTransform3DValue) }
    }

    // MARK: Static transform property

    func testCSSStaticTransformProperty() throws {
        let transform = try mainLayer(try layer("""
        <style>.r{transform:translate(10px, 20px)}</style>
        <path class="r" d="M0 0h10v10z"/>
        """)).transform
        XCTAssertEqual(transform.m41, 10, accuracy: 1e-6)
        XCTAssertEqual(transform.m42, 20, accuracy: 1e-6)
    }

    func testCSSTransformOverridesTheAttributeAndInlineWins() throws {
        let attribute = try mainLayer(try layer("""
        <path transform="translate(5, 0)" d="M0 0h10v10z"/>
        """)).transform
        XCTAssertEqual(attribute.m41, 5, accuracy: 1e-6)

        let rule = try mainLayer(try layer("""
        <style>.r{transform:translate(10px, 0)}</style>
        <path class="r" transform="translate(5, 0)" d="M0 0h10v10z"/>
        """)).transform
        XCTAssertEqual(rule.m41, 10, accuracy: 1e-6)

        let inline = try mainLayer(try layer("""
        <style>.r{transform:translate(10px, 0)}</style>
        <path class="r" transform="translate(5, 0)" style="transform:translate(15px, 0)" d="M0 0h10v10z"/>
        """)).transform
        XCTAssertEqual(inline.m41, 15, accuracy: 1e-6)

        let none = try mainLayer(try layer("""
        <path transform="translate(5, 0)" style="transform:none" d="M0 0h10v10z"/>
        """)).transform
        XCTAssertTrue(CATransform3DIsIdentity(none), "CSS `transform: none` replaces the attribute")
    }

    func testPercentTranslateUsesTheViewBox() throws {
        let transform = try mainLayer(try layer("""
        <style>.r{transform:translate(50%, 10%)}</style>
        <path class="r" d="M0 0h10v10z"/>
        """, viewBox: "0 0 100 200")).transform
        XCTAssertEqual(transform.m41, 50, accuracy: 1e-6)
        XCTAssertEqual(transform.m42, 20, accuracy: 1e-6)
    }

    func testInvalidCSSTransformFallsBackToTheAttribute() throws {
        let transform = try mainLayer(try layer("""
        <style>.r{transform:matrix3d(1, 0)}</style>
        <path class="r" transform="translate(5, 0)" d="M0 0h10v10z"/>
        """)).transform
        XCTAssertEqual(transform.m41, 5, accuracy: 1e-6)
    }

    // MARK: transform-origin

    func testTransformOriginRotatesAroundThePoint() throws {
        let transform = try mainLayer(try layer("""
        <style>.r{transform:rotate(90deg);transform-origin:10px 0px}</style>
        <path class="r" d="M0 0h10v10z"/>
        """)).transform
        let fixed = point(transform, 10, 0)
        XCTAssertEqual(fixed.x, 10, accuracy: 1e-6)
        XCTAssertEqual(fixed.y, 0, accuracy: 1e-6)
        let moved = point(transform, 0, 0)
        XCTAssertEqual(moved.x, 10, accuracy: 1e-6)
        XCTAssertEqual(moved.y, -10, accuracy: 1e-6)
    }

    func testTransformOriginPercentagesAndKeywords() throws {
        let percent = try mainLayer(try layer("""
        <style>.r{transform:rotate(180deg);transform-origin:50% 50%}</style>
        <path class="r" d="M0 0h10v10z"/>
        """)).transform
        let percentFixed = point(percent, 50, 50)
        XCTAssertEqual(percentFixed.x, 50, accuracy: 1e-6)
        XCTAssertEqual(percentFixed.y, 50, accuracy: 1e-6)

        let keywords = try mainLayer(try layer("""
        <style>.r{transform:rotate(180deg);transform-origin:right bottom}</style>
        <path class="r" d="M0 0h10v10z"/>
        """)).transform
        let keywordFixed = point(keywords, 100, 100)
        XCTAssertEqual(keywordFixed.x, 100, accuracy: 1e-6)
        XCTAssertEqual(keywordFixed.y, 100, accuracy: 1e-6)
    }

    // MARK: transform-box

    func testTransformBoxFillBoxUsesTheShapeBounds() throws {
        let transform = try mainLayer(try layer("""
        <style>.r{transform-box:fill-box;transform-origin:center;transform:rotate(180deg)}</style>
        <rect class="r" x="10" y="20" width="20" height="10"/>
        """)).transform
        let center = point(transform, 20, 25)
        XCTAssertEqual(center.x, 20, accuracy: 1e-6)
        XCTAssertEqual(center.y, 25, accuracy: 1e-6)
        let corner = point(transform, 10, 20)
        XCTAssertEqual(corner.x, 30, accuracy: 1e-6)
        XCTAssertEqual(corner.y, 30, accuracy: 1e-6)
    }

    func testGroupFillBoxUsesItsContentBounds() throws {
        let root = try layer("""
        <style>.g{transform-box:fill-box;transform-origin:center;transform:rotate(180deg)}</style>
        <g class="g"><rect x="10" y="20" width="20" height="10"/></g>
        """)
        // The group layer is the outermost layer with a transform.
        let groupLayer = try XCTUnwrap(root.sublayers?.first)
        XCTAssertFalse(CATransform3DIsIdentity(groupLayer.transform))
        let center = point(groupLayer.transform, 20, 25)
        XCTAssertEqual(center.x, 20, accuracy: 1e-6)
        XCTAssertEqual(center.y, 25, accuracy: 1e-6)
    }

    func testGroupStaticTransform() throws {
        let root = try layer("""
        <style>.g{transform:translate(10px, 0)}</style>
        <g class="g"><rect x="0" y="0" width="10" height="10"/></g>
        """)
        let groupLayer = try XCTUnwrap(root.sublayers?.first)
        XCTAssertEqual(groupLayer.transform.m41, 10, accuracy: 1e-6)
    }

    // MARK: Animated transforms

    func testAnimatedTransformUsesTransformOrigin() throws {
        let animation = try animation(try layer("""
        <style>
            @keyframes spin{0%{transform:rotate(0deg)}100%{transform:rotate(90deg)}}
            .r{transform-origin:10px 0px;animation:spin 1s linear infinite}
        </style>
        <path class="r" d="M0 0h10v10z"/>
        """), key: "transform")
        let values = try matrices(animation)
        let fixed = point(values[1], 10, 0)
        XCTAssertEqual(fixed.x, 10, accuracy: 1e-6)
        XCTAssertEqual(fixed.y, 0, accuracy: 1e-6)
        let start = point(values[0], 0, 0)
        XCTAssertEqual(start.x, 0, accuracy: 1e-6)
        XCTAssertEqual(start.y, 0, accuracy: 1e-6)
    }

    func testAnimatedTransformBoxFillBox() throws {
        let animation = try animation(try layer("""
        <style>
            @keyframes spin{0%{transform:rotate(0deg)}100%{transform:rotate(180deg)}}
            .r{transform-box:fill-box;transform-origin:center;animation:spin 1s linear infinite}
        </style>
        <rect class="r" x="10" y="20" width="20" height="10"/>
        """), key: "transform")
        let values = try matrices(animation)
        let fixed = point(values[1], 20, 25)
        XCTAssertEqual(fixed.x, 20, accuracy: 1e-6)
        XCTAssertEqual(fixed.y, 25, accuracy: 1e-6)
    }

    func testStaticCSSTransformIsTheImplicitAnimationEndpoint() throws {
        let animation = try animation(try layer("""
        <style>
            @keyframes shift{50%{transform:translateX(30px)}}
            .r{transform:translateX(10px);animation:shift 1s linear infinite}
        </style>
        <path class="r" d="M0 0h10v10z"/>
        """), key: "transform")
        let values = try matrices(animation)
        XCTAssertEqual(values.count, 3)
        XCTAssertEqual(values[0].m41, 10, accuracy: 1e-6)
        XCTAssertEqual(values[1].m41, 30, accuracy: 1e-6)
        XCTAssertEqual(values[2].m41, 10, accuracy: 1e-6)
    }

    func testGroupAnimatedTransformUsesItsOwnOrigin() throws {
        let root = try layer("""
        <style>
            @keyframes spin{0%{transform:rotate(0deg)}100%{transform:rotate(90deg)}}
            .g{transform-box:fill-box;transform-origin:center;animation:spin 1s linear infinite}
        </style>
        <g class="g"><rect x="10" y="20" width="20" height="10"/></g>
        """)
        let animation = try animation(root, key: "transform")
        let values = try matrices(animation)
        let fixed = point(values[1], 20, 25)
        XCTAssertEqual(fixed.x, 20, accuracy: 1e-6)
        XCTAssertEqual(fixed.y, 25, accuracy: 1e-6)
    }
}
