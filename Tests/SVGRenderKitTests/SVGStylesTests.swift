import XCTest
@testable import SVGRenderKit

final class SVGStylesTests: XCTestCase {

    func testSetFontFamilyStoresFontFamilyAndNotClipPath() {
        let style = SVGSourceStyleElement()
        style.setFontFamily(str: "Helvetica, Arial")

        XCTAssertEqual(style.fontFamily, "Helvetica, Arial")
        XCTAssertNil(style.clipPath)
    }
}
