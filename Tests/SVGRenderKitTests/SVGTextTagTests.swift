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

    private func textLayerCount(_ svg: String) throws -> Int {
        func count(in layer: CALayer) -> Int {
            var n = layer is CATextLayer ? 1 : 0
            for sublayer in layer.sublayers ?? [] { n += count(in: sublayer) }
            return n
        }
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        return count(in: try parser.getLayer(overrideElements: nil))
    }

    // MARK: B106 — text styling

    func testDefaultFontSizeIs16() throws {
        let font = try renderedFont("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\"><text>Hi</text></svg>")
        XCTAssertEqual(font.pointSize, 16)
    }

    func testQuotedFontFamilyIsStripped() throws {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\"><text font-family=\"'Helvetica'\">Hi</text></svg>"
        let font = try renderedFont(svg)
        XCTAssertEqual(font.familyName, "Helvetica")
    }

    func testWeightAppliesToNamedFamily() throws {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\"><text font-family=\"Helvetica\" font-weight=\"bold\">Hi</text></svg>"
        let font = try renderedFont(svg)
        XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.traitBold))
    }

    func testDisplayNoneTextIsNotRendered() throws {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\"><text display=\"none\">Hi</text></svg>"
        XCTAssertEqual(try textLayerCount(svg), 0)
    }

    func testVisibilityHiddenTextIsNotRendered() throws {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\"><text visibility=\"hidden\">Hi</text></svg>"
        XCTAssertEqual(try textLayerCount(svg), 0)
    }

    func testWhitespaceIsCollapsed() throws {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\"><text>  Hello   World  </text></svg>"
        XCTAssertEqual(try renderedText(svg), "Hello World")
    }

    func testXmlSpacePreserveKeepsWhitespace() throws {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\"><text xml:space=\"preserve\"> A  B </text></svg>"
        XCTAssertEqual(try renderedText(svg), " A  B ")
    }

    // B112: the text bitmap must follow the render scale, not a global screen scale.
    func testTextContentsScaleUsesRenderScale() throws {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 10 10\"><text x=\"1\" y=\"5\">Hi</text></svg>"
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        parser.root.getSvgOptions().renderScale = 3
        let layer = try parser.getLayer(overrideElements: nil)
        let textLayer = try XCTUnwrap(findTextLayer(in: layer))
        XCTAssertEqual(textLayer.contentsScale, 3, accuracy: 0.001)
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
