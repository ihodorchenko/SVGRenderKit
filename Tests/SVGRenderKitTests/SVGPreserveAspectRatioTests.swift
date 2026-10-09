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
}
