import XCTest
import SwiftUI
@testable import SVGRenderKit
import SVGRenderKitSwiftUI

/// Hosts `SVGImageView` in a real window and inspects the `SVGView` SwiftUI creates for it.
@MainActor
final class SVGImageViewTests: XCTestCase {

    private let markup = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 10 10\"><rect id=\"box\" width=\"10\" height=\"10\"/></svg>"

    private var window: UIWindow!
    private var host: UIHostingController<SVGImageView>!

    override func setUpWithError() throws {
        try super.setUpWithError()
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("SwiftUI hosting tests need an application host on Mac Catalyst")
        #endif
    }

    override func tearDown() async throws {
        window?.isHidden = true
        window = nil
        host = nil
        try await super.tearDown()
    }

    private func show(_ view: SVGImageView) -> SVGView {
        host = UIHostingController(rootView: view)
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        return findSVGView(in: host.view)!
    }

    private func update(_ view: SVGImageView) {
        host.rootView = view
        host.view.layoutIfNeeded()
    }

    private func findSVGView(in view: UIView) -> SVGView? {
        if let svg = view as? SVGView { return svg }
        for sub in view.subviews { if let found = findSVGView(in: sub) { return found } }
        return nil
    }

    private func waitUntil(_ timeout: TimeInterval = 5, _ condition: @escaping () -> Bool) {
        wait(for: [expectation(for: NSPredicate { _, _ in condition() }, evaluatedWith: nil)], timeout: timeout)
    }

    func testRendersSvgString() {
        let view = show(SVGImageView(svgString: markup))

        waitUntil { view.contentView.layer.sublayers?.isEmpty == false }
        XCTAssertEqual(view.svgString, markup)
    }

    func testChangedSourceReloadsView() {
        let view = show(SVGImageView(svgString: markup))
        waitUntil { view.contentView.layer.sublayers?.isEmpty == false }

        let other = markup.replacingOccurrences(of: "0 0 10 10", with: "0 0 20 20")
        update(SVGImageView(svgString: other))

        XCTAssertEqual(view.svgString, other)
    }

    func testUnchangedRedrawDoesNotReload() {
        let view = show(SVGImageView(svgString: markup))
        waitUntil { view.contentView.layer.sublayers?.isEmpty == false }
        let layer = view.shapeLayer

        update(SVGImageView(svgString: markup))
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        XCTAssertTrue(view.shapeLayer === layer, "an identical source must not re-parse the document")
    }

    func testFillColorsChangeReloadsView() {
        let view = show(SVGImageView(svgString: markup, fillColors: ["box": .red]))
        waitUntil { view.shapeLayer != nil }
        let layer = view.shapeLayer

        update(SVGImageView(svgString: markup, fillColors: ["box": .blue]))

        waitUntil { view.shapeLayer != nil && view.shapeLayer !== layer }
    }
}
