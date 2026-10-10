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
}
