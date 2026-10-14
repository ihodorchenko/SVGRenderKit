import XCTest
@testable import SVGRenderKit

/// B82 — the parsed document is an ownership tree, not a web of retain cycles.
/// Releasing the `SVGRoot` (dropping the parser, or evicting the entry from the
/// parser cache) must deallocate the whole object tree.
final class SVGMemoryManagementTests: XCTestCase {

    private let markup = """
    <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 10 10">
      <defs>
        <linearGradient id="grad"><stop offset="0" stop-color="#000"/><stop offset="1" stop-color="#fff"/></linearGradient>
        <clipPath id="clip"><rect width="10" height="10"/></clipPath>
        <symbol id="sym"><circle cx="5" cy="5" r="4"/></symbol>
      </defs>
      <g id="grp" fill="url(#grad)" clip-path="url(#clip)">
        <rect width="10" height="10"/>
        <use xlink:href="#sym"/>
      </g>
    </svg>
    """

    override func tearDown() {
        SVGCache.s.resetCache()
        super.tearDown()
    }

    func testDocumentDeallocatesWhenParserIsReleased() throws {
        weak var weakRoot: SVGRoot?
        weak var weakGroup: SVGGroupObject?
        weak var weakShape: SVGShapeObject?

        autoreleasepool {
            do {
                let parser = try SVGParser(svgString: markup, parsedRoot: nil)
                let group = parser.root.svgElement.all.array.compactMap { $0 as? SVGGroupObject }.first
                let shape = group?.all.array.compactMap { $0 as? SVGShapeObject }.first

                weakRoot = parser.root
                weakGroup = group
                weakShape = shape

                XCTAssertNotNil(weakRoot, "precondition: the document parsed")
                XCTAssertNotNil(group, "precondition: the group was found")
                XCTAssertNotNil(shape, "precondition: the shape was found")
            } catch {
                XCTFail("parse failed: \(error)")
            }
        }

        XCTAssertNil(weakRoot, "SVGRoot is retained after the parser is released")
        XCTAssertNil(weakGroup, "group object is retained after the parser is released")
        XCTAssertNil(weakShape, "shape object is retained after the parser is released")
    }

    func testLayerBuildDoesNotRetainModel() throws {
        weak var weakRoot: SVGRoot?

        autoreleasepool {
            do {
                let parser = try SVGParser(svgString: markup, parsedRoot: nil)
                weakRoot = parser.root
                _ = try parser.getLayer(overrideElements: nil)
            } catch {
                XCTFail("render failed: \(error)")
            }
        }

        XCTAssertNil(weakRoot, "SVGRoot is retained after building and dropping its layer")
    }

    func testCacheEvictionReleasesDocument() throws {
        SVGCache.s.resetCache()

        weak var weakRoot: SVGRoot?
        autoreleasepool {
            do {
                let parser = try SVGParser.getParser(svgString: markup, name: "B82-leak")
                weakRoot = parser.root
            } catch {
                XCTFail("parse failed: \(error)")
            }
        }
        XCTAssertNotNil(weakRoot, "precondition: a named document is cached")

        SVGCache.s.resetCache()
        XCTAssertNil(weakRoot, "document evicted from the parser cache leaked")
    }
}
