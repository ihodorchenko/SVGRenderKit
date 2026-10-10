import XCTest
@testable import SVGRenderKit

final class SVGUtilsTests: XCTestCase {

    func testTrimmed() {
        XCTAssertEqual(SVGUtils.trimmed(string: "  hello \n"), "hello")
        XCTAssertEqual(SVGUtils.trimmed(string: "no-space"), "no-space")
    }

    func testSplitBySeparator() {
        XCTAssertEqual(SVGUtils.split(string: "1 2 3", separator: " "), ["1", "2", "3"])
    }

    func testSplitBySeparatorOmitsEmptyComponents() {
        XCTAssertEqual(SVGUtils.split(string: "1,,2", separator: ","), ["1", "2"])
        XCTAssertEqual(SVGUtils.split(string: " 1  2 ", separator: " "), ["1", "2"])
    }

    func testSplitByCharacterSet() {
        let set = CharacterSet(charactersIn: ", ")
        XCTAssertEqual(SVGUtils.split(string: "1, 2,3", separatorSet: set), ["1", "2", "3"])
    }

    func testMD5() {
        // The implementation returns an uppercase hex digest.
        XCTAssertEqual(SVGUtils.md5("hello"), "5D41402ABC4B2A76B9719D911017C592")
    }

    // MARK: pathEndInfo

    func testPathEndInfoLineTangent() {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 10, y: 0))
        let info = SVGUtils.pathEndInfo(path: path)
        XCTAssertEqual(info.point.x, 10, accuracy: 0.001)
        XCTAssertEqual(info.point.y, 0, accuracy: 0.001)
        XCTAssertEqual(info.tangent.x, 10, accuracy: 0.001)
        XCTAssertEqual(info.tangent.y, 0, accuracy: 0.001)
    }

    func testPathEndInfoCubicCurveTangentUsesLastControlPoint() {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addCurve(to: CGPoint(x: 10, y: 0), controlPoint1: CGPoint(x: 0, y: 10), controlPoint2: CGPoint(x: 10, y: 10))
        let info = SVGUtils.pathEndInfo(path: path)
        XCTAssertEqual(info.point.x, 10, accuracy: 0.001)
        XCTAssertEqual(info.point.y, 0, accuracy: 0.001)
        // Tangent = end - control2 = (10,0) - (10,10) = (0,-10)
        XCTAssertEqual(info.tangent.x, 0, accuracy: 0.001)
        XCTAssertEqual(info.tangent.y, -10, accuracy: 0.001)
    }

    func testPathEndInfoQuadCurveTangentUsesControlPoint() {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addQuadCurve(to: CGPoint(x: 10, y: 0), controlPoint: CGPoint(x: 10, y: 10))
        let info = SVGUtils.pathEndInfo(path: path)
        XCTAssertEqual(info.point.x, 10, accuracy: 0.001)
        XCTAssertEqual(info.point.y, 0, accuracy: 0.001)
        // Tangent = end - control = (10,0) - (10,10) = (0,-10)
        XCTAssertEqual(info.tangent.x, 0, accuracy: 0.001)
        XCTAssertEqual(info.tangent.y, -10, accuracy: 0.001)
    }
}

final class MD5Tests: XCTestCase {

    func testKnownVectors() {
        XCTAssertEqual(MD5(""), "D41D8CD98F00B204E9800998ECF8427E")
        XCTAssertEqual(MD5("abc"), "900150983CD24FB0D6963F7D28E17F72")
        XCTAssertEqual(MD5("The quick brown fox jumps over the lazy dog"), "9E107D9D372BB6826BD81D3542A419D6")
    }
}
