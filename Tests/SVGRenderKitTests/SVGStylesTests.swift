import XCTest
@testable import SVGRenderKit

final class SVGStylesTests: XCTestCase {

    func testSetFontFamilyStoresFontFamilyAndNotClipPath() {
        let style = SVGSourceStyleElement()
        style.setFontFamily(str: "Helvetica, Arial")

        XCTAssertEqual(style.fontFamily, "Helvetica, Arial")
        XCTAssertNil(style.clipPath)
    }

    // MARK: Stroke attributes

    func testStrokeLinecapParsed() throws {
        let style = SVGSourceStyleElement()
        try style.set(attributeDict: ["stroke-linecap": "round"])
        XCTAssertEqual(style.strokeLinecap, .round)
    }

    func testStrokeLinejoinParsed() throws {
        let style = SVGSourceStyleElement()
        try style.set(attributeDict: ["stroke-linejoin": "bevel"])
        XCTAssertEqual(style.strokeLinejoin, .bevel)
    }

    func testStrokeMiterlimitParsed() throws {
        let style = SVGSourceStyleElement()
        try style.set(attributeDict: ["stroke-miterlimit": "8"])
        let miter = try XCTUnwrap(style.strokeMiterlimit)
        XCTAssertEqual(miter, 8, accuracy: 0.0001)
    }

    func testStrokeLinecapInheritLeavesNil() throws {
        let style = SVGSourceStyleElement()
        try style.set(attributeDict: ["stroke-linecap": "inherit"])
        XCTAssertNil(style.strokeLinecap)
    }

    func testStrokeLinecapInvalidLeavesNil() throws {
        let style = SVGSourceStyleElement()
        try style.set(attributeDict: ["stroke-linecap": "bogus"])
        XCTAssertNil(style.strokeLinecap)
    }

    func testStrokeAttributesAppliedToLayer() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <line x1="10" y1="10" x2="90" y2="90" stroke="#000000" stroke-width="2"
                  stroke-linecap="round" stroke-linejoin="round" stroke-miterlimit="5"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let shape = try XCTUnwrap(findStrokedShapeLayer(in: layer))

        XCTAssertEqual(shape.lineCap.rawValue, "round")
        XCTAssertEqual(shape.lineJoin.rawValue, "round")
        XCTAssertEqual(shape.miterLimit, 5, accuracy: 0.0001)
    }

    func testStyleClassSelectorOverridesInheritedFill() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <style type="text/css">.st0{fill:#0F754E;}</style>
            <g fill="none">
                <path class="st0" d="M0 0 H100 V100 H0 Z"/>
            </g>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let shape = try XCTUnwrap(findFilledShapeLayer(in: layer))
        let fill = try XCTUnwrap(shape.fillColor)
        let color = UIColor(cgColor: fill)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        XCTAssertTrue(color.getRed(&r, green: &g, blue: &b, alpha: &a))
        XCTAssertEqual(r, 0x0F / 255.0, accuracy: 0.01)
        XCTAssertEqual(g, 0x75 / 255.0, accuracy: 0.01)
        XCTAssertEqual(b, 0x4E / 255.0, accuracy: 0.01)
    }

    func testStyleIdSelectorOverridesClassSelector() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <style type="text/css">.st0{fill:#0F754E;} #main{fill:#FF0000;}</style>
            <g fill="none">
                <path id="main" class="st0" d="M0 0 H100 V100 H0 Z"/>
            </g>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let shape = try XCTUnwrap(findFilledShapeLayer(in: layer))
        let fill = try XCTUnwrap(shape.fillColor)
        let color = UIColor(cgColor: fill)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        XCTAssertTrue(color.getRed(&r, green: &g, blue: &b, alpha: &a))
        XCTAssertEqual(r, 1.0, accuracy: 0.01)
        XCTAssertEqual(g, 0.0, accuracy: 0.01)
        XCTAssertEqual(b, 0.0, accuracy: 0.01)
    }

    // MARK: Stroke dash

    func testStrokeDasharrayParsed() throws {
        let style = SVGSourceStyleElement()
        try style.set(attributeDict: ["stroke-dasharray": "5, 5"])
        let arr = try XCTUnwrap(style.strokeDasharray)
        XCTAssertEqual(arr, [CGFloat(5), CGFloat(5)])
    }

    func testStrokeDasharraySpaceSeparated() throws {
        let style = SVGSourceStyleElement()
        try style.set(attributeDict: ["stroke-dasharray": "5 3 2"])
        let arr = try XCTUnwrap(style.strokeDasharray)
        XCTAssertEqual(arr, [CGFloat(5), CGFloat(3), CGFloat(2), CGFloat(5), CGFloat(3), CGFloat(2)])
    }

    func testStrokeDasharrayOddCountDoubled() throws {
        let style = SVGSourceStyleElement()
        try style.set(attributeDict: ["stroke-dasharray": "5"])
        let arr = try XCTUnwrap(style.strokeDasharray)
        XCTAssertEqual(arr, [CGFloat(5), CGFloat(5)])
    }

    func testStrokeDasharrayNoneLeavesNil() throws {
        let style = SVGSourceStyleElement()
        try style.set(attributeDict: ["stroke-dasharray": "none"])
        XCTAssertNil(style.strokeDasharray)
    }

    func testStrokeDasharrayInvalidLeavesNil() throws {
        let style = SVGSourceStyleElement()
        try style.set(attributeDict: ["stroke-dasharray": "foo"])
        XCTAssertNil(style.strokeDasharray)
    }

    func testStrokeDasharrayNegativeLeavesNil() throws {
        let style = SVGSourceStyleElement()
        try style.set(attributeDict: ["stroke-dasharray": "5 -5"])
        XCTAssertNil(style.strokeDasharray)
    }

    func testStrokeDashoffsetParsed() throws {
        let style = SVGSourceStyleElement()
        try style.set(attributeDict: ["stroke-dashoffset": "3"])
        let offset = try XCTUnwrap(style.strokeDashoffset)
        XCTAssertEqual(offset, 3, accuracy: 0.0001)
    }

    func testStrokeDashAppliedToLayer() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <line x1="0" y1="50" x2="100" y2="50" stroke="#000000" stroke-width="2"
                  stroke-dasharray="5 5" stroke-dashoffset="2"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let shape = try XCTUnwrap(findStrokedShapeLayer(in: layer))

        guard let pattern = shape.lineDashPattern else {
            return XCTFail("expected a dash pattern")
        }
        XCTAssertEqual(pattern.count, 2)
        XCTAssertEqual(pattern[0].doubleValue, 5, accuracy: 0.0001)
        XCTAssertEqual(pattern[1].doubleValue, 5, accuracy: 0.0001)
        XCTAssertEqual(shape.lineDashPhase, 2, accuracy: 0.0001)
    }

    private func findStrokedShapeLayer(in layer: CALayer) -> CAShapeLayer? {
        if let shape = layer as? CAShapeLayer, shape.strokeColor != nil {
            return shape
        }
        for sublayer in layer.sublayers ?? [] {
            if let found = findStrokedShapeLayer(in: sublayer) {
                return found
            }
        }
        return nil
    }

    private func findFilledShapeLayer(in layer: CALayer) -> CAShapeLayer? {
        if let shape = layer as? CAShapeLayer, shape.path != nil, shape.fillColor != nil {
            return shape
        }
        for sublayer in layer.sublayers ?? [] {
            if let found = findFilledShapeLayer(in: sublayer) {
                return found
            }
        }
        return nil
    }

    func testFillOpacityMultipliesAlpha() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <rect width="50" height="50" fill="rgba(255,0,0,0.5)" fill-opacity="0.5"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let shape = try XCTUnwrap(findFilledShapeLayer(in: layer))
        let alpha = try XCTUnwrap(shape.fillColor).alpha
        XCTAssertEqual(alpha, 0.25, accuracy: 0.01)
    }

    // MARK: Visibility (F1)

    func testVisibilityParsed() throws {
        let style = SVGSourceStyleElement()
        try style.set(attributeDict: ["visibility": "hidden"])
        XCTAssertEqual(style.visibility, .hidden)
    }

    func testVisibilityHiddenHidesShape() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <rect x="10" y="10" width="50" height="50" fill="#e74c3c" visibility="hidden"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        XCTAssertTrue(hasHiddenLayer(in: layer))
    }

    // MARK: Group composite (F1)

    func testGroupOpacityCompositesGroup() throws {
        // Group opacity must apply to the group's composite, not be inherited to
        // each child (which would double-fade overlaps).
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <g opacity="0.5">
                <rect x="10" y="10" width="50" height="50" fill="#e74c3c"/>
            </g>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        let group = try XCTUnwrap(findLayer(withOpacity: 0.5, in: layer))
        let child = try XCTUnwrap(group.sublayers?.first)
        XCTAssertEqual(child.opacity, 1, accuracy: 0.001)
    }

    func testGroupClipPathAppliesMask() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs><clipPath id="c"><circle cx="50" cy="50" r="40"/></clipPath></defs>
            <g clip-path="url(#c)">
                <rect x="10" y="10" width="80" height="80" fill="#e74c3c"/>
            </g>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        XCTAssertTrue(hasMaskedLayer(in: layer))
    }

    private func hasHiddenLayer(in layer: CALayer) -> Bool {
        if layer.isHidden { return true }
        for sublayer in layer.sublayers ?? [] {
            if hasHiddenLayer(in: sublayer) { return true }
        }
        return false
    }

    private func hasMaskedLayer(in layer: CALayer) -> Bool {
        if layer.mask != nil { return true }
        for sublayer in layer.sublayers ?? [] {
            if hasMaskedLayer(in: sublayer) { return true }
        }
        return false
    }

    private func findLayer(withOpacity opacity: Float, in layer: CALayer) -> CALayer? {
        if abs(layer.opacity - opacity) < 0.001 {
            return layer
        }
        for sublayer in layer.sublayers ?? [] {
            if let found = findLayer(withOpacity: opacity, in: sublayer) {
                return found
            }
        }
        return nil
    }
}
