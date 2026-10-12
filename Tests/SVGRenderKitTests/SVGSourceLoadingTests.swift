import XCTest
@testable import SVGRenderKit

final class SVGSourceLoadingTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        SVGCache.s.resetCache()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
        SVGCache.s.resetCache()
    }

    private func svg(width: Int) -> String {
        "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 \(width) 10\"><rect width=\"\(width)\" height=\"10\"/></svg>"
    }

    private func viewBoxWidth(_ parser: SVGParser) -> CGFloat {
        parser.root.getSvgOptions().viewBox.width
    }

    func testRewrittenFileAtSameURLIsReparsed() throws {
        let url = dir.appendingPathComponent("icon.svg")
        try svg(width: 10).write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(viewBoxWidth(try SVGParser.getParser(svgURL: url)), 10)

        try svg(width: 2000).write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(viewBoxWidth(try SVGParser.getParser(svgURL: url)), 2000)
    }

    func testSameNameDifferentURLsDoNotCollide() throws {
        let a = dir.appendingPathComponent("a.svg"), b = dir.appendingPathComponent("b.svg")
        try svg(width: 10).write(to: a, atomically: true, encoding: .utf8)
        try svg(width: 20).write(to: b, atomically: true, encoding: .utf8)
        XCTAssertEqual(viewBoxWidth(try SVGParser.getParser(svgURL: a, name: "n")), 10)
        XCTAssertEqual(viewBoxWidth(try SVGParser.getParser(svgURL: b, name: "n")), 20)
    }

    func testSetSVGNameFromCustomBundle() throws {
        let bundleURL = dir.appendingPathComponent("Res.bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        try svg(width: 10).write(to: bundleURL.appendingPathComponent("icon.svg"), atomically: true, encoding: .utf8)
        let bundle = try XCTUnwrap(Bundle(url: bundleURL))

        let view = SVGView(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
        view.set(SVGName: "icon.svg", bundle: bundle)
        let loaded = expectation(for: NSPredicate { _, _ in view.shapeLayer != nil }, evaluatedWith: nil)
        wait(for: [loaded], timeout: 5)
    }

    func testSetSVGURLRendersAndReloadsOnUpdate() throws {
        let url = dir.appendingPathComponent("icon.svg")
        try svg(width: 10).write(to: url, atomically: true, encoding: .utf8)

        let view = SVGView(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
        view.set(svgURL: url)
        wait(for: [expectation(for: NSPredicate { _, _ in view.parser != nil }, evaluatedWith: nil)], timeout: 5)
        XCTAssertEqual(viewBoxWidth(try XCTUnwrap(view.parser)), 10)

        try svg(width: 2000).write(to: url, atomically: true, encoding: .utf8)
        view.updateSvg()
        wait(for: [expectation(for: NSPredicate { _, _ in view.parser.map { self.viewBoxWidth($0) } == 2000 }, evaluatedWith: nil)], timeout: 5)
    }
}
