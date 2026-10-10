import XCTest
@testable import SVGRenderKit

final class SVGPreserveAspectRatioTests: XCTestCase {

    // MARK: Parsing

    func testDefaultWhenNil() {
        let par = SVGPreserveAspectRatio.get(string: nil)
        XCTAssertEqual(par.align, .xMidYMid)
        XCTAssertEqual(par.meetOrSlice, .meet)
    }

    func testDefaultWhenEmpty() {
        let par = SVGPreserveAspectRatio.get(string: "")
        XCTAssertEqual(par.align, .xMidYMid)
        XCTAssertEqual(par.meetOrSlice, .meet)
    }

    func testAlignAndSlice() {
        let par = SVGPreserveAspectRatio.get(string: "xMaxYMax slice")
        XCTAssertEqual(par.align, .xMaxYMax)
        XCTAssertEqual(par.meetOrSlice, .slice)
    }

    func testNone() {
        let par = SVGPreserveAspectRatio.get(string: "none")
        XCTAssertEqual(par.align, .none)
        XCTAssertEqual(par.meetOrSlice, .meet)
    }

    func testDeferStripped() {
        let par = SVGPreserveAspectRatio.get(string: "defer xMidYMin meet")
        XCTAssertEqual(par.align, .xMidYMin)
        XCTAssertEqual(par.meetOrSlice, .meet)
    }

    func testUnrecognizedTokenFallsBackToDefault() {
        let par = SVGPreserveAspectRatio.get(string: "bogus")
        XCTAssertEqual(par.align, .xMidYMid)
        XCTAssertEqual(par.meetOrSlice, .meet)
    }

    // MARK: Resolve

    func testMeetCentersInWideContainer() {
        let par = SVGPreserveAspectRatio.get(string: "xMidYMid meet")
        let r = par.resolve(viewBox: CGRect(x: 0, y: 0, width: 100, height: 100),
                            containerSize: CGSize(width: 200, height: 100))
        XCTAssertEqual(r.scaleX, 1, accuracy: 0.0001)
        XCTAssertEqual(r.scaleY, 1, accuracy: 0.0001)
        XCTAssertEqual(r.translateX, 50, accuracy: 0.0001)
        XCTAssertEqual(r.translateY, 0, accuracy: 0.0001)
    }

    func testSliceCropsInWideContainer() {
        let par = SVGPreserveAspectRatio.get(string: "xMidYMid slice")
        let r = par.resolve(viewBox: CGRect(x: 0, y: 0, width: 100, height: 100),
                            containerSize: CGSize(width: 200, height: 100))
        XCTAssertEqual(r.scaleX, 2, accuracy: 0.0001)
        XCTAssertEqual(r.scaleY, 2, accuracy: 0.0001)
        XCTAssertEqual(r.translateX, 0, accuracy: 0.0001)
        XCTAssertEqual(r.translateY, -50, accuracy: 0.0001)
    }

    func testNoneStretches() {
        let par = SVGPreserveAspectRatio.get(string: "none")
        let r = par.resolve(viewBox: CGRect(x: 0, y: 0, width: 100, height: 100),
                            containerSize: CGSize(width: 200, height: 100))
        XCTAssertEqual(r.scaleX, 2, accuracy: 0.0001)
        XCTAssertEqual(r.scaleY, 1, accuracy: 0.0001)
        XCTAssertEqual(r.translateX, 0, accuracy: 0.0001)
        XCTAssertEqual(r.translateY, 0, accuracy: 0.0001)
    }

    func testXMinYMinMeetAlignsTopLeft() {
        let par = SVGPreserveAspectRatio.get(string: "xMinYMin meet")
        let r = par.resolve(viewBox: CGRect(x: 0, y: 0, width: 100, height: 100),
                            containerSize: CGSize(width: 200, height: 100))
        XCTAssertEqual(r.translateX, 0, accuracy: 0.0001)
        XCTAssertEqual(r.translateY, 0, accuracy: 0.0001)
    }

    func testXMaxYMaxMeetAlignsBottomRight() {
        let par = SVGPreserveAspectRatio.get(string: "xMaxYMax meet")
        let r = par.resolve(viewBox: CGRect(x: 0, y: 0, width: 100, height: 100),
                            containerSize: CGSize(width: 200, height: 100))
        XCTAssertEqual(r.translateX, 100, accuracy: 0.0001)
        XCTAssertEqual(r.translateY, 0, accuracy: 0.0001)
    }

    // MARK: SVGOptions integration

    func testOptionsParsesPreserveAspectRatio() throws {
        let options = try SVGOptions(attributeDict: [
            "viewBox": "0 0 100 100",
            "width": "100",
            "height": "100",
            "preserveAspectRatio": "xMaxYMax slice"
        ])
        XCTAssertEqual(options.preserveAspectRatio.align, .xMaxYMax)
        XCTAssertEqual(options.preserveAspectRatio.meetOrSlice, .slice)
    }

    func testOptionsDefaultsPreserveAspectRatio() throws {
        let options = try SVGOptions(attributeDict: [
            "viewBox": "0 0 100 100",
            "width": "100",
            "height": "100"
        ])
        XCTAssertEqual(options.preserveAspectRatio.align, .xMidYMid)
        XCTAssertEqual(options.preserveAspectRatio.meetOrSlice, .meet)
    }

    // MARK: SVGView layout fit

    func testLayoutCentersSquareViewBoxInTallContainer() throws {
        // A square viewBox in a tall container must be centered vertically, not
        // pushed off-screen by a scale-multiplied centering translation.
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
            <rect width="24" height="24" fill="#000"/>
        </svg>
        """
        let view = SVGView()
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        view.parser = parser
        view.shapeLayer = try parser.getLayer(overrideElements: nil)
        view.frame = CGRect(x: 0, y: 0, width: 240, height: 480)

        view.layoutSubviews()

        let affine = CATransform3DGetAffineTransform(try XCTUnwrap(view.shapeLayer).transform)

        // scale = 10; 240x240 content centered vertically => viewBox origin at (0, 120).
        let origin = CGPoint(x: 0, y: 0).applying(affine)
        XCTAssertEqual(origin.x, 0, accuracy: 0.001)
        XCTAssertEqual(origin.y, 120, accuracy: 0.001)

        // Opposite corner (24, 24) => (240, 360).
        let corner = CGPoint(x: 24, y: 24).applying(affine)
        XCTAssertEqual(corner.x, 240, accuracy: 0.001)
        XCTAssertEqual(corner.y, 360, accuracy: 0.001)
    }
}
