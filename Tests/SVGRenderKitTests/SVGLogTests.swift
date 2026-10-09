import XCTest
@testable import SVGRenderKit

final class SVGLogTests: XCTestCase {

    override func tearDown() {
        super.tearDown()
        SVGLog.logger = PrintSVGLogger()
    }

    func testCustomLoggerReceivesMessages() {
        final class TestLogger: SVGLogger {
            var messages: [String] = []
            func log(_ message: String) {
                messages.append(message)
            }
        }

        let logger = TestLogger()
        SVGLog.logger = logger

        SVGLog.addSLog(errorStr: "boom")

        XCTAssertEqual(logger.messages, ["Error SVG: boom"])
    }
}
