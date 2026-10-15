import XCTest
import UIKit
@testable import SVGRenderKit

final class SVGImageTests: XCTestCase {

    private func makeBase64PNG() -> String {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
        let image = renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        return image.pngData()!.base64EncodedString()
    }

    private func findContentLayer(in layer: CALayer) -> CALayer? {
        if layer.contents != nil { return layer }
        for sublayer in layer.sublayers ?? [] {
            if let found = findContentLayer(in: sublayer) { return found }
        }
        return nil
    }

    func testDecodeBase64DataURI() {
        let image = SVGImage.decode(dataURI: "data:image/png;base64,\(makeBase64PNG())")
        XCTAssertNotNil(image)
    }

    func testDecodeRejectsNonDataURI() {
        XCTAssertNil(SVGImage.decode(dataURI: "https://example.com/image.png"))
    }

    private func wrappedBase64(_ base64: String, width: Int = 16) -> String {
        var lines: [String] = []
        var index = base64.startIndex
        while index < base64.endIndex {
            let end = base64.index(index, offsetBy: width, limitedBy: base64.endIndex) ?? base64.endIndex
            lines.append(String(base64[index..<end]))
            index = end
        }
        return lines.joined(separator: "\n")
    }

    func testDecodeBase64DataURIWithLineBreaks() {
        // Some generators wrap the base64 payload across lines; the decoder must ignore them (B99).
        let wrapped = wrappedBase64(makeBase64PNG())
        XCTAssertTrue(wrapped.contains("\n"))
        XCTAssertNotNil(SVGImage.decode(dataURI: "data:image/png;base64,\(wrapped)"))
    }

    func testImageRendersContentsWithWrappedBase64() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <image x="10" y="10" width="40" height="40" href="data:image/png;base64,\(wrappedBase64(makeBase64PNG()))"/>
        </svg>
        """
        let layer = try SVGParser(svgString: svg, parsedRoot: nil).getLayer(overrideElements: nil)
        let imageLayer = try XCTUnwrap(findContentLayer(in: layer))
        XCTAssertNotNil(imageLayer.contents)
    }

    func testImageRendersContentsAtResolvedFrame() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <image x="10" y="10" width="40" height="40" href="data:image/png;base64,\(makeBase64PNG())"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let imageLayer = try XCTUnwrap(findContentLayer(in: layer))
        XCTAssertNotNil(imageLayer.contents)
        XCTAssertEqual(imageLayer.frame.width, 40, accuracy: 0.001)
        XCTAssertEqual(imageLayer.frame.height, 40, accuracy: 0.001)
    }

    func testExternalHrefDegradesGracefully() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <image x="10" y="10" width="40" height="40" href="https://example.com/image.png"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        _ = try parser.getLayer(overrideElements: nil) // must not throw
    }
}
