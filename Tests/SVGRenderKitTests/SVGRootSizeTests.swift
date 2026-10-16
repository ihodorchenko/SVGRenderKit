import XCTest
import UIKit
@testable import SVGRenderKit

/// B101 — sizing of the root `<svg>` element.
///
/// The parser must never throw on a partial or missing `viewBox`/`width`/`height`
/// combination. Instead it derives the viewport the way a browser does: a lone
/// dimension follows the `viewBox` aspect ratio, a percentage is relative to the
/// `viewBox`, and an unresolvable viewport degrades to a square instead of failing
/// the whole document.
final class SVGRootSizeTests: XCTestCase {

    private func assertLength(_ length: SVGLength, is expected: SVGLength,
                             file: StaticString = #filePath, line: UInt = #line) {
        switch (length, expected) {
        case (.px(let a), .px(let b)):
            XCTAssertEqual(a, b, accuracy: 1e-6, file: file, line: line)
        case (.percent(let a), .percent(let b)):
            XCTAssertEqual(a, b, accuracy: 1e-6, file: file, line: line)
        default:
            XCTFail("length \(length) does not match \(expected)", file: file, line: line)
        }
    }

    // MARK: - viewBox present, only one dimension given

    func testWidthOnlyWithViewBoxFollowsAspectRatio() throws {
        let options = try SVGOptions(attributeDict: [
            "viewBox": "0 0 100 50",
            "width": "200"
        ])
        XCTAssertEqual(options.size.width, 200, accuracy: 1e-6)
        XCTAssertEqual(options.size.height, 100, accuracy: 1e-6)
        assertLength(options.width, is: .px(value: 200))
        assertLength(options.height, is: .px(value: 100))
    }

    func testHeightOnlyWithViewBoxFollowsAspectRatio() throws {
        let options = try SVGOptions(attributeDict: [
            "viewBox": "0 0 100 50",
            "height": "100"
        ])
        XCTAssertEqual(options.size.width, 200, accuracy: 1e-6)
        XCTAssertEqual(options.size.height, 100, accuracy: 1e-6)
        assertLength(options.width, is: .px(value: 200))
        assertLength(options.height, is: .px(value: 100))
    }

    func testPercentWidthOnlyWithViewBoxIsRelativeToViewBox() throws {
        let options = try SVGOptions(attributeDict: [
            "viewBox": "0 0 100 200",
            "width": "50%"
        ])
        XCTAssertEqual(options.size.width, 50, accuracy: 1e-6)
        XCTAssertEqual(options.size.height, 100, accuracy: 1e-6)
        assertLength(options.width, is: .percent(value: 0.5))
    }

    // MARK: - viewBox present, both / neither dimension given

    func testBothPercentWithViewBox() throws {
        let options = try SVGOptions(attributeDict: [
            "viewBox": "0 0 100 200",
            "width": "50%",
            "height": "25%"
        ])
        XCTAssertEqual(options.size.width, 50, accuracy: 1e-6)
        XCTAssertEqual(options.size.height, 50, accuracy: 1e-6)
    }

    func testOnlyViewBoxUsesViewBoxSize() throws {
        let options = try SVGOptions(attributeDict: ["viewBox": "0 0 100 50"])
        XCTAssertEqual(options.size.width, 100, accuracy: 1e-6)
        XCTAssertEqual(options.size.height, 50, accuracy: 1e-6)
        XCTAssertEqual(options.viewBox, CGRect(x: 0, y: 0, width: 100, height: 50))
    }

    // MARK: - no viewBox

    func testWidthOnlyWithoutViewBoxDegradesToSquare() throws {
        let options = try SVGOptions(attributeDict: ["width": "120"])
        XCTAssertEqual(options.size.width, 120, accuracy: 1e-6)
        XCTAssertEqual(options.size.height, 120, accuracy: 1e-6)
        XCTAssertEqual(options.viewBox, CGRect(x: 0, y: 0, width: 120, height: 120))
    }

    func testHeightOnlyWithoutViewBoxDegradesToSquare() throws {
        let options = try SVGOptions(attributeDict: ["height": "80"])
        XCTAssertEqual(options.size.width, 80, accuracy: 1e-6)
        XCTAssertEqual(options.size.height, 80, accuracy: 1e-6)
    }

    func testBothPixelsWithoutViewBox() throws {
        let options = try SVGOptions(attributeDict: ["width": "120", "height": "40"])
        XCTAssertEqual(options.size.width, 120, accuracy: 1e-6)
        XCTAssertEqual(options.size.height, 40, accuracy: 1e-6)
        XCTAssertEqual(options.viewBox, CGRect(x: 0, y: 0, width: 120, height: 40))
    }

    func testPercentWithoutViewBoxDoesNotThrow() throws {
        let options = try SVGOptions(attributeDict: ["width": "50%", "height": "50%"])
        XCTAssertGreaterThan(options.size.width, 0)
        XCTAssertGreaterThan(options.size.height, 0)
    }

    func testNoDimensionsAtAllDoesNotThrow() throws {
        let options = try SVGOptions(attributeDict: [:])
        XCTAssertEqual(options.size.width, 100, accuracy: 1e-6)
        XCTAssertEqual(options.size.height, 100, accuracy: 1e-6)
        XCTAssertEqual(options.viewBox, CGRect(x: 0, y: 0, width: 100, height: 100))
    }

    // MARK: - end to end through the parser

    func testParserRendersWidthOnlySvg() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="48">
            <rect width="10" height="10" fill="#000000"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let options = try XCTUnwrap(parser.root).getSvgOptions()
        XCTAssertEqual(options.size.width, 48, accuracy: 1e-6)
        XCTAssertEqual(options.size.height, 48, accuracy: 1e-6)

        let layer = try parser.getLayer(overrideElements: nil)
        XCTAssertFalse(layer.sublayers?.isEmpty ?? true)
    }

    func testParserRendersHeightOnlySvg() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" height="60">
            <circle cx="10" cy="10" r="5" fill="#000000"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let options = try XCTUnwrap(parser.root).getSvgOptions()
        XCTAssertEqual(options.size.width, 60, accuracy: 1e-6)
        XCTAssertEqual(options.size.height, 60, accuracy: 1e-6)
    }

    func testParserRendersSvgWithoutDimensions() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg">
            <rect width="10" height="10" fill="#000000"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let options = try XCTUnwrap(parser.root).getSvgOptions()
        XCTAssertGreaterThan(options.size.width, 0)
        XCTAssertGreaterThan(options.size.height, 0)
    }
}

/// B128 — relative units and `auto` on the root fall back to the `viewBox`.
final class SVGRootRelativeUnitTests: XCTestCase {

    func testEmSizedRootFallsBackToViewBox() throws {
        // Iconify export: `width="1em" height="1em"`.
        let options = try SVGOptions(attributeDict: ["width": "1em", "height": "1em", "viewBox": "0 0 24 24"])
        XCTAssertEqual(options.size, CGSize(width: 24, height: 24))
    }

    func testAutoSizedRootFallsBackToViewBox() throws {
        let options = try SVGOptions(attributeDict: ["width": "auto", "height": "auto", "viewBox": "0 0 40 20"])
        XCTAssertEqual(options.size, CGSize(width: 40, height: 20))
    }

    func testRelativeWidthWithAbsoluteHeightFollowsViewBoxAspect() throws {
        let options = try SVGOptions(attributeDict: ["width": "2rem", "height": "50", "viewBox": "0 0 100 50"])
        XCTAssertEqual(options.size, CGSize(width: 100, height: 50))
    }

    func testEmWithoutViewBoxDoesNotCollapseToZero() throws {
        let options = try SVGOptions(attributeDict: ["width": "1em", "height": "1em"])
        XCTAssertGreaterThan(options.size.width, 0)
        XCTAssertGreaterThan(options.size.height, 0)
    }

    func testRendererRendersEmSizedIcon() async throws {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1em\" height=\"1em\" viewBox=\"0 0 24 24\"><rect width=\"24\" height=\"24\" fill=\"#f00\"/></svg>"
        let data = try await SVGRenderer.render(.string(svg), format: .png)
        let image = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(image.size.width * image.scale, 24, accuracy: 0.5)
    }
}
