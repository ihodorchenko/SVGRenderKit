import XCTest
@testable import SVGRenderKit

/// B133 (c) — `marker-start/mid` follow the curve tangents and treat each subpath end as its own vertex.
final class SVGMarkerTangentTests: XCTestCase {

    /// Marker placements in drawing order: (point, angle in degrees). The marker's ref point is the origin.
    private func placements(_ pathData: String, markers: String) throws -> [(point: CGPoint, angle: Double)] {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs><marker id="m" markerWidth="4" markerHeight="4" refX="0" refY="0" orient="auto"><rect width="4" height="4"/></marker></defs>
            <path d="\(pathData)" fill="none" stroke="#000" \(markers)/>
        </svg>
        """
        let layer = try SVGParser(svgString: svg, parsedRoot: nil).getLayer(overrideElements: nil)
        var found: [(CGPoint, Double)] = []
        func walk(_ l: CALayer) {
            if !CATransform3DIsIdentity(l.transform) {
                let t = CATransform3DGetAffineTransform(l.transform)
                found.append((CGPoint(x: t.tx, y: t.ty), atan2(Double(t.b), Double(t.a)) * 180 / .pi))
            }
            (l.sublayers ?? []).forEach(walk)
        }
        walk(layer)
        return found.map { (point: $0.0, angle: $0.1) }
    }

    func testMidMarkerFollowsCurveTangentsNotChords() throws {
        // Two cubics meeting at (50,50): both arrive and leave straight down, though the chords are horizontal.
        let m = try placements("M10 50 C10 10 50 10 50 50 C50 90 90 90 90 50", markers: "marker-mid=\"url(#m)\"")
        XCTAssertEqual(m.count, 1)
        XCTAssertEqual(m[0].point.x, 50, accuracy: 1e-6)
        XCTAssertEqual(m[0].angle, 90, accuracy: 0.5)
    }

    func testStartMarkerFollowsTheCurveTangent() throws {
        // The first control point is straight above the start: the curve leaves upwards (−90°), the chord points right.
        let m = try placements("M10 50 C10 10 90 10 90 50", markers: "marker-start=\"url(#m)\"")
        XCTAssertEqual(m.count, 1)
        XCTAssertEqual(m[0].angle, -90, accuracy: 0.5)
    }

    func testSubpathJointIsTwoVerticesEachFollowingItsOwnSegment() throws {
        let m = try placements("M10 10 L30 10 M50 50 L50 80", markers: "marker-mid=\"url(#m)\"")
        XCTAssertEqual(m.count, 2)
        XCTAssertEqual(m[0].point.x, 30, accuracy: 1e-6)
        XCTAssertEqual(m[0].angle, 0, accuracy: 0.5, "end of the first subpath: the way it arrived")
        XCTAssertEqual(m[1].point.x, 50, accuracy: 1e-6)
        XCTAssertEqual(m[1].angle, 90, accuracy: 0.5, "start of the second subpath: the way it leaves")
    }

    func testPolylineBisectorIsUnchanged() throws {
        let m = try placements("M10 10 L50 10 L50 50", markers: "marker-mid=\"url(#m)\"")
        XCTAssertEqual(m.count, 1)
        XCTAssertEqual(m[0].angle, 45, accuracy: 0.5)
    }
}
