import XCTest
@testable import SVGRenderKit

/// Animated documents are not pixel fixtures: there is no single "correct" static frame of them.
/// CoreSVG ignores CSS animations and draws the base state, the WebKit oracle draws the
/// SVG-as-image into a canvas at an arbitrary moment of the timeline, and the kit rasters its own
/// model state — the three answers disagree by design. `CorpusLoader` therefore leaves such
/// documents out of the corpus, so a demo icon shown in the Example gallery never moves the parity
/// counts.
final class ParityCorpusAnimationTests: XCTestCase {

    func testDetectsSmilAndCssAnimation() {
        // SMIL animation elements.
        XCTAssertTrue(CorpusLoader.hasRenderingAnimation(
            #"<svg><rect width="1" height="1"><animate attributeName="opacity" from="0" to="1" dur="1s"/></rect></svg>"#))
        XCTAssertTrue(CorpusLoader.hasRenderingAnimation(
            #"<svg><g><animateTransform attributeName="transform" type="translate" values="0 0;10 0" dur="1s"/></g></svg>"#))
        XCTAssertTrue(CorpusLoader.hasRenderingAnimation(
            #"<svg><rect width="1" height="1"><set attributeName="opacity" to="0"/></rect></svg>"#))
        // CSS animations, in a stylesheet or inline.
        XCTAssertTrue(CorpusLoader.hasRenderingAnimation(
            #"<svg><style>@keyframes fade { from { opacity: 0 } }</style></svg>"#))
        XCTAssertTrue(CorpusLoader.hasRenderingAnimation(
            #"<svg><rect width="1" height="1" style="animation: fade .6s ease-out both"/></svg>"#))
        XCTAssertTrue(CorpusLoader.hasRenderingAnimation(
            #"<svg><rect width="1" height="1" style="animation-name: fade"/></svg>"#))
        // A static document has none of it.
        XCTAssertFalse(CorpusLoader.hasRenderingAnimation(
            ##"<svg><rect width="1" height="1" fill="#f00"/></svg>"##))
    }

    func testCorpusContainsNoAnimatedDocuments() {
        let animated = CorpusLoader.load().filter { CorpusLoader.hasRenderingAnimation($0.svg) }
        XCTAssertTrue(
            animated.isEmpty,
            "animated documents are not pixel fixtures and must be skipped by CorpusLoader: \(animated.map(\.name))")
    }

    func testLoadSkipsAnimatedDocumentsInADirectory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("animated-corpus-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("folder"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try ##"<svg viewBox="0 0 10 10"><rect width="10" height="10" fill="#f00"/></svg>"##
            .write(to: directory.appendingPathComponent("folder/static.svg"), atomically: true, encoding: .utf8)
        try ##"<svg viewBox="0 0 10 10"><rect width="10" height="10" fill="#f00"><animate attributeName="opacity" from="0" to="1" dur="1s"/></rect></svg>"##
            .write(to: directory.appendingPathComponent("folder/animated.svg"), atomically: true, encoding: .utf8)
        try #"<svg viewBox="0 0 10 10"><style>@keyframes fade{from{opacity:0}}</style><rect width="10" height="10"/></svg>"#
            .write(to: directory.appendingPathComponent("css-animated.svg"), atomically: true, encoding: .utf8)

        let fixtures = CorpusLoader.load(directory: directory)

        XCTAssertEqual(fixtures.map(\.name), ["folder/static.svg"],
                       "only static documents belong to the pixel corpus")
    }
}
