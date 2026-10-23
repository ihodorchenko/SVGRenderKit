import XCTest
@testable import SVGRenderKit

/// Every numeric attribute of every supported element, fed non-finite, huge, tiny and negative
/// values. The library promises to degrade (skip + log) on untrusted input, never to trap: a crash
/// anywhere in parsing, layer building or drawing fails the whole run, and the `HOSTILE` line printed
/// before each case names the document that did it.
@MainActor
final class SVGHostileNumbersTests: XCTestCase {

    private let values = ["nan", "inf", "-inf", "1e308", "-1e308", "1e30", "-1", "0", "1e-320", "99999999999"]

    /// `$V` marks the hostile value; every entry is one document body.
    private var bodies: [String] {
        var result: [String] = []
        func vary(_ template: String, _ attributes: [String]) {
            for attribute in attributes { result.append(template.replacingOccurrences(of: "ATTR", with: attribute)) }
        }
        // Shapes.
        vary(##"<rect width="10" height="10" fill="red" ATTR="$V"/>"##, ["x", "y", "width", "height", "rx", "ry"])
        vary(##"<circle r="5" cx="5" cy="5" fill="red" ATTR="$V"/>"##, ["cx", "cy", "r"])
        vary(##"<ellipse rx="5" ry="3" cx="5" cy="5" fill="red" ATTR="$V"/>"##, ["cx", "cy", "rx", "ry"])
        vary(##"<line x1="0" y1="0" x2="9" y2="9" stroke="#000" ATTR="$V"/>"##, ["x1", "y1", "x2", "y2"])
        result.append(##"<polyline points="0,0 $V,$V 10,10" fill="none" stroke="#000"/>"##)
        result.append(##"<polygon points="0,0 $V,5 10,$V" fill="red"/>"##)
        for d in ["M0 0 L$V $V L5 5z", "M$V $V L5 5 L9 0z", "M0 0 H$V V$V z", "M0 0 C$V $V 1 1 5 5", "M0 0 S$V $V 5 5",
                  "M0 0 Q$V $V 5 5", "M0 0 T$V $V", "M0 0 A$V $V $V 1 1 $V $V", "M0 0 A5 5 0 1 1 $V $V", "M0 0 A$V 3 45 0 1 9 9",
                  "M0 0 L5 5 m$V $V l3 3"] {
            result.append(##"<path d="\##(d)" fill="red" stroke="#000"/>"##)
        }
        // Stroke / paint / opacity / transform presentation attributes.
        vary(##"<rect width="10" height="10" fill="red" stroke="#000" ATTR="$V"/>"##,
             ["stroke-width", "stroke-miterlimit", "stroke-dashoffset", "opacity", "fill-opacity", "stroke-opacity"])
        result.append(##"<rect width="10" height="10" fill="none" stroke="#000" stroke-dasharray="$V 2"/>"##)
        result.append(##"<rect width="10" height="10" fill="none" stroke="#000" stroke-dasharray="2 $V 1"/>"##)
        for transform in ["translate($V)", "translate($V $V)", "rotate($V)", "rotate(45 $V $V)", "scale($V)", "scale($V 2)", "skewX($V)", "skewY($V)", "matrix($V 0 0 1 0 0)", "matrix(1 0 0 1 $V $V)"] {
            result.append(##"<rect width="10" height="10" fill="red" transform="\##(transform)"/>"##)
        }
        // Root and structure.
        vary(##"<svg xmlns="http://www.w3.org/2000/svg" ATTR="$V" viewBox="0 0 10 10"><rect width="10" height="10"/></svg>"##, ["width", "height"])
        result.append(##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="$V $V $V $V"><rect width="10" height="10"/></svg>"##)
        result.append(##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $V $V" width="10" height="10"><rect width="10" height="10"/></svg>"##)
        vary(##"<defs><rect id="r" width="5" height="5"/></defs><use href="#r" ATTR="$V"/>"##, ["x", "y", "width", "height"])
        vary(##"<defs><symbol id="s" viewBox="0 0 5 5"><rect width="5" height="5"/></symbol></defs><use href="#s" width="10" height="10" ATTR="$V"/>"##, ["x", "y", "width", "height"])
        // Gradients.
        vary(##"<defs><linearGradient id="g" ATTR="$V"><stop offset="0" stop-color="#f00"/><stop offset="1" stop-color="#00f"/></linearGradient></defs><rect width="10" height="10" fill="url(#g)"/>"##,
             ["x1", "y1", "x2", "y2"])
        vary(##"<defs><linearGradient id="g" gradientUnits="userSpaceOnUse" ATTR="$V"><stop offset="0" stop-color="#f00"/><stop offset="1" stop-color="#00f"/></linearGradient></defs><rect width="10" height="10" fill="url(#g)"/>"##,
             ["x1", "y1", "x2", "y2"])
        vary(##"<defs><radialGradient id="g" ATTR="$V"><stop offset="0" stop-color="#f00"/><stop offset="1" stop-color="#00f"/></radialGradient></defs><rect width="10" height="10" fill="url(#g)"/>"##,
             ["cx", "cy", "r", "fx", "fy", "fr"])
        vary(##"<defs><radialGradient id="g" gradientUnits="userSpaceOnUse" ATTR="$V"><stop offset="0" stop-color="#f00"/><stop offset="1" stop-color="#00f"/></radialGradient></defs><rect width="10" height="10" fill="url(#g)"/>"##,
             ["cx", "cy", "r", "fx", "fy", "fr"])
        result.append(##"<defs><linearGradient id="g"><stop offset="$V" stop-color="#f00"/><stop offset="1" stop-color="#00f" stop-opacity="$V"/></linearGradient></defs><rect width="10" height="10" fill="url(#g)"/>"##)
        result.append(##"<defs><linearGradient id="g" gradientTransform="rotate($V) scale($V)"><stop offset="0" stop-color="#f00"/><stop offset="1" stop-color="#00f"/></linearGradient></defs><rect width="10" height="10" fill="url(#g)"/>"##)
        result.append(##"<defs><linearGradient id="g" spreadMethod="reflect"><stop offset="0" stop-color="#f00"/><stop offset="1" stop-color="#00f"/></linearGradient></defs><rect width="10" height="10" stroke-width="$V" stroke="url(#g)" fill="none"/>"##)
        // Patterns, masks, clips, markers, filters.
        vary(##"<defs><pattern id="p" width="4" height="4" patternUnits="userSpaceOnUse" ATTR="$V"><rect width="2" height="2"/></pattern></defs><rect width="10" height="10" fill="url(#p)"/>"##,
             ["x", "y", "width", "height", "patternTransform", "viewBox"])
        vary(##"<defs><pattern id="p" width="0.5" height="0.5" ATTR="$V"><rect width="1" height="1"/></pattern></defs><rect width="10" height="10" fill="url(#p)"/>"##,
             ["x", "y", "width", "height"])
        vary(##"<defs><mask id="m" ATTR="$V"><rect width="10" height="10" fill="#fff"/></mask></defs><rect width="10" height="10" mask="url(#m)"/>"##,
             ["x", "y", "width", "height"])
        vary(##"<defs><mask id="m" maskUnits="userSpaceOnUse" ATTR="$V"><rect width="10" height="10" fill="#fff"/></mask></defs><rect width="10" height="10" mask="url(#m)"/>"##,
             ["x", "y", "width", "height"])
        vary(##"<defs><clipPath id="c" ATTR="$V"><rect width="5" height="5"/></clipPath></defs><rect width="10" height="10" clip-path="url(#c)"/>"##,
             ["transform"])
        vary(##"<defs><marker id="k" markerWidth="3" markerHeight="3" ATTR="$V"><rect width="2" height="2"/></marker></defs><path d="M1 1 L8 8 L9 1" stroke="#000" fill="none" marker-start="url(#k)" marker-mid="url(#k)" marker-end="url(#k)"/>"##,
             ["markerWidth", "markerHeight", "refX", "refY", "viewBox", "orient", "markerUnits"])
        vary(##"<defs><filter id="f" ATTR="$V"><feGaussianBlur stdDeviation="1"/></filter></defs><rect width="5" height="5" filter="url(#f)"/>"##,
             ["x", "y", "width", "height"])
        vary(##"<defs><filter id="f"><feGaussianBlur ATTR="$V"/></filter></defs><rect width="5" height="5" filter="url(#f)"/>"##, ["stdDeviation"])
        vary(##"<defs><filter id="f"><feOffset ATTR="$V"/></filter></defs><rect width="5" height="5" filter="url(#f)"/>"##, ["dx", "dy"])
        vary(##"<defs><filter id="f"><feDropShadow ATTR="$V"/></filter></defs><rect width="5" height="5" filter="url(#f)"/>"##, ["dx", "dy", "stdDeviation", "flood-opacity"])
        // Text.
        vary(##"<text x="1" y="8" font-size="5" ATTR="$V">hi<tspan>yo</tspan></text>"##,
             ["x", "y", "font-size", "font-weight", "stroke-width", "opacity", "dx", "dy", "letter-spacing", "textLength"])
        result.append(##"<text x="1" y="8" font-size="$V%">hi</text>"##)
        result.append(##"<text x="1" y="8" font-size="$Vem">hi</text>"##)
        result.append(##"<text x="1" y="8" font-size="5" stroke="#000" stroke-width="$V" fill="none">hi</text>"##)
        // Animation.
        for animation in [##"<animate attributeName="opacity" from="$V" to="$V" dur="1s"/>"##,
                          ##"<animate attributeName="opacity" values="0;$V;1" dur="1s"/>"##,
                          ##"<animate attributeName="opacity" from="0" to="1" dur="$V"/>"##,
                          ##"<animate attributeName="opacity" from="0" to="1" dur="1s" begin="$V"/>"##,
                          ##"<animate attributeName="opacity" values="0;1" keyTimes="0;$V" dur="1s"/>"##,
                          ##"<animate attributeName="opacity" from="0" to="1" dur="1s" repeatCount="$V"/>"##,
                          ##"<animateTransform attributeName="transform" type="rotate" from="$V" to="$V" dur="1s"/>"##,
                          ##"<animateTransform attributeName="transform" type="rotate" values="0 $V $V;$V" dur="1s"/>"##,
                          ##"<animateTransform attributeName="transform" type="scale" from="$V" to="2" dur="1s"/>"##,
                          ##"<animateTransform attributeName="transform" type="translate" values="0,0;$V,$V" dur="1s"/>"##,
                          ##"<animateTransform attributeName="transform" type="skewX" values="0;$V" dur="1s"/>"##,
                          ##"<set attributeName="opacity" to="$V" begin="0s"/>"##] {
            result.append("<rect width=\"10\" height=\"10\" fill=\"red\">\(animation)</rect>")
        }
        return result
    }

    func testHostileNumbersNeverTrap() throws {
        let cases = bodies
        var count = 0
        for body in cases {
            for value in values {
                let inner = body.replacingOccurrences(of: "$V", with: value)
                let svg = inner.hasPrefix("<svg") ? inner : "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 10 10\">\(inner)</svg>"
                print("HOSTILE \(svg)")
                count += 1
                guard let parser = try? SVGParser(svgString: svg, parsedRoot: nil),
                      let layer = try? parser.getLayer(overrideElements: nil) else { continue }
                layer.frame = CGRect(x: 0, y: 0, width: 32, height: 32)
                guard let context = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
                layer.render(in: context)
            }
        }
        XCTAssertGreaterThan(count, 1000)
    }
}
