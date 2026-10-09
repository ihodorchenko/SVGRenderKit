import XCTest
@testable import SVGRenderKit

final class SVGTextTagTests: XCTestCase {

    private func findTextLayer(in layer: CALayer) -> CATextLayer? {
        if let textLayer = layer as? CATextLayer {
            return textLayer
        }
        for sublayer in layer.sublayers ?? [] {
            if let found = findTextLayer(in: sublayer) {
                return found
            }
        }
        return nil
    }

    private func renderedText(_ svg: String) throws -> String? {
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let textLayer = try XCTUnwrap(findTextLayer(in: layer))
        if let attributed = textLayer.string as? NSAttributedString {
            return attributed.string
        }
        return textLayer.string as? String
    }

    func testTextRendersActualContent() throws {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\"><text x=\"10\" y=\"20\">Hello World</text></svg>"
        let text = try renderedText(svg)
        XCTAssertEqual(text, "Hello World")
    }

    func testTextRendersWithFillColor() throws {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\"><text x=\"10\" y=\"20\" fill=\"#ff0000\">Red</text></svg>"
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let textLayer = try XCTUnwrap(findTextLayer(in: layer))

        let attributed = try XCTUnwrap(textLayer.string as? NSAttributedString)
        let color = try XCTUnwrap(attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        XCTAssertEqual(red, 1, accuracy: 1e-6)
        XCTAssertEqual(green, 0, accuracy: 1e-6)
        XCTAssertEqual(blue, 0, accuracy: 1e-6)
    }

    private func renderedFont(_ svg: String) throws -> UIFont {
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let textLayer = try XCTUnwrap(findTextLayer(in: layer))
        let attributed = try XCTUnwrap(textLayer.string as? NSAttributedString)
        return try XCTUnwrap(attributed.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
    }

    func testFontSizeApplied() throws {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\"><text font-size=\"24\">Big</text></svg>"
        let font = try renderedFont(svg)
        XCTAssertEqual(font.pointSize, 24)
    }

    func testFontSizeWithPixelsApplied() throws {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\"><text font-size=\"30px\">Big</text></svg>"
        let font = try renderedFont(svg)
        XCTAssertEqual(font.pointSize, 30)
    }

    func testFontWeightBoldApplied() throws {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\"><text font-weight=\"bold\">Bold</text></svg>"
        let font = try renderedFont(svg)
        XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.traitBold))
    }

    func testFontFamilyApplied() throws {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\"><text font-family=\"Helvetica\" font-size=\"20\">Helvetica</text></svg>"
        let font = try renderedFont(svg)
        XCTAssertEqual(font.pointSize, 20)
        XCTAssertEqual(font.familyName, "Helvetica")
    }

    func testFontSizePercentApplied() throws {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\"><g font-size=\"20\"><text font-size=\"150%\">Big</text></g></svg>"
        let font = try renderedFont(svg)
        XCTAssertEqual(font.pointSize, 30, accuracy: 0.001)
    }

    func testFontSizeEmApplied() throws {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\"><g font-size=\"10\"><text font-size=\"2em\">Big</text></g></svg>"
        let font = try renderedFont(svg)
        XCTAssertEqual(font.pointSize, 20, accuracy: 0.001)
    }
}
