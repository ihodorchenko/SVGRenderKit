import XCTest
import UIKit
@testable import SVGRenderKit

/// A `userSpaceOnUse` gradient must paint the whole element, wherever the element is.
///
/// The gradient's raster window used to be the `viewBox` alone. The window lives in the
/// element's own coordinate space, so an ancestor `transform` that moves the element (a wave
/// group scrolling across a logo, for example) maps part of the element outside it — that part
/// stayed unpainted and the layer underneath showed through. The window must cover the
/// element's own bounds: the gradient only paints through the element's silhouette anyway, so a
/// larger window never paints anything extra.
@MainActor
final class SVGUserSpaceGradientBoundsTests: XCTestCase {

    private func alpha(of image: UIImage, x: Int, y: Int) -> Int {
        guard let cgImage = image.cgImage else { return -1 }
        let width = cgImage.width, height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return -1 }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        let index = (y * width + x) * 4 + 3
        return index < pixels.count ? Int(pixels[index]) : -1
    }

    func testGradientPaintsAnElementShiftedOutsideTheViewBox() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
          <defs>
            <linearGradient id="g" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="0" y2="100">
              <stop offset="0" stop-color="#ff0000"/>
              <stop offset="1" stop-color="#0000ff"/>
            </linearGradient>
          </defs>
          <g transform="translate(-80 0)">
            <rect x="-200" y="0" width="400" height="100" fill="url(#g)"/>
          </g>
        </svg>
        """
        let image = try KitRenderer.render(svg, size: CGSize(width: 100, height: 100))
        // The rect covers local −200…200 and the group shifts it by −80, so all three probes
        // sit on the rect. With the viewBox-only window the painting stopped at local x = 100,
        // i.e. at x = 20 on screen, leaving everything to the right transparent.
        XCTAssertGreaterThan(alpha(of: image, x: 10, y: 50), 200)
        XCTAssertGreaterThan(alpha(of: image, x: 60, y: 50), 200, "the gradient stopped inside the element")
        XCTAssertGreaterThan(alpha(of: image, x: 90, y: 50), 200, "the gradient stopped at the viewBox edge")
    }

    func testGradientWindowCoversTheElementBounds() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
          <defs>
            <linearGradient id="g" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="0" y2="100">
              <stop offset="0" stop-color="#ff0000"/>
              <stop offset="1" stop-color="#0000ff"/>
            </linearGradient>
          </defs>
          <g transform="translate(-80 0)">
            <rect x="-200" y="0" width="400" height="100" fill="url(#g)"/>
          </g>
        </svg>
        """
        let layer = try SVGParser(svgString: svg, parsedRoot: nil).getLayer(overrideElements: nil)
        func firstGradient(_ layer: CALayer) -> CAGradientLayer? {
            if let gradient = layer as? CAGradientLayer { return gradient }
            for sublayer in layer.sublayers ?? [] {
                if let found = firstGradient(sublayer) { return found }
            }
            return nil
        }
        let gradient = try XCTUnwrap(firstGradient(layer))
        // The rect's own bounds in its user space: x −200…200, y 0…100.
        XCTAssertEqual(gradient.frame.minX, -200, accuracy: 0.001)
        XCTAssertEqual(gradient.frame.width, 400, accuracy: 0.001)
    }
}
