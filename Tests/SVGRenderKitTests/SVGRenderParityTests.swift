import XCTest
import UIKit
@testable import SVGRenderKit

/// Renders each fixture with the reference renderer (Apple's CoreSVG) and
/// `SVGView` (under test) on the fly, then compares the two rasters within a
/// tolerance.
///
/// No golden PNGs are committed; the reference is produced at test time to keep
/// the repository small.
final class SVGRenderParityTests: XCTestCase {

    private let size = CGSize(width: 256, height: 256)
    /// Per-channel tolerance (0...255). Absorbs anti-aliasing / rasterizer noise
    /// between the two render paths.
    private let tolerance = 16
    /// Maximum allowed fraction of pixels that may differ.
    private let maxDifferingFraction = 0.02

    @MainActor func testRendersMatchReference() throws {
        // Probe the reference renderer once; skip if CoreSVG is unavailable here.
        let probeSVG = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
            <rect width="10" height="10" fill="#ff0000"/>
        </svg>
        """
        if let probe = ReferenceRenderer.render(probeSVG, size: size),
           ImageComparator.hasOpaquePixels(probe) {
            // Reference renderer is available.
        } else {
            throw XCTSkip("CoreSVG reference rendering is unavailable in this environment")
        }

        for fixture in ParityFixtures.all {
            try XCTContext.runActivity(named: fixture.name) { activity in
                guard let reference = ReferenceRenderer.render(fixture.svg, size: size) else {
                    XCTFail("[\(fixture.name)] failed to produce reference render")
                    return
                }
                let actual = try KitRenderer.render(fixture.svg, size: size)

                guard let comparison = ImageComparator.compare(actual, reference, size: size, tolerance: tolerance) else {
                    XCTFail("[\(fixture.name)] failed to rasterize images for comparison")
                    return
                }

                activity.add(XCTAttachment(image: actual))
                activity.add(XCTAttachment(image: reference))
                XCTAssertTrue(
                    comparison.passed(maxDifferingFraction: maxDifferingFraction),
                    "[\(fixture.name)] differing=\(String(format: "%.3f", comparison.differingFraction)) "
                        + "(\(comparison.differingPixelCount)/\(comparison.totalPixelCount)) "
                        + "maxDelta=\(comparison.maxChannelDelta) "
                        + "mae=\(String(format: "%.4f", comparison.meanAbsoluteError))"
                )
            }
        }
    }

    /// Renders the entire Example icon corpus against CoreSVG, prints an annotated
    /// pass/fail report, and gates on regressions: no kit crashes, no reference
    /// parse failures, and every divergence must be accounted for in
    /// `ParityTriage.reasons` (known limitations). New/unknown failures fail the
    /// build so a regression can't slip in silently.
    @MainActor func testCorpusParity() throws {
        let fixtures = CorpusLoader.load()
        guard !fixtures.isEmpty else {
            throw XCTSkip("No SVG corpus found under Example/Example/data")
        }

        let probeSVG = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
            <rect width="10" height="10" fill="#ff0000"/>
        </svg>
        """
        let probeOK = ReferenceRenderer.render(probeSVG, size: size).map { ImageComparator.hasOpaquePixels($0) } ?? false
        guard probeOK else {
            throw XCTSkip("CoreSVG reference rendering is unavailable in this environment")
        }

        var pass = 0, fail = 0, referenceMissing = 0, kitError = 0, referenceLimited = 0
        var lines: [String] = []
        var kitErrorNames: [String] = []
        var referenceMissingNames: [String] = []
        var unexpectedFailures: [String] = []

        for fixture in fixtures {
            // CoreSVG (the parity oracle) does not implement a few SVG 1.1 features
            // (`display:none`, `<switch>`); our renderer handles them per spec, so
            // such fixtures can't be validated against the reference and are
            // reported separately rather than as regressions.
            let unsupported = ReferenceRenderer.unsupportedFeatures(in: fixture.svg)
            if !unsupported.isEmpty {
                referenceLimited += 1
                let reason = unsupported.map { feature -> String in
                    switch feature {
                    case .displayNone: return "display:none"
                    case .switchElement: return "<switch>"
                    }
                }.joined(separator: ", ")
                lines.append("REF-LIMITED \(fixture.name) (\(reason) — not implemented by CoreSVG)")
                continue
            }

            guard let reference = ReferenceRenderer.render(fixture.svg, size: size) else {
                referenceMissing += 1
                referenceMissingNames.append(fixture.name)
                lines.append("REF-MISSING \(fixture.name)")
                continue
            }
            guard let actual = try? KitRenderer.render(fixture.svg, size: size) else {
                kitError += 1
                kitErrorNames.append(fixture.name)
                lines.append("KIT-ERROR \(fixture.name)")
                continue
            }
            guard let cmp = ImageComparator.compare(actual, reference, size: size, tolerance: tolerance) else {
                kitError += 1
                kitErrorNames.append(fixture.name)
                lines.append("COMPARE-ERROR \(fixture.name)")
                continue
            }
            if cmp.passed(maxDifferingFraction: maxDifferingFraction) {
                pass += 1
            } else {
                fail += 1
                let reason = ParityTriage.reason(for: fixture.name)
                if reason == nil {
                    unexpectedFailures.append(fixture.name)
                }
                let annotation = reason ?? "unknown (add to ParityTriage.reasons)"
                lines.append("FAIL \(fixture.name) differing=\(String(format: "%.3f", cmp.differingFraction)) maxDelta=\(cmp.maxChannelDelta) mae=\(String(format: "%.4f", cmp.meanAbsoluteError)) — \(annotation)")
            }
        }

        // Report (always emitted, informational).
        print("CORPUS_SUMMARY pass=\(pass) fail=\(fail) referenceMissing=\(referenceMissing) kitError=\(kitError) referenceLimited=\(referenceLimited) total=\(fixtures.count)")
        for line in lines {
            print("CORPUS_\(line)")
        }

        // Gate (hard): a regression is a crash, a reference parse failure, or a
        // divergence not accounted for in ParityTriage.reasons.
        XCTAssertEqual(kitError, 0, "RenderKit crashed/failed on: \(kitErrorNames)")
        XCTAssertEqual(referenceMissing, 0, "CoreSVG could not parse: \(referenceMissingNames)")
        XCTAssertTrue(
            unexpectedFailures.isEmpty,
            "Unexpected parity regressions (not in ParityTriage.reasons): \(unexpectedFailures)"
        )
    }
}
