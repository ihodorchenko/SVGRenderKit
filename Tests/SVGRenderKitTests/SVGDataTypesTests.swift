import XCTest
@testable import SVGRenderKit

final class SVGFuncIRITests: XCTestCase {

    func testLocalKeyFromContent() throws {
        let iri = try SVGFuncIRI.get(content: "#gradient")
        guard case .local(let key) = iri else {
            return XCTFail("expected .local, got \(iri)")
        }
        XCTAssertEqual(key, "#gradient")
    }

    func testClassSelectorFromContent() throws {
        let iri = try SVGFuncIRI.get(content: ".my-class")
        guard case .local(let key) = iri else {
            return XCTFail("expected .local, got \(iri)")
        }
        XCTAssertEqual(key, ".my-class")
    }

    func testFullURLString() throws {
        let iri = try SVGFuncIRI.get(fullStr: "url(#grad)")
        guard case .local(let key) = iri else {
            return XCTFail("expected .local, got \(iri)")
        }
        XCTAssertEqual(key, "#grad")
    }

    func testNonURLStringThrows() {
        XCTAssertThrowsError(try SVGFuncIRI.get(fullStr: "not-a-url"))
    }

    func testExternalContentThrows() {
        XCTAssertThrowsError(try SVGFuncIRI.get(content: "https://example.com/image.png"))
    }
}

final class SVGPaintTests: XCTestCase {

    func testNone() throws {
        let paint = try SVGPaint.get(string: "none")
        guard case .none = paint else {
            return XCTFail("expected .none, got \(paint)")
        }
    }

    func testHexColor() throws {
        let paint = try SVGPaint.get(string: "#ff0000")
        guard case .color(let color) = paint else {
            return XCTFail("expected .color, got \(paint)")
        }
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        XCTAssertEqual(red, 1)
        XCTAssertEqual(green, 0)
        XCTAssertEqual(blue, 0)
        XCTAssertEqual(alpha, 1)
    }

    func testNamedColor() throws {
        let paint = try SVGPaint.get(string: "red")
        guard case .color = paint else {
            return XCTFail("expected .color, got \(paint)")
        }
    }

    func testFuncIRI() throws {
        let paint = try SVGPaint.get(string: "url(#grad)")
        guard case .funcIRI(let iri) = paint else {
            return XCTFail("expected .funcIRI, got \(paint)")
        }
        guard case .local(let key) = iri else {
            return XCTFail("expected .local, got \(iri)")
        }
        XCTAssertEqual(key, "#grad")
    }

    func testUnknownThrows() {
        XCTAssertThrowsError(try SVGPaint.get(string: "totally-unknown"))
    }
}

final class SVGLengthTests: XCTestCase {

    func testPixelsWithSuffix() throws {
        let length = try SVGLength.get(string: "10px")
        guard case .px(let value) = length else {
            return XCTFail("expected .px, got \(length)")
        }
        XCTAssertEqual(value, 10)
    }

    func testPercent() throws {
        let length = try SVGLength.get(string: "50%")
        guard case .percent(let value) = length else {
            return XCTFail("expected .percent, got \(length)")
        }
        XCTAssertEqual(value, 0.5)
    }

    func testPlainNumberIsPixels() throws {
        let length = try SVGLength.get(string: "10")
        guard case .px(let value) = length else {
            return XCTFail("expected .px, got \(length)")
        }
        XCTAssertEqual(value, 10)
    }

    func testInvalidThrows() {
        XCTAssertThrowsError(try SVGLength.get(string: "abc"))
    }
}

final class SVGErrorTests: XCTestCase {

    func testDescriptions() {
        XCTAssertEqual(SVGError.parseError(text: "boom").description, "ParseError: boom")
        XCTAssertEqual(SVGError.unexpectedError(text: "boom").description, "UnexpectedError: boom")
        XCTAssertEqual(SVGError.content(text: "boom").description, "ContentError: boom")
    }

    func testLocalizedDescriptionMatchesDescription() {
        let error = SVGError.parseError(text: "boom")
        XCTAssertEqual(error.localizedDescription, error.description)
        XCTAssertEqual(error.errorDescription, error.description)
    }
}
