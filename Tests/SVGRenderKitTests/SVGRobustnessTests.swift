import XCTest
@testable import SVGRenderKit

final class SVGRobustnessTests: XCTestCase {

    private func render(_ body: String) throws -> CALayer {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" viewBox=\"0 0 100 100\">\(body)</svg>"
        return try SVGParser(svgString: svg, parsedRoot: nil).getLayer(overrideElements: nil)
    }

    func testArcWithInfiniteNumbersDoesNotCrash() {
        _ = try? render("<path d=\"M0 0 A 10 10 0 1e999 0 20 20\"/>")
        _ = try? render("<path d=\"M0 0 A 1e999 1e999 0 0 0 1e999 20\"/>")
    }

    func testArcNonZeroFlagsAreTrue() throws {
        let a = try render("<path d=\"M0 0 A 30 30 0 1 1 40 0\"/>")
        let b = try render("<path d=\"M0 0 A 30 30 0 2 2 40 0\"/>")
        let pa = (a.sublayers?.first as? CAShapeLayer)?.path?.boundingBoxOfPath
        let pb = (b.sublayers?.first as? CAShapeLayer)?.path?.boundingBoxOfPath
        XCTAssertEqual(pa, pb)
    }

    func testCircularUseDoesNotOverflowStack() {
        // B102 terminates the cycle; B119-5 drops the cyclic `<use>` with a log instead of
        // failing the document, so both shapes of the cycle render as much as they can.
        XCTAssertNoThrow(try render("<g id=\"a\"><use xlink:href=\"#a\"/></g><use xlink:href=\"#a\"/>"))
        XCTAssertNoThrow(try render("<symbol id=\"s\"><use xlink:href=\"#s\"/></symbol><use xlink:href=\"#s\"/>"))
    }

    func testRepeatedUseOfSameElementIsNotACycle() throws {
        _ = try render("<defs><rect id=\"r\" width=\"5\" height=\"5\"/></defs><use xlink:href=\"#r\"/><use xlink:href=\"#r\" x=\"10\"/>")
    }

    func testCacheResetIsThreadSafe() {
        let group = DispatchGroup()
        for i in 0..<50 {
            DispatchQueue.global().async(group: group) {
                if i % 2 == 0 { SVGCache.s.resetCache() } else { _ = SVGCache.s.get(md5: "k\(i)") }
            }
        }
        group.wait()
    }
}
