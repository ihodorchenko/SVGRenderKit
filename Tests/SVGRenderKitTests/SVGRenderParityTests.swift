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

    func testRendersMatchReference() throws {
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

    /// Triage harness: renders the entire Example icon corpus and prints a
    /// pass/fail summary. It does not hard-fail — out-of-scope features are
    /// expected to differ and are reported for triage, not as regressions.
    func testCorpusParity() throws {
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

        for fixture in fixtures {
            // CoreSVG (the parity oracle) does not implement `display:none`; it
            // renders elements that the spec — and our renderer — correctly hide.
            // Such fixtures cannot be validated against the reference, so they
            // are reported separately rather than as regressions.
            if ReferenceRenderer.unsupportedFeatures(in: fixture.svg).contains(.displayNone) {
                referenceLimited += 1
                lines.append("REF-LIMITED \(fixture.name) (display:none)")
                continue
            }

            guard let reference = ReferenceRenderer.render(fixture.svg, size: size) else {
                referenceMissing += 1
                lines.append("REF-MISSING \(fixture.name)")
                continue
            }
            guard let actual = try? KitRenderer.render(fixture.svg, size: size) else {
                kitError += 1
                lines.append("KIT-ERROR \(fixture.name)")
                continue
            }
            guard let cmp = ImageComparator.compare(actual, reference, size: size, tolerance: tolerance) else {
                kitError += 1
                lines.append("COMPARE-ERROR \(fixture.name)")
                continue
            }
            if cmp.passed(maxDifferingFraction: maxDifferingFraction) {
                pass += 1
            } else {
                fail += 1
                lines.append("FAIL \(fixture.name) differing=\(String(format: "%.3f", cmp.differingFraction)) maxDelta=\(cmp.maxChannelDelta) mae=\(String(format: "%.4f", cmp.meanAbsoluteError))")
            }
        }

        print("CORPUS_SUMMARY pass=\(pass) fail=\(fail) referenceMissing=\(referenceMissing) kitError=\(kitError) referenceLimited=\(referenceLimited) total=\(fixtures.count)")
        for line in lines {
            print("CORPUS_\(line)")
        }
    }
}
