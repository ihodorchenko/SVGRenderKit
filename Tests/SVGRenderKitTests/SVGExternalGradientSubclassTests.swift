// Deliberately NO `@testable`: this file only sees the module's public API, so it proves that a
// third-party `SVGBaseGradient` subclass compiles and works outside the module (B137).
import XCTest
import UIKit
import SVGRenderKit

private final class ExternalGradient: SVGBaseGradient {
    var requestedPaths = 0

    override func getGradientLayer(maskLayer: CALayer, path: UIBezierPath, viewBox: CGRect, currentColor: UIColor = .black) -> CALayer? {
        requestedPaths += 1
        let layer = CAGradientLayer()
        layer.frame = path.bounds
        layer.colors = stops.map { $0.resolvedColor(currentColor: currentColor).cgColor }
        layer.locations = stops.map { NSNumber(value: $0.offset) }
        return layer
    }
}

final class SVGExternalGradientSubclassTests: XCTestCase {
    func testExternalSubclassUsesPublicInitAndOverride() throws {
        let svg = SWXMLHash.parse("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 10 10\"/>")
        let root = try SVGRoot(xmlSvgElement: XCTUnwrap(svg["svg"].element))
        let gradientXML = SWXMLHash.parse("""
        <linearGradient id="g" gradientUnits="userSpaceOnUse" spreadMethod="reflect">
          <stop offset="0" stop-color="#ff0000"/><stop offset="1" stop-color="#0000ff"/>
        </linearGradient>
        """)
        let element = try XCTUnwrap(gradientXML["linearGradient"].element)
        let gradient = try ExternalGradient(xmlElement: element, parent: root)

        XCTAssertEqual(gradient.gradientUnits, .userSpaceOnUse)
        XCTAssertEqual(gradient.spreadMethod, .reflect)
        XCTAssertNil(gradient.transform)
        XCTAssertFalse(gradient.isEnable())

        let path = UIBezierPath(rect: CGRect(x: 0, y: 0, width: 4, height: 4))
        let layer = gradient.getGradientLayer(maskLayer: CALayer(), path: path, viewBox: CGRect(x: 0, y: 0, width: 10, height: 10))
        XCTAssertEqual(gradient.requestedPaths, 1)
        XCTAssertTrue(layer is CAGradientLayer)
    }
}
