import XCTest
@testable import SVGRenderKit

final class SVGRendererTests: XCTestCase {

    private let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><rect width="10" height="10" fill="#ff0000"/></svg>
    """

    private func pixel(_ image: UIImage, x: Int, y: Int) -> [UInt8] {
        let cg = image.cgImage!
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: -x, y: -(cg.height - 1 - y), width: cg.width, height: cg.height))
        return px
    }

    func testPNGAtExplicitSizeAndScale() async throws {
        let data = try await SVGRenderer.render(.string(svg), size: CGSize(width: 20, height: 20), scale: 2)
        let image = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(image.cgImage?.width, 40)
        XCTAssertEqual(pixel(image, x: 20, y: 20), [255, 0, 0, 255])
    }

    func testDefaultsToDocumentSize() async throws {
        let data = try await SVGRenderer.render(.data(Data(svg.utf8)))
        let image = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(image.cgImage?.width, 10)
        XCTAssertEqual(image.cgImage?.height, 10)
    }

    func testPNGIsTransparentOutsideArtworkAndBackgroundFills() async throws {
        let wide = CGSize(width: 40, height: 10)
        let plain = UIImage(data: try await SVGRenderer.render(.string(svg), size: wide))!
        XCTAssertEqual(pixel(plain, x: 1, y: 5)[3], 0)
        let filled = UIImage(data: try await SVGRenderer.render(.string(svg), size: wide, background: .blue))!
        XCTAssertEqual(pixel(filled, x: 1, y: 5), [0, 0, 255, 255])
    }

    func testJPEGHasWhiteBackgroundByDefault() async throws {
        let data = try await SVGRenderer.render(.string(svg), size: CGSize(width: 40, height: 10), format: .jpeg())
        XCTAssertEqual(Array(data.prefix(2)), [0xFF, 0xD8])
        let px = pixel(UIImage(data: data)!, x: 1, y: 5)
        XCTAssertTrue(px.prefix(3).allSatisfy { $0 > 240 })
    }

    func testPDFData() async throws {
        let data = try await SVGRenderer.render(.string(svg), format: .pdf)
        XCTAssertEqual(String(decoding: data.prefix(5), as: UTF8.self), "%PDF-")
    }

    func testCallbackVariantAndURLSource() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".svg")
        try svg.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let done = expectation(description: "completion")
        SVGRenderer.render(.url(url)) { result in
            XCTAssertNotNil(try? result.get())
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
    }

    func testInvalidInputThrows() async {
        do {
            _ = try await SVGRenderer.render(.string("not svg"))
            XCTFail("expected error")
        } catch {}
        do {
            _ = try await SVGRenderer.render(.string(svg), size: .zero)
            XCTFail("expected error")
        } catch {}
    }
}
