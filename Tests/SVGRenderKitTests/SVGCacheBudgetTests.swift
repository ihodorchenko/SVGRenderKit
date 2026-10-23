import XCTest
@testable import SVGRenderKit

/// B133 (d, e, f) — cache memory accounting, the reset/parse race and the notification observer.
final class SVGCacheBudgetTests: XCTestCase {

    override func setUp() {
        super.setUp()
        SVGCache.s.isSVGParserUseCache = true
        SVGCache.s.resetCache()
    }

    override func tearDown() {
        SVGConfiguration.shared.updateNotificationName = nil
        SVGCache.s.resetCache()
        super.tearDown()
    }

    // MARK: d — byte budget

    func testBoundedCacheEvictsWhenTheByteBudgetIsExceeded() {
        let cache = SVGBoundedCache<Int, Int>(limit: 100, costLimit: 100, cost: { $0 })
        cache.set(60, for: 1)
        cache.set(30, for: 2)
        XCTAssertNotNil(cache.value(for: 1))
        XCTAssertNotNil(cache.value(for: 2))
        cache.set(50, for: 3)             // 140 > 100: clear, then store the newcomer
        XCTAssertNil(cache.value(for: 1))
        XCTAssertNil(cache.value(for: 2))
        XCTAssertEqual(cache.value(for: 3), 50)
    }

    func testOversizedValueIsStillCachedAlone() {
        let cache = SVGBoundedCache<Int, Int>(limit: 100, costLimit: 100, cost: { $0 })
        cache.set(10, for: 1)
        cache.set(500, for: 2)
        XCTAssertNil(cache.value(for: 1))
        XCTAssertEqual(cache.value(for: 2), 500, "a hit behaves as without a budget")
    }

    func testReplacingAKeyReleasesItsCost() {
        let cache = SVGBoundedCache<Int, Int>(limit: 100, costLimit: 100, cost: { $0 })
        cache.set(90, for: 1)
        cache.set(90, for: 1)
        cache.set(5, for: 2)
        XCTAssertEqual(cache.value(for: 1), 90, "the old 90 must not be counted twice")
        XCTAssertEqual(cache.value(for: 2), 5)
    }

    func testCacheWithoutCostBehavesAsBefore() {
        let cache = SVGBoundedCache<Int, Int>(limit: 2)
        cache.set(1, for: 1)
        cache.set(2, for: 2)
        cache.set(3, for: 3)              // count limit: clear on overflow
        XCTAssertNil(cache.value(for: 1))
        XCTAssertEqual(cache.value(for: 3), 3)
    }

    // MARK: e — a parse that straddles resetCache()

    func testStaleParseIsNotStoredAfterReset() throws {
        let root = try XCTUnwrap(SVGParser(svgString: "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 1 1\"/>", parsedRoot: nil).root)
        let generation = SVGCache.s.generation          // a parse starts here …
        SVGConfiguration.shared.addColorOverrides(["red": "#00f"])   // … override colors change: resetCache()
        SVGCache.s.set(md5: "stale", object: root, generation: generation)   // … and it finishes
        XCTAssertNil(SVGCache.s.get(md5: "stale"), "the tree was built with the old colors")

        SVGCache.s.set(md5: "fresh", object: root, generation: SVGCache.s.generation)
        XCTAssertNotNil(SVGCache.s.get(md5: "fresh"))
        SVGConfiguration.shared.setColorOverrides([:])
    }

    // MARK: f — the old notification observer is removed

    func testChangingTheNotificationNameDropsTheOldObserver() throws {
        let root = try XCTUnwrap(SVGParser(svgString: "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 1 1\"/>", parsedRoot: nil).root)
        let first = Notification.Name("b133.first"), second = Notification.Name("b133.second")
        SVGConfiguration.shared.updateNotificationName = first
        SVGConfiguration.shared.updateNotificationName = second

        SVGCache.s.set(md5: "k", object: root)
        NotificationCenter.default.post(name: first, object: nil)
        XCTAssertNotNil(SVGCache.s.get(md5: "k"), "the replaced name must not reset the cache any more")
        NotificationCenter.default.post(name: second, object: nil)
        XCTAssertNil(SVGCache.s.get(md5: "k"))
    }
}
