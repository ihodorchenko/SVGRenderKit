import XCTest
@testable import SVGRenderKit

final class SVGConfigurationTests: XCTestCase {

    override func tearDown() {
        super.tearDown()
        SVGConfiguration.shared.updateNotificationName = nil
        SVGConfiguration.shared.isParserCacheEnabled = true
    }

    func testUpdateNotificationNameWiresViews() {
        SVGConfiguration.shared.updateNotificationName = Notification.Name("test.themeChanged")
        XCTAssertNotNil(SVGView.updateNotificationName)

        SVGConfiguration.shared.updateNotificationName = nil
        XCTAssertNil(SVGView.updateNotificationName)
    }

    func testCacheEnabledDelegatesToConfiguration() {
        SVGConfiguration.shared.isParserCacheEnabled = false
        XCTAssertFalse(SVGCache.s.isSVGParserUseCache)

        SVGConfiguration.shared.isParserCacheEnabled = true
        XCTAssertTrue(SVGCache.s.isSVGParserUseCache)
    }
}
