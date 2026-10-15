import XCTest
import UIKit
@testable import SVGRenderKit

/// B113 — the parser cache is keyed by a full digest of the content, not a fixed-width
/// `hashValue`, so a hash collision can never return a foreign parsed tree.
final class SVGParserCacheKeyTests: XCTestCase {

    private let red = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 10 10\"><rect width=\"10\" height=\"10\" fill=\"#ff0000\"/></svg>"
    private let blue = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 10 10\"><rect width=\"10\" height=\"10\" fill=\"#0000ff\"/></svg>"

    override func setUp() {
        super.setUp()
        SVGCache.s.isSVGParserUseCache = true
    }

    func testStringCacheDoesNotReturnStaleTreeForSameName() throws {
        let name = "cache-string-\(UUID().uuidString)"
        let a = try SVGParser.getParser(svgString: red, name: name)
        let b = try SVGParser.getParser(svgString: blue, name: name)
        XCTAssertFalse(a.root === b.root)
        let again = try SVGParser.getParser(svgString: red, name: name)
        XCTAssertTrue(a.root === again.root, "identical name+content should hit the cache")
    }

    func testDataCacheDoesNotReturnStaleTreeForSameName() throws {
        let name = "cache-data-\(UUID().uuidString)"
        let a = try SVGParser.getParser(svgData: Data(red.utf8), name: name)
        let b = try SVGParser.getParser(svgData: Data(blue.utf8), name: name)
        XCTAssertFalse(a.root === b.root)
        let again = try SVGParser.getParser(svgData: Data(red.utf8), name: name)
        XCTAssertTrue(a.root === again.root, "identical name+content should hit the cache")
    }
}
