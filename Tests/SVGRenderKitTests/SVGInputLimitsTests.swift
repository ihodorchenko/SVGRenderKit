import XCTest
import UIKit
@testable import SVGRenderKit

/// B102 — limits on untrusted input. A document must not be able to hang the parser
/// (deep nesting, `<use>` cycles in `contentBounds`) or exhaust memory (`<use>` fan-out,
/// unbounded mask/pattern/render bitmaps).
final class SVGInputLimitsTests: XCTestCase {

    private final class CapturingLogger: SVGLogger {
        var messages: [String] = []
        func log(_ message: String) {
            messages.append(message)
        }
    }

    override func tearDown() {
        super.tearDown()
        SVGLog.logger = PrintSVGLogger()
    }

    private func captureLog() -> CapturingLogger {
        let logger = CapturingLogger()
        SVGLog.logger = logger
        return logger
    }

    private func maxGroupDepth(_ group: SVGGroupObject, _ depth: Int) -> Int {
        var result = depth
        for element in group.layerElements.array {
            if let child = element as? SVGGroupObject {
                result = max(result, maxGroupDepth(child, depth + 1))
            }
        }
        return result
    }

    private func countLayers(_ layer: CALayer) -> Int {
        (layer.sublayers ?? []).reduce(1) { $0 + countLayers($1) }
    }

    // MARK: - Nesting depth

    func testDeepNestingIsCapped() throws {
        let depth = SVGInputLimits.maxNestingDepth + 50
        var svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\">"
        svg += String(repeating: "<g>", count: depth)
        svg += "<rect width=\"10\" height=\"10\" fill=\"#000000\"/>"
        svg += String(repeating: "</g>", count: depth)
        svg += "</svg>"

        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let root = try XCTUnwrap(parser.root)
        XCTAssertLessThanOrEqual(maxGroupDepth(root.svgElement, 0), SVGInputLimits.maxNestingDepth)
    }

    func testNormalNestingIsUntouched() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <g><g><g><rect width="10" height="10" fill="#000000"/></g></g></g>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let root = try XCTUnwrap(parser.root)
        XCTAssertEqual(maxGroupDepth(root.svgElement, 0), 3)
    }

    // MARK: - <use> expansion budget

    func testUseFanOutIsCapped() throws {
        var defs = "<g id=\"l0\"><rect width=\"1\" height=\"1\" fill=\"#000000\"/></g>"
        for level in 1...14 {
            defs += "<g id=\"l\(level)\"><use href=\"#l\(level - 1)\"/><use href=\"#l\(level - 1)\"/></g>"
        }
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs>\(defs)</defs>
            <use href="#l14"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        // Unbounded this is ~2^15 layers (a DAG fan-out, not a cycle).
        XCTAssertLessThanOrEqual(countLayers(layer), 1 << (SVGInputLimits.maxUseDepth + 3))
    }

    func testModestUseFanOutIsUntouched() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <defs><g id="a"><rect width="1" height="1" fill="#000000"/></g></defs>
            <use href="#a"/><use href="#a"/><use href="#a"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        // Three uses + three referenced rects, all present.
        XCTAssertEqual(countLayers(layer), 10)
    }

    func testUseCycleIsDetectedAndSkipped() throws {
        // B102 detects the cycle; B119-5 made it degrade instead of failing the whole
        // document — the cyclic `<use>` is logged and dropped, the rest still renders.
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <g id="a"><use href="#a"/></g>
            <rect width="1" height="1" fill="#000000"/>
        </svg>
        """
        let log = captureLog()
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        XCTAssertTrue(log.messages.contains { $0.contains("circular reference") },
                      "the cycle must still be reported: \(log.messages)")
        XCTAssertGreaterThan(countLayers(layer), 1, "the rest of the document must render")
    }

    // MARK: - contentBounds recursion

    func testSelfReferencingUseInContentBoundsTerminates() throws {
        // The `<use>` sits under a `display:none` group, so `createLayer`'s cycle guard
        // never sees it, but the `contentBounds` walk still reaches the referencing
        // `<use>` — and, without a guard, recurses forever.
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <mask id="m"><rect width="1" height="1" fill="#ffffff"/></mask>
            <g id="a" mask="url(#m)">
                <g display="none"><use href="#a"/></g>
            </g>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let root = try XCTUnwrap(parser.root)
        let groupA = try XCTUnwrap(root.svgElement.layerElements.array.compactMap { $0 as? SVGGTag }.first)

        XCTAssertFalse(groupA.contentBounds.isNull)
        XCTAssertNoThrow(try parser.getLayer(overrideElements: nil))
    }

    // MARK: - Bitmap size caps

    func testOversizedMaskIsSkippedWithLog() throws {
        let logger = captureLog()
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <mask id="m" maskUnits="userSpaceOnUse" width="5000" height="20">
                <rect width="1" height="1" fill="#ffffff"/>
            </mask>
            <rect width="50" height="50" fill="#ff0000" mask="url(#m)"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        XCTAssertNotNil(layer)
        XCTAssertTrue(logger.messages.contains { $0.contains("skipped mask") },
                      "expected an oversized mask to be skipped, got \(logger.messages)")
    }

    func testOversizedPatternIsSkippedWithLog() throws {
        let logger = captureLog()
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <pattern id="p" patternUnits="userSpaceOnUse" width="5000" height="20">
                <rect width="10" height="10" fill="#00ff00"/>
            </pattern>
            <rect width="50" height="50" fill="url(#p)"/>
        </svg>
        """
        let parser = try SVGParser(svgString: svg, parsedRoot: nil)
        let layer = try parser.getLayer(overrideElements: nil)
        XCTAssertNotNil(layer)
        XCTAssertTrue(logger.messages.contains { $0.contains("skipped pattern") },
                      "expected an oversized pattern to be skipped, got \(logger.messages)")
    }

    func testRendererRejectsOversizedOutput() async {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            <rect width="100" height="100" fill="#000000"/>
        </svg>
        """
        do {
            _ = try await SVGRenderer.render(.string(svg), size: CGSize(width: 9000, height: 10))
            XCTFail("expected an oversized render to throw")
        } catch {
            // expected
        }
    }
}
