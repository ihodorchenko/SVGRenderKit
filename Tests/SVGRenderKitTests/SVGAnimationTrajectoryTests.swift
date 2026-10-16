import XCTest
@testable import SVGRenderKit

/// B131 — `animateTransform` must move a point along the path SMIL prescribes, not merely
/// carry the right keyframe values. Core Animation interpolates a `transform` by decomposing
/// the two matrices (angle, translation) and lerping the parts, so a big angular step makes the
/// pivot drift off its circle. The tests therefore sample the *geometry* — where a probe point
/// is at time `u` — using the same decomposition CA applies between adjacent keyframes.
final class SVGAnimationTrajectoryTests: XCTestCase {

    // MARK: Helpers

    private func animation(_ transformAnimation: String) throws -> CAAnimation {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <rect width="50" height="50" fill="#ff0000">\(transformAnimation)</rect>
        </svg>
        """
        let layer = try SVGParser(svgString: svg, parsedRoot: nil).getLayer(overrideElements: nil)
        return try XCTUnwrap(findAnimated(layer)?.animation(forKey: "transform"))
    }

    private func findAnimated(_ layer: CALayer) -> CALayer? {
        if layer.animationKeys()?.contains("transform") == true { return layer }
        for sub in layer.sublayers ?? [] { if let f = findAnimated(sub) { return f } }
        return nil
    }

    private struct Parts { var angle: CGFloat; var tx: CGFloat; var ty: CGFloat }

    private func parts(_ t: CATransform3D) -> Parts {
        Parts(angle: atan2(t.m12, t.m11), tx: t.m41, ty: t.m42)
    }

    /// The transform at normalised time `u` (0…1), interpolating the way CA does.
    private func transform(of anim: CAAnimation, at u: Double) throws -> CATransform3D {
        var times: [Double] = []
        var matrices: [CATransform3D] = []
        if let basic = anim as? CABasicAnimation {
            matrices = [try XCTUnwrap((basic.fromValue as? NSValue)?.caTransform3DValue),
                        try XCTUnwrap((basic.toValue as? NSValue)?.caTransform3DValue)]
            times = [0, 1]
        } else {
            let key = try XCTUnwrap(anim as? CAKeyframeAnimation)
            matrices = try XCTUnwrap(key.values).map { try XCTUnwrap(($0 as? NSValue)?.caTransform3DValue) }
            times = key.keyTimes?.map { $0.doubleValue }
                ?? matrices.indices.map { Double($0) / Double(matrices.count - 1) }
        }
        var i = 0
        while i < times.count - 2 && u >= times[i + 1] { i += 1 }
        let span = times[i + 1] - times[i]
        let f = span > 0 ? CGFloat((u - times[i]) / span) : 0
        let a = parts(matrices[i]), b = parts(matrices[i + 1])
        // CA takes the shortest way between two orientations.
        let delta = atan2(sin(b.angle - a.angle), cos(b.angle - a.angle))
        let angle = a.angle + delta * f
        var t = CATransform3DMakeRotation(angle, 0, 0, 1)
        t.m41 = a.tx + (b.tx - a.tx) * f
        t.m42 = a.ty + (b.ty - a.ty) * f
        return t
    }

    private func lastMatrix(_ anim: CAAnimation) throws -> CATransform3D {
        let key = try XCTUnwrap(anim as? CAKeyframeAnimation)
        return try XCTUnwrap((key.values?.last as? NSValue)?.caTransform3DValue)
    }

    private func point(_ p: CGPoint, _ anim: CAAnimation, at u: Double) throws -> CGPoint {
        p.applying(CATransform3DGetAffineTransform(try transform(of: anim, at: u)))
    }

    /// Where SMIL puts `p` for a rotation of `angle` degrees about `c`.
    private func expected(_ p: CGPoint, angle: Double, about c: CGPoint) -> CGPoint {
        let r = angle * .pi / 180
        let dx = p.x - c.x, dy = p.y - c.y
        return CGPoint(x: c.x + dx * cos(r) - dy * sin(r), y: c.y + dx * sin(r) + dy * cos(r))
    }

    private func assertClose(_ a: CGPoint, _ b: CGPoint, accuracy: CGFloat = 0.5, _ message: String = "",
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: accuracy, message, file: file, line: line)
    }

    private let probe = CGPoint(x: 0, y: 0)

    // MARK: rotate

    func testFullTurnKeepsProbeOnItsCircle() throws {
        let anim = try animation(#"<animateTransform attributeName="transform" type="rotate" from="0 12 12" to="360 12 12" dur="2s"/>"#)
        for u in stride(from: 0.0, through: 1.0, by: 0.05) {
            assertClose(try point(probe, anim, at: u), expected(probe, angle: 360 * u, about: CGPoint(x: 12, y: 12)), "u=\(u)")
        }
    }

    func testThreeValuesKeepProbeOnItsCircle() throws {
        let anim = try animation(#"<animateTransform attributeName="transform" type="rotate" values="0 12 12;120 12 12;240 12 12" dur="3s"/>"#)
        for u in stride(from: 0.0, through: 1.0, by: 0.05) {
            assertClose(try point(probe, anim, at: u), expected(probe, angle: 240 * u, about: CGPoint(x: 12, y: 12)), "u=\(u)")
        }
    }

    func testExactHalfTurnTakesTheRequestedWay() throws {
        let anim = try animation(#"<animateTransform attributeName="transform" type="rotate" from="0 12 12" to="180 12 12" dur="2s"/>"#)
        for u in stride(from: 0.0, through: 1.0, by: 0.1) {
            assertClose(try point(probe, anim, at: u), expected(probe, angle: 180 * u, about: CGPoint(x: 12, y: 12)), "u=\(u)")
        }
    }

    func testNegativeSweepIsClockwiseBack() throws {
        let anim = try animation(#"<animateTransform attributeName="transform" type="rotate" from="0 12 12" to="-270 12 12" dur="2s"/>"#)
        for u in stride(from: 0.0, through: 1.0, by: 0.1) {
            assertClose(try point(probe, anim, at: u), expected(probe, angle: -270 * u, about: CGPoint(x: 12, y: 12)), "u=\(u)")
        }
    }

    func testKeyTimesAreHonouredAcrossSubdivision() throws {
        let anim = try animation(#"<animateTransform attributeName="transform" type="rotate" values="0 12 12;180 12 12;360 12 12" keyTimes="0;0.25;1" dur="2s"/>"#)
        // First half-turn takes a quarter of the time, the second three quarters.
        assertClose(try point(probe, anim, at: 0.125), expected(probe, angle: 90, about: CGPoint(x: 12, y: 12)))
        assertClose(try point(probe, anim, at: 0.25), expected(probe, angle: 180, about: CGPoint(x: 12, y: 12)))
        assertClose(try point(probe, anim, at: 0.625), expected(probe, angle: 270, about: CGPoint(x: 12, y: 12)))
    }

    func testCentreIsTakenFromEveryValue() throws {
        // The centre slides (0,0) → (10,10) → (20,20) while the angle goes 0 → 90 → 180.
        let anim = try animation(#"<animateTransform attributeName="transform" type="rotate" values="0 0 0;90 10 10;180 20 20" dur="2s"/>"#)
        let p = CGPoint(x: 5, y: 0)
        assertClose(try point(p, anim, at: 0.25), expected(p, angle: 45, about: CGPoint(x: 5, y: 5)))
        assertClose(try point(p, anim, at: 0.5), expected(p, angle: 90, about: CGPoint(x: 10, y: 10)))
        assertClose(try point(p, anim, at: 0.75), expected(p, angle: 135, about: CGPoint(x: 15, y: 15)))
        assertClose(try point(p, anim, at: 1), expected(p, angle: 180, about: CGPoint(x: 20, y: 20)))
    }

    func testRotateWithoutCentreSpinsAboutOrigin() throws {
        let anim = try animation(#"<animateTransform attributeName="transform" type="rotate" from="0" to="360" dur="2s"/>"#)
        let p = CGPoint(x: 10, y: 0)
        assertClose(try point(p, anim, at: 0.25), CGPoint(x: 0, y: 10))
        assertClose(try point(p, anim, at: 0.5), CGPoint(x: -10, y: 0))
    }

    // MARK: skew

    func testSkewXAnimatesInsteadOfBecomingIdentity() throws {
        let anim = try animation(#"<animateTransform attributeName="transform" type="skewX" values="0;30" dur="2s"/>"#)
        let end = try lastMatrix(anim)
        XCTAssertEqual(end.m21, tan(30 * .pi / 180), accuracy: 1e-4)
        XCTAssertEqual(end.m12, 0, accuracy: 1e-6)
    }

    func testSkewYAnimatesInsteadOfBecomingIdentity() throws {
        let anim = try animation(#"<animateTransform attributeName="transform" type="skewY" from="0" to="45" dur="2s"/>"#)
        let end = try lastMatrix(anim)
        XCTAssertEqual(end.m12, 1, accuracy: 1e-4)
    }

    // MARK: begin

    func testBeginIsRelativeToTheDocumentEpoch() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <rect width="50" height="50"><animate attributeName="opacity" from="0" to="1" dur="1s" begin="2s"/></rect>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        parser.root.getSvgOptions().animationEpoch = 1000
        let layer = try parser.getLayer(overrideElements: nil)
        parser.root.getSvgOptions().animationEpoch = nil
        let animated = try XCTUnwrap(findAnimatedKey(layer, "opacity"))
        XCTAssertEqual(animated.animation(forKey: "opacity")?.beginTime ?? 0, 1002, accuracy: 1e-6)
    }

    private func findAnimatedKey(_ layer: CALayer, _ key: String) -> CALayer? {
        if layer.animationKeys()?.contains(key) == true { return layer }
        for sub in layer.sublayers ?? [] { if let f = findAnimatedKey(sub, key) { return f } }
        return nil
    }
}
