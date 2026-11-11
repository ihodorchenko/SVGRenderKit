import XCTest
@testable import SVGRenderKit

/// A style property is listed in several places of `SVGSourceStyleElement` (`set(attributeDict:)`,
/// `combine(child:)`, `set(element:)`). A property added to the class but forgotten in one of the
/// lists is silently dropped; these tests fail instead.
final class SVGStylePropertyCoverageTests: XCTestCase {

    /// One valid value for every presentation property.
    private let sample: [String: String] = [
        "display": "block", "visibility": "hidden", "text-anchor": "middle",
        "fill": "#112233", "color": "#445566", "fill-opacity": "0.5", "fill-rule": "evenodd", "opacity": "0.4",
        "stroke": "#778899", "stroke-opacity": "0.3", "stroke-width": "2",
        "stroke-linecap": "round", "stroke-linejoin": "bevel", "stroke-miterlimit": "5",
        "stroke-dasharray": "1 2", "stroke-dashoffset": "1",
        "clip-path": "url(#c)", "clip-rule": "evenodd", "mask": "url(#m)",
        "marker-start": "url(#a)", "marker-mid": "url(#b)", "marker-end": "url(#e)", "filter": "url(#f)",
        "transform": "translate(1px, 2px)", "transform-origin": "center center", "transform-box": "fill-box",
        "font-family": "Arial", "font-style": "italic", "font-weight": "700", "font-size": "12",
    ]

    /// Names of the stored properties that are `nil`.
    private func unsetProperties(of style: SVGSourceStyleElement) -> [String] {
        Mirror(reflecting: style).children.compactMap { child in
            let value = Mirror(reflecting: child.value)
            return value.displayStyle == .optional && value.children.isEmpty ? child.label : nil
        }
    }

    private func fullStyle() throws -> SVGSourceStyleElement {
        let style = SVGSourceStyleElement()
        try style.set(attributeDict: sample)
        return style
    }

    /// `filter` and `dropShadow` are two shapes of the same CSS property and are mutually
    /// exclusive, so the sample can only exercise one of them; `dropShadow` has its own test.
    func testSampleSetsEveryProperty() throws {
        XCTAssertEqual(unsetProperties(of: try fullStyle()), ["dropShadow"],
                       "a property is missing from `sample` or not parsed by `set(attributeDict:)`")
    }

    func testCombineCarriesEveryProperty() throws {
        let combined = SVGSourceStyleElement().combine(child: try fullStyle())
        XCTAssertEqual(unsetProperties(of: combined), ["dropShadow"], "`combine(child:)` drops a property")
    }

    func testSetElementCopiesEveryProperty() throws {
        let copy = SVGSourceStyleElement()
        copy.set(element: try fullStyle())
        XCTAssertEqual(unsetProperties(of: copy), ["dropShadow"], "`set(element:)` drops a property")
    }

    func testDropShadowIsACarriedProperty() throws {
        let style = SVGSourceStyleElement()
        try style.set(attributeDict: ["filter": "drop-shadow(1px 2px 3px #123456)"])
        XCTAssertNotNil(style.dropShadow)
        XCTAssertNil(style.filter)
        let combined = SVGSourceStyleElement().combine(child: style)
        XCTAssertNotNil(combined.dropShadow)
        XCTAssertNil(combined.filter, "`combine` keeps the mutually exclusive pair coherent")
        let copy = SVGSourceStyleElement()
        copy.set(element: style)
        XCTAssertNotNil(copy.dropShadow)
    }

    func testWithoutGroupCompositingKeepsTheRest() throws {
        let stripped = try fullStyle().withoutGroupCompositing()
        XCTAssertEqual(Set(unsetProperties(of: stripped)),
                       ["opacity", "clipPath", "mask", "filter", "dropShadow", "transform", "transformOrigin",
                        "transformBox"])
    }
}
