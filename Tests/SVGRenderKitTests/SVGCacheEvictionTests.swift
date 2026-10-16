import XCTest
@testable import SVGRenderKit

/// B117 — LRU eviction of `SVGCache`, and a concurrent stress over the renderer.
final class SVGCacheEvictionTests: XCTestCase {

    private func root(_ n: Int) throws -> SVGRoot {
        try SVGParser(svgString: "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 \(n + 1) 1\"/>", parsedRoot: nil).root
    }

    override func setUp() {
        super.setUp()
        SVGCache.s.isSVGParserUseCache = true
        SVGCache.s.resetCache()
    }

    override func tearDown() {
        SVGCache.s.resetCache()
        super.tearDown()
    }

    func testOldestEntryIsEvictedFirst() throws {
        let max = SVGCache.s.maxCount
        let shared = try root(0)
        for i in 0..<max { SVGCache.s.set(md5: "k\(i)", object: shared) }
        XCTAssertNotNil(SVGCache.s.get(md5: "k0"))            // refresh k0: now k1 is the oldest
        SVGCache.s.set(md5: "new", object: shared)            // evicts exactly one entry
        XCTAssertNotNil(SVGCache.s.get(md5: "k0"), "a recently used entry survives")
        XCTAssertNil(SVGCache.s.get(md5: "k1"), "the least recently used entry is evicted")
        XCTAssertNotNil(SVGCache.s.get(md5: "new"))
        XCTAssertNotNil(SVGCache.s.get(md5: "k\(max - 1)"))
    }

    func testReplacingAnExistingKeyDoesNotEvict() throws {
        let max = SVGCache.s.maxCount
        let shared = try root(0)
        for i in 0..<max { SVGCache.s.set(md5: "k\(i)", object: shared) }
        SVGCache.s.set(md5: "k5", object: shared)
        for i in 0..<max { XCTAssertNotNil(SVGCache.s.get(md5: "k\(i)"), "k\(i) was evicted") }
    }

    func testConcurrentRendersOfSharedDocumentsAreStable() async throws {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 20 20\"><defs><linearGradient id=\"g\"><stop offset=\"0\" stop-color=\"#f00\"/><stop offset=\"1\" stop-color=\"#00f\"/></linearGradient></defs><rect width=\"20\" height=\"20\" fill=\"url(#g)\"/><text x=\"1\" y=\"10\">T</text></svg>"
        try await withThrowingTaskGroup(of: Int.self) { group in
            for i in 0..<24 {
                group.addTask {
                    let data = try await SVGRenderer.render(.string(svg, name: "stress-\(i % 3)"), size: CGSize(width: 20, height: 20), format: .png)
                    return data.count
                }
            }
            var sizes: [Int] = []
            for try await size in group { sizes.append(size) }
            XCTAssertEqual(sizes.count, 24)
            XCTAssertTrue(sizes.allSatisfy { $0 > 0 })
        }
    }
}
