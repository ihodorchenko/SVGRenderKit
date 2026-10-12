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

    // MARK: Concurrent rasterization

    /// Layer building is serialized but rasterization runs concurrently; concurrent renders of different
    /// sizes and scales (sharing one cached document and its pattern/gradient state) must each match what
    /// a lone render produces.
    func testConcurrentRendersMatchSequentialRenders() async throws {
        let doc = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 40">
          <defs>
            <linearGradient id="g"><stop offset="0" stop-color="#f00"/><stop offset="1" stop-color="#00f"/></linearGradient>
            <pattern id="p" width="8" height="8" patternUnits="userSpaceOnUse"><rect width="4" height="4" fill="#0a0"/></pattern>
          </defs>
          <rect width="40" height="20" fill="url(#g)"/>
          <rect y="20" width="40" height="20" fill="url(#p)"/>
        </svg>
        """
        let variants: [(CGSize, CGFloat)] = [
            (CGSize(width: 40, height: 40), 1), (CGSize(width: 80, height: 80), 1),
            (CGSize(width: 40, height: 40), 2), (CGSize(width: 120, height: 60), 1),
        ]
        var expected: [Data] = []
        for (size, scale) in variants {
            expected.append(try await SVGRenderer.render(.string(doc, name: "concurrent"), size: size, scale: scale))
        }

        let results = try await withThrowingTaskGroup(of: (Int, Data).self) { group -> [Int: Data] in
            for round in 0..<6 {
                for (index, variant) in variants.enumerated() {
                    group.addTask {
                        let data = try await SVGRenderer.render(
                            .string(doc, name: "concurrent"), size: variant.0, scale: variant.1)
                        return (round * variants.count + index, data)
                    }
                }
            }
            var all: [Int: Data] = [:]
            for try await (key, data) in group { all[key] = data }
            return all
        }

        XCTAssertEqual(results.count, 6 * variants.count)
        for (key, data) in results {
            XCTAssertEqual(data, expected[key % variants.count], "render \(key) differs from the sequential result")
        }
    }
}
