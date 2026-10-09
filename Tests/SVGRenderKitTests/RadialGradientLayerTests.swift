import XCTest
@testable import SVGRenderKit

final class RadialGradientLayerTests: XCTestCase {

    func testDrawDoesNotMutateLocations() {
        let layer = RadialGradientLayer()
        layer.colors = [UIColor.red.cgColor, UIColor.blue.cgColor]
        layer.locations = [0, 1]
        layer.frame = CGRect(x: 0, y: 0, width: 10, height: 10)

        let context = CGContext(
            data: nil,
            width: 10,
            height: 10,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!

        layer.draw(in: context)

        XCTAssertEqual(layer.locations.count, 2)
        XCTAssertEqual(layer.locations, [0, 1])
    }
}
