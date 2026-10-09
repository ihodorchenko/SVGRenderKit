import XCTest
@testable import SVGRenderKit

final class SVGColorsTests: XCTestCase {

    private func rgba(_ color: UIColor) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (red, green, blue, alpha)
    }

    private func assertColor(
        _ color: UIColor,
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        alpha: CGFloat,
        accuracy: CGFloat = 1e-6,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let c = rgba(color)
        XCTAssertEqual(c.red, red, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(c.green, green, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(c.blue, blue, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(c.alpha, alpha, accuracy: accuracy, file: file, line: line)
    }

    // MARK: - Hex

    func testHexSixDigits() {
        let color = SVGColors.getColor(hexString: "#ff0000")!
        assertColor(color, red: 1, green: 0, blue: 0, alpha: 1)
    }

    func testHexThreeDigits() {
        let color = SVGColors.getColor(hexString: "#0f0")!
        assertColor(color, red: 0, green: 1, blue: 0, alpha: 1)
    }

    func testHexFourDigits() {
        let color = SVGColors.getColor(hexString: "#f00f")!
        assertColor(color, red: 1, green: 0, blue: 0, alpha: 1)
    }

    func testHexEightDigits() {
        // 8-digit hex is parsed in AARRGGBB order.
        let color = SVGColors.getColor(hexString: "#8000ff00")!
        assertColor(color, red: 0, green: 1, blue: 0, alpha: 128.0 / 255.0)
    }

    func testHexWithoutLeadingHash() {
        let color = SVGColors.getColor(hexString: "00ff00")!
        assertColor(color, red: 0, green: 1, blue: 0, alpha: 1)
    }

    func testHexInvalidReturnsNil() {
        XCTAssertNil(SVGColors.getColor(hexString: "#zzzzzz"))
        XCTAssertNil(SVGColors.getColor(hexString: "#12345"))
    }

    // MARK: - rgb / rgba / argb

    func testRGBString() {
        let color = SVGColors.getColor(rgbString: "rgb(255, 0, 0)")!
        assertColor(color, red: 1, green: 0, blue: 0, alpha: 1)
    }

    func testRGBAString() {
        let color = SVGColors.getColor(rgbaString: "rgba(0, 255, 0, 0.5)")!
        assertColor(color, red: 0, green: 1, blue: 0, alpha: 0.5)
    }

    func testARGBString() {
        let color = SVGColors.getColor(argbString: "argb(0.5, 0, 0, 255)")!
        assertColor(color, red: 0, green: 0, blue: 1, alpha: 0.5)
    }

    func testRGBStringHandlesWhitespace() {
        let color = SVGColors.getColor(rgbString: "rgb( 255 , 0 , 0 )")!
        assertColor(color, red: 1, green: 0, blue: 0, alpha: 1)
    }

    // MARK: - Named colors

    func testNamedColors() {
        assertColor(SVGColors.getColor(string: "red"), red: 1, green: 0, blue: 0, alpha: 1)
        assertColor(SVGColors.getColor(string: "lime"), red: 0, green: 1, blue: 0, alpha: 1)
        assertColor(SVGColors.getColor(string: "blue"), red: 0, green: 0, blue: 1, alpha: 1)
        assertColor(SVGColors.getColor(string: "white"), red: 1, green: 1, blue: 1, alpha: 1)
        assertColor(SVGColors.getColor(string: "black"), red: 0, green: 0, blue: 0, alpha: 1)
    }

    // MARK: - getColor(string:)

    func testGetColorStringHex() {
        assertColor(SVGColors.getColor(string: "#00ff00"), red: 0, green: 1, blue: 0, alpha: 1)
    }

    func testGetColorStringRGB() {
        assertColor(SVGColors.getColor(string: "rgb(0,0,255)"), red: 0, green: 0, blue: 1, alpha: 1)
    }

    func testGetColorStringUnknownReturnsClear() {
        let color = SVGColors.getColor(string: "not-a-real-color")
        assertColor(color, red: 0, green: 0, blue: 0, alpha: 0)
    }

    // MARK: - Overrides

    func testColorStringOverride() {
        SVGColors.setOvverideColors(colors: ["brand" : "#00ff00"])
        assertColor(SVGColors.getColor(string: "brand"), red: 0, green: 1, blue: 0, alpha: 1)
        SVGColors.setOvverideColors(colors: [:])
    }

    func testUIColorOverride() {
        SVGColors.setOvverideUIColors(colors: ["brand" : UIColor(red: 1, green: 0, blue: 0, alpha: 1)])
        assertColor(SVGColors.getColor(string: "brand"), red: 1, green: 0, blue: 0, alpha: 1)
        SVGColors.setOvverideUIColors(colors: [:])
    }

    // MARK: - HTMLColors lookup table

    func testHTMLColorsContainsStandardNames() {
        XCTAssertEqual(HTMLColors.colors["red"], "#ff0000")
        XCTAssertEqual(HTMLColors.colors["white"], "#ffffff")
        XCTAssertEqual(HTMLColors.colors["lime"], "#00ff00")
    }
}
