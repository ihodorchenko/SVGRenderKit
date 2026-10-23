import XCTest
import UIKit
@testable import SVGRenderKit

/// The browser oracle's dump reader (B122).
///
/// The rasters themselves are produced by the Example app (`WebKitParityRunner`), so what can be
/// tested here is the reading: fixture names come out relative to the dump directory, the
/// browser's recorded failures keep their reason, and a missing directory degrades into "no
/// rasters" (the oracle then reports every fixture as missing) instead of throwing.
final class WebKitReferenceRastersTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("webkit-rasters-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("folder_2/folder"),
                                               withIntermediateDirectories: true)
        try png().write(to: directory.appendingPathComponent("folder_2/folder/icon.svg.png"))
        try png().write(to: directory.appendingPathComponent("top.svg.png"))
        // Not a `.png` and not a raster: it must be ignored rather than reported as a fixture.
        try "noise".write(to: directory.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        try "folder_3/broken.svg\tthe browser did not load the document"
            .write(to: directory.appendingPathComponent("failures.tsv"), atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testLoadsRastersUnderTheirFixtureNames() throws {
        let loaded = WebKitReferenceRasters.load(from: directory)

        XCTAssertEqual(loaded.images.keys.sorted(), ["folder_2/folder/icon.svg", "top.svg"])
        XCTAssertEqual((loaded.images["folder_2/folder/icon.svg"].flatMap { UIImage(data: $0) })?.size,
                       CGSize(width: 4, height: 4))
        XCTAssertEqual(loaded.failures, ["folder_3/broken.svg": "the browser did not load the document"])
    }

    func testMissingDirectoryYieldsNoRasters() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("webkit-rasters-missing-\(UUID().uuidString)", isDirectory: true)

        let loaded = WebKitReferenceRasters.load(from: missing)

        XCTAssertTrue(loaded.images.isEmpty)
        XCTAssertTrue(loaded.failures.isEmpty)
    }

    /// The rasters are named relative to the dump directory, and that path is often reached through
    /// a symlink (`/tmp` is a symlink to `/private/tmp`): naming them with a plain string prefix
    /// test against the *unresolved* paths silently dropped every raster, so the reader resolves
    /// both sides before matching.
    func testLoadsRastersThroughASymlinkedDirectory() throws {
        let real = FileManager.default.temporaryDirectory
            .appendingPathComponent("webkit-rasters-real-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: real) }
        let dump = real.appendingPathComponent("dump", isDirectory: true)
        try FileManager.default.createDirectory(at: dump.appendingPathComponent("folder_2"), withIntermediateDirectories: true)
        try png().write(to: dump.appendingPathComponent("folder_2/icon.svg.png"))

        // `link/dump` is the same directory as `real/dump`, but only the symlink is announced.
        let link = FileManager.default.temporaryDirectory
            .appendingPathComponent("webkit-rasters-link-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        defer { try? FileManager.default.removeItem(at: link) }

        let loaded = WebKitReferenceRasters.load(from: link.appendingPathComponent("dump", isDirectory: true))

        XCTAssertEqual(loaded.images.keys.sorted(), ["folder_2/icon.svg"])
    }

    private func png() -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4), format: format).pngData { context in
            context.cgContext.setFillColor(UIColor.red.cgColor)
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }
}
