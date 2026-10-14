import XCTest
@testable import SVGRenderKit

/// Regression tests for the former Task.md backlog (B41…B72), including the items that were
/// verified and closed as "won't fix" (the tests pin the verified behaviour).
@MainActor
final class SVGBacklogTests: XCTestCase {

    private func layer(_ body: String, viewBox: String = "0 0 100 100") throws -> CALayer {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" viewBox=\"\(viewBox)\">\(body)</svg>"
        return try SVGParser(svgString: svg, parsedRoot: nil).getLayer(overrideElements: nil)
    }

    private func root(_ body: String, viewBox: String = "0 0 100 100") throws -> SVGRoot {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" viewBox=\"\(viewBox)\">\(body)</svg>"
        return try SVGParser(svgString: svg, parsedRoot: nil).root
    }

    private func all<T: CALayer>(_ type: T.Type, in l: CALayer) -> [T] {
        var out: [T] = []
        if let t = l as? T { out.append(t) }
        for s in l.sublayers ?? [] { out += all(type, in: s) }
        return out
    }

    /// Alpha at a pixel after rendering the layer. Sample at y=50 to avoid the raw
    /// (y-up) context's flip relative to `CALayer.render`.
    private func alpha(_ layer: CALayer, at point: CGPoint, size: Int = 100) -> UInt8 {
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        guard let ctx = CGContext(data: &pixels, width: size, height: size, bitsPerComponent: 8,
                                  bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        layer.frame = CGRect(x: 0, y: 0, width: size, height: size)
        layer.render(in: ctx)
        return pixels[(Int(point.y) * size + Int(point.x)) * 4 + 3]
    }

    // MARK: B41 — <use>+<symbol> transform order (verified correct)

    func testB41SymbolUseCentersAndScalesContent() throws {
        let l = try layer("""
        <symbol id="s" viewBox="0 0 10 10"><rect width="10" height="10"/></symbol>
        <use xlink:href="#s" width="100" height="50"/>
        """)
        // viewBox 10x10 into 100x50 (meet): scale 5, centered horizontally by 25.
        let transformed = try XCTUnwrap(all(CALayer.self, in: l).first { !CATransform3DIsIdentity($0.transform) })
        let t = CATransform3DGetAffineTransform(transformed.transform)
        let origin = CGPoint.zero.applying(t)
        let corner = CGPoint(x: 10, y: 10).applying(t)
        XCTAssertEqual(origin.x, 25, accuracy: 0.001)
        XCTAssertEqual(origin.y, 0, accuracy: 0.001)
        XCTAssertEqual(corner.x, 75, accuracy: 0.001)
        XCTAssertEqual(corner.y, 50, accuracy: 0.001)
    }

    // MARK: B44 — userSpaceOnUse gradients with a non-zero viewBox origin

    func testB44LinearGradientHonorsViewBoxOrigin() throws {
        let l = try layer("""
        <defs><linearGradient id="g" gradientUnits="userSpaceOnUse" x1="10" y1="10" x2="110" y2="10">
        <stop offset="0" stop-color="#f00"/><stop offset="1" stop-color="#00f"/></linearGradient></defs>
        <rect x="10" y="10" width="100" height="100" fill="url(#g)"/>
        """, viewBox: "10 10 100 100")
        let g = try XCTUnwrap(all(CAGradientLayer.self, in: l).first)
        XCTAssertEqual(g.startPoint.x, 0, accuracy: 0.001)
        XCTAssertEqual(g.endPoint.x, 1, accuracy: 0.001)
    }

    func testB44RadialGradientHonorsViewBoxOrigin() throws {
        let l = try layer("""
        <defs><radialGradient id="g" gradientUnits="userSpaceOnUse" cx="60" cy="60" r="50">
        <stop offset="0" stop-color="#f00"/><stop offset="1" stop-color="#00f"/></radialGradient></defs>
        <rect x="10" y="10" width="100" height="100" fill="url(#g)"/>
        """, viewBox: "10 10 100 100")
        let g = try XCTUnwrap(all(RadialGradientLayer.self, in: l).first)
        XCTAssertEqual(g.center.x, 50, accuracy: 0.001)
        XCTAssertEqual(g.center.y, 50, accuracy: 0.001)
    }

    // MARK: B72 — non-uniform gradientTransform makes the radial gradient elliptical

    func testB72NonUniformGradientTransformIsAppliedAsAffine() throws {
        let l = try layer("""
        <defs><radialGradient id="g" gradientUnits="userSpaceOnUse" cx="50" cy="50" r="25" gradientTransform="scale(2 1)">
        <stop offset="0" stop-color="#f00"/><stop offset="1" stop-color="#00f"/></radialGradient></defs>
        <rect width="100" height="100" fill="url(#g)"/>
        """)
        let g = try XCTUnwrap(all(RadialGradientLayer.self, in: l).first)
        XCTAssertEqual(g.gradientTransform.a, 2, accuracy: 0.001)
        XCTAssertEqual(g.gradientTransform.d, 1, accuracy: 0.001)
        XCTAssertEqual(g.radius, 25, accuracy: 0.001)
    }

    // MARK: B45 — XML errors are logged

    private final class CaptureLogger: SVGLogger {
        var messages: [String] = []
        func log(_ message: String) { messages.append(message) }
    }

    func testB45TruncatedXMLIsLogged() {
        let logger = CaptureLogger()
        let previous = SVGLog.logger
        SVGLog.logger = logger
        defer { SVGLog.logger = previous }
        _ = try? SVGParser(svgString: "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 10 10\"><g><rect width=\"5\" height=\"5\"/>", parsedRoot: nil)
        XCTAssertTrue(logger.messages.contains { $0.contains("XML parse error") })
    }

    // MARK: B46 — url(...) parsing

    func testB46FuncIRIParsing() throws {
        guard case .local(let key) = try SVGFuncIRI.get(fullStr: "URL( #a )") else { return XCTFail() }
        XCTAssertEqual(key, "#a")
        guard case .local(let key2) = try SVGFuncIRI.get(fullStr: "url (#b)") else { return XCTFail() }
        XCTAssertEqual(key2, "#b")
        XCTAssertThrowsError(try SVGFuncIRI.get(fullStr: "urlfoo(#a)"))
        XCTAssertThrowsError(try SVGFuncIRI.get(fullStr: "url(foo(1))"))
    }

    // MARK: B47 — SVGLength precision and non-finite input

    func testB47LengthUsesDoublePrecisionAndRejectsNonFinite() throws {
        guard case .px(let v) = try SVGLength.get(string: "0.1234567891") else { return XCTFail() }
        XCTAssertEqual(Double(v), 0.1234567891, accuracy: 1e-9)
        guard case .px(let inf) = try SVGLength.get(string: "1e999") else { return XCTFail() }
        XCTAssertEqual(inf, 0)
    }

    // MARK: B49 — a path must start with moveto (verified against SVG 1.1 §8.3.9)

    func testB49PathWithoutLeadingMoveToIsRejectedBySpec() {
        XCTAssertNotNil(SVGParseString.parseSVGPath(pathString: "L 10 10").error)
        XCTAssertNil(SVGParseString.parseSVGPath(pathString: "M 0 0 L 10 10").error)
    }

    // MARK: B52 — contentBounds counts <use> and <image>

    func testB52ContentBoundsIncludesUseAndImage() throws {
        let r = try root("""
        <defs><rect id="r" width="10" height="10"/></defs>
        <use xlink:href="#r" x="20" y="5"/>
        <image x="50" y="60" width="10" height="20" xlink:href="data:image/png;base64,AAAA"/>
        """)
        let b = r.svgElement.contentBounds
        XCTAssertEqual(b.minX, 20, accuracy: 0.001)
        XCTAssertEqual(b.minY, 5, accuracy: 0.001)
        XCTAssertEqual(b.maxX, 60, accuracy: 0.001)
        XCTAssertEqual(b.maxY, 80, accuracy: 0.001)
    }

    // MARK: B53 — marker viewport (markerWidth/Height + viewBox)

    func testB53MarkerViewBoxScalesIntoMarkerViewport() throws {
        let r = try root("""
        <defs><marker id="m" markerWidth="10" markerHeight="10" viewBox="0 0 20 20" refX="0" refY="0"><rect width="20" height="20"/></marker></defs>
        <path d="M0 0 L50 50" stroke="#000" marker-end="url(#m)"/>
        """)
        let marker = try XCTUnwrap(r.svgElement.getMarker(byKey: "#m", fromParents: false))
        let mapping = marker.viewportMapping()
        XCTAssertEqual(mapping.scale, 0.5, accuracy: 0.001)
        XCTAssertEqual(mapping.clip.width, 20, accuracy: 0.001)
    }

    func testB53MarkerClipsToViewportUnlessOverflowVisible() throws {
        func masks(_ overflow: String) throws -> Int {
            let l = try layer("""
            <defs><marker id="m" markerWidth="4" markerHeight="4" \(overflow)><rect width="20" height="20"/></marker></defs>
            <path d="M0 0 L50 50" stroke="#000" marker-end="url(#m)"/>
            """)
            return all(CALayer.self, in: l).filter { $0.mask is CAShapeLayer && $0.sublayers?.contains(where: { $0 is CAShapeLayer }) == true }.count
        }
        XCTAssertGreaterThan(try masks(""), 0)
        XCTAssertEqual(try masks("overflow=\"visible\""), 0)
    }

    // MARK: B54 — markers render even with stroke="none" (verified against SVG 1.1 §11.6.2)

    func testB54MarkersAreDrawnWithoutStroke() throws {
        let withMarker = try layer("""
        <defs><marker id="m" markerWidth="4" markerHeight="4"><rect width="4" height="4"/></marker></defs>
        <path d="M0 0 L50 50" stroke="none" marker-end="url(#m)"/>
        """)
        let without = try layer("<path d=\"M0 0 L50 50\" stroke=\"none\"/>")
        XCTAssertGreaterThan(all(CAShapeLayer.self, in: withMarker).count, all(CAShapeLayer.self, in: without).count)
    }

    // MARK: B55/B56 — filters

    func testB55StdDeviationPairIsAveraged() {
        XCTAssertEqual(SVGFilter.parseStdDeviation("3 4"), 3.5)
        XCTAssertEqual(SVGFilter.parseStdDeviation("3,5"), 4)
        XCTAssertEqual(SVGFilter.parseStdDeviation("2"), 2)
        XCTAssertNil(SVGFilter.parseStdDeviation("a"))
        XCTAssertNil(SVGFilter.parseStdDeviation("1 2 3"))
    }

    func testB55BlurWithPairStdDeviationIsApplied() throws {
        // `stdDeviation="3 4"` averages to 3.5, so the element is actually blurred:
        // the band just outside the rect is partly opaque (B97 bakes the blur in).
        let l = try layer("""
        <defs><filter id="f"><feGaussianBlur stdDeviation="3 4"/></filter></defs>
        <rect x="0" y="25" width="50" height="50" fill="#000000" filter="url(#f)"/>
        """)
        XCTAssertGreaterThan(alpha(l, at: CGPoint(x: 53, y: 50)), 0)
    }

    func testB56BlurAndDropShadowAreCombined() throws {
        let l = try layer("""
        <defs><filter id="f"><feGaussianBlur stdDeviation="2"/><feDropShadow dx="2" dy="2" stdDeviation="3" flood-opacity="0.5"/></filter></defs>
        <rect x="0" y="25" width="50" height="50" fill="#000000" filter="url(#f)"/>
        """)
        let filtered = try XCTUnwrap(all(CALayer.self, in: l).first { $0.shadowOpacity > 0 })
        XCTAssertGreaterThan(filtered.shadowRadius, 0)
        // The element itself is blurred too: a baked bitmap replaces its sublayers.
        XCTAssertTrue(all(CALayer.self, in: filtered).contains { $0.contents != nil })
    }

    // MARK: B57 — <image> preserveAspectRatio

    private func pngDataURI(width: Int, height: Int) -> String {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height),
                                               format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
        let data = renderer.pngData { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return "data:image/png;base64," + data.base64EncodedString()
    }

    func testB57ImageMeetCentersAndKeepsAspect() throws {
        let l = try layer("<image x=\"0\" y=\"0\" width=\"100\" height=\"100\" xlink:href=\"\(pngDataURI(width: 20, height: 10))\"/>")
        let content = try XCTUnwrap(all(CALayer.self, in: l).first { $0.contents != nil })
        XCTAssertEqual(content.frame.width, 100, accuracy: 0.01)
        XCTAssertEqual(content.frame.height, 50, accuracy: 0.01)
        XCTAssertEqual(content.frame.minY, 25, accuracy: 0.01)
    }

    func testB57ImageSliceFillsAndClips() throws {
        let l = try layer("<image width=\"100\" height=\"100\" preserveAspectRatio=\"xMidYMid slice\" xlink:href=\"\(pngDataURI(width: 20, height: 10))\"/>")
        let content = try XCTUnwrap(all(CALayer.self, in: l).first { $0.contents != nil })
        XCTAssertEqual(content.frame.height, 100, accuracy: 0.01)
        XCTAssertEqual(content.frame.width, 200, accuracy: 0.01)
        XCTAssertTrue(content.superlayer?.masksToBounds ?? false)
    }

    func testB57ImageNoneStretches() throws {
        let l = try layer("<image width=\"100\" height=\"100\" preserveAspectRatio=\"none\" xlink:href=\"\(pngDataURI(width: 20, height: 10))\"/>")
        let content = try XCTUnwrap(all(CALayer.self, in: l).first { $0.contents != nil })
        XCTAssertEqual(content.frame.size, CGSize(width: 100, height: 100))
    }

    // MARK: B58 — pattern fill-opacity and gradient stroke-opacity

    func testB58GradientStrokeOpacityIsApplied() throws {
        let l = try layer("""
        <defs><linearGradient id="g"><stop offset="0" stop-color="#f00"/><stop offset="1" stop-color="#00f"/></linearGradient></defs>
        <rect width="50" height="50" fill="none" stroke="url(#g)" stroke-width="4" stroke-opacity="0.5"/>
        """)
        let g = try XCTUnwrap(all(CAGradientLayer.self, in: l).first)
        XCTAssertEqual(g.superlayer?.opacity ?? 1, 0.5, accuracy: 0.001)
    }

    func testB58PatternFillOpacityIsApplied() throws {
        let l = try layer("""
        <defs><pattern id="p" width="10" height="10" patternUnits="userSpaceOnUse"><rect width="10" height="10" fill="#f00"/></pattern></defs>
        <rect width="50" height="50" fill="url(#p)" fill-opacity="0.5"/>
        """)
        // A coloured pattern carries fill-opacity in its tint, so check the rendered alpha.
        XCTAssertEqual(alpha(l, at: CGPoint(x: 25, y: 50)), 128, accuracy: 12)
    }

    // MARK: B60 — fromParents is honored

    func testB60ShapeGradientLookupHonorsFromParents() throws {
        let r = try root("""
        <defs><linearGradient id="g"><stop offset="0" stop-color="#f00"/><stop offset="1" stop-color="#00f"/></linearGradient></defs>
        <rect width="10" height="10"/>
        """)
        let shape = try XCTUnwrap(r.svgElement.layerElements.array.compactMap { $0 as? SVGShapeObject }.first)
        XCTAssertNotNil(shape.getGradient(byKey: "#g", fromParents: true))
        XCTAssertNil(shape.getGradient(byKey: "#g", fromParents: false))
    }

    // MARK: B62 — malformed numbers are not silently zero

    private func number(_ text: String) -> CGFloat? {
        var stack = NumberStack()
        stack.characterStack = text
        return stack.asCGFloat
    }

    func testB62MalformedPathNumbers() {
        XCTAssertNil(number("1e-"))
        XCTAssertNil(number("."))
        XCTAssertNil(number("1e999"))
        XCTAssertEqual(number("-.5"), -0.5)
        XCTAssertEqual(number("5."), 5)
    }

    // MARK: B63 — preserveAspectRatio with a comma

    func testB63PreserveAspectRatioAcceptsComma() {
        let p = SVGPreserveAspectRatio.get(string: "xMinYMax, slice")
        XCTAssertEqual(p.align, .xMinYMax)
        XCTAssertEqual(p.meetOrSlice, .slice)
        let d = SVGPreserveAspectRatio.get(string: "defer xMidYMid,meet")
        XCTAssertEqual(d.align, .xMidYMid)
    }

    // MARK: B64 — gradient dedupe by id (first definition wins)

    func testB64DuplicateGradientIdUsesFirstDefinition() throws {
        let l = try layer("""
        <defs>
        <linearGradient id="g"><stop offset="0" stop-color="#ff0000"/><stop offset="1" stop-color="#ff0000"/></linearGradient>
        <linearGradient id="g"><stop offset="0" stop-color="#0000ff"/><stop offset="1" stop-color="#0000ff"/></linearGradient>
        </defs>
        <rect width="50" height="50" fill="url(#g)"/>
        """)
        let g = try XCTUnwrap(all(CAGradientLayer.self, in: l).first)
        let first = UIColor(cgColor: g.colors?.first as! CGColor)
        var r: CGFloat = 0, b: CGFloat = 0
        first.getRed(&r, green: nil, blue: &b, alpha: nil)
        XCTAssertEqual(r, 1, accuracy: 0.01)
        XCTAssertEqual(b, 0, accuracy: 0.01)
    }

    // MARK: B65 — "none" is not an opaque color

    func testB65NoneColorIsTransparent() {
        XCTAssertEqual(SVGColors.getColor(string: "none").cgColor.alpha, 0)
    }

    // MARK: B66 — a set override is visible to an immediately following read (verified)

    func testB66OverrideIsVisibleImmediately() {
        defer { SVGColors.setOvverideColors(colors: [:]) }
        for i in 0..<200 {
            SVGColors.setOvverideColors(colors: ["#abc": i % 2 == 0 ? "#ff0000" : "#0000ff"])
            var r: CGFloat = 0
            SVGColors.getColor(string: "#abc").getRed(&r, green: nil, blue: nil, alpha: nil)
            XCTAssertEqual(r, i % 2 == 0 ? 1 : 0, accuracy: 0.01, "iteration \(i)")
        }
    }

    // MARK: B67 — invalid transform arguments

    func testB67NonNumericTransformArgumentThrows() {
        XCTAssertThrowsError(try SVGTransform.get(string: "translate(foo 10)"))
        XCTAssertThrowsError(try SVGTransform.get(string: "scale(1e999)"))
        XCTAssertNoThrow(try SVGTransform.get(string: "translate(5 10)"))
    }

    // MARK: B68 — skew(90°) stays finite (degenerate, like browsers) (verified)

    func testB68Skew90IsFiniteAndDegenerate() throws {
        let t = try SVGTransform.get(string: "skewX(90)")
        XCTAssertTrue(t.m21.isFinite)
        XCTAssertGreaterThan(abs(t.m21), 1e10)
    }

    // MARK: B69 — arc flags / radicant sign (verified against the analytic circle)

    func testB69LargeArcSweepVariantsMatchGeometry() throws {
        func bounds(_ d: String) throws -> CGRect {
            let l = try layer("<path d=\"\(d)\"/>")
            return try XCTUnwrap(all(CAShapeLayer.self, in: l).first { $0.path != nil }).path!.boundingBoxOfPath
        }
        // Radius-50 circle through (50,0) and (0,50): centers (50,50) and (0,0).
        let a = try bounds("M 50 0 A 50 50 0 1 1 0 50")   // large, clockwise → center (50,50)
        XCTAssertEqual(a.minX, 0, accuracy: 0.5); XCTAssertEqual(a.maxX, 100, accuracy: 0.5)
        XCTAssertEqual(a.minY, 0, accuracy: 0.5); XCTAssertEqual(a.maxY, 100, accuracy: 0.5)
        let b = try bounds("M 50 0 A 50 50 0 1 0 0 50")   // large, counter-clockwise → center (0,0)
        XCTAssertEqual(b.minX, -50, accuracy: 0.5); XCTAssertEqual(b.maxX, 50, accuracy: 0.5)
        XCTAssertEqual(b.minY, -50, accuracy: 0.5); XCTAssertEqual(b.maxY, 50, accuracy: 0.5)
        let c = try bounds("M 50 0 A 50 50 0 0 0 0 50")   // small, counter-clockwise → center (50,50)
        XCTAssertEqual(c.maxX, 50, accuracy: 0.5); XCTAssertEqual(c.maxY, 50, accuracy: 0.5)
    }

    // MARK: B70 — Figma shadow tint uses the alpha coefficient (verified)

    func testB70FigmaShadowOpacityComesFromAlphaCoefficient() throws {
        let l = try layer("""
        <defs><filter id="f">
        <feOffset dy="4"/><feGaussianBlur stdDeviation="2"/>
        <feColorMatrix type="matrix" values="0 0 0 0 0.2  0 0 0 0 0.4  0 0 0 0 0.6  0 0 0 0.25 0"/>
        </filter></defs>
        <rect width="50" height="50" filter="url(#f)"/>
        """)
        let shadowLayer = try XCTUnwrap(all(CALayer.self, in: l).first { $0.shadowOpacity > 0 })
        XCTAssertEqual(shadowLayer.shadowOpacity, 0.25, accuracy: 0.001)
    }

    // MARK: B71 — shadows live in layer space, scaled by the view's transform (verified)

    func testB71ShadowIsInLocalUnitsAndScaledByAncestorTransform() throws {
        let view = SVGView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        view.set(svgData: Data("""
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><defs><filter id="f">
        <feDropShadow dx="5" dy="5" stdDeviation="2"/></filter></defs>
        <rect width="50" height="50" filter="url(#f)"/></svg>
        """.utf8), name: "b71-\(UUID().uuidString)", fill_colors: nil)
        let exp = expectation(description: "render")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { exp.fulfill() }
        wait(for: [exp], timeout: 5)
        view.layoutIfNeeded()
        let shadowLayer = try XCTUnwrap(all(CALayer.self, in: view.layer).first { $0.shadowOpacity > 0 })
        XCTAssertEqual(shadowLayer.shadowOffset.width, 5, accuracy: 0.001)
        let scaled = try XCTUnwrap(all(CALayer.self, in: view.layer).first { $0.transform.m11 == 2 })
        XCTAssertNotNil(scaled)
    }
}
