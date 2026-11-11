import XCTest
@testable import SVGRenderKit

/// M4 animation frame oracle: compares the kit and browser rasters dumped by the Example app
/// (`AnimationOracleRunner`, `Scripts/animation-oracle.sh`) and prints per-frame numbers.
///
/// Report-only by design: the browser is the reference, but the kit's known divergences (matrix
/// decomposition, color interpolation) are expected to show up as non-zero numbers. The CI gate
/// stays the trajectory tests; this harness is for "does it look like the browser".
final class SVGAnimationFrameOracleTests: XCTestCase {

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    func testAnimationFrameReport() throws {
        guard let directory = Self.dumpDirectory() else {
            throw XCTSkip("no animation oracle dump (run Scripts/animation-oracle.sh)")
        }
        let manifestURL = directory.appendingPathComponent("manifest.json")
        guard let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
              let fixtures = manifest["fixtures"] as? [String],
              let times = manifest["times"] as? [Double],
              let size = manifest["size"] as? [Int], size.count == 2 else {
            XCTFail("cannot read \(manifestURL.path)")
            return
        }
        let pixelSize = size[0]
        var frameCount = 0
        var totalError = 0.0
        var maxError = 0.0
        var missing: [String] = []

        for fixture in fixtures {
            for (index, time) in times.enumerated() {
                let kitURL = directory.appendingPathComponent("kit/\(fixture)/\(index).png")
                let webURL = directory.appendingPathComponent("web/\(fixture)/\(index).png")
                guard let kitImage = UIImage(contentsOfFile: kitURL.path),
                      let webImage = UIImage(contentsOfFile: webURL.path),
                      let kitPixels = Self.pixels(kitImage, size: pixelSize),
                      let webPixels = Self.pixels(webImage, size: pixelSize),
                      kitPixels.count == webPixels.count else {
                    missing.append("\(fixture)@\(time)")
                    continue
                }
                var differing = 0
                var error = 0.0
                let pixelCount = pixelSize * pixelSize
                for pixel in 0..<pixelCount {
                    var pixelDiff = 0
                    for channel in 0..<3 {
                        let offset = pixel * 4 + channel
                        let delta = abs(Int(kitPixels[offset]) - Int(webPixels[offset]))
                        pixelDiff = max(pixelDiff, delta)
                        error += Double(delta) / 255.0
                    }
                    if pixelDiff > 8 { differing += 1 }
                }
                let fraction = Double(differing) / Double(pixelCount)
                let mean = error / Double(pixelCount * 3)
                totalError += mean
                maxError = max(maxError, mean)
                frameCount += 1
                print("ANIMATION_FRAME \(fixture) t=\(time) differing=\(String(format: "%.4f", fraction)) "
                    + "mean=\(String(format: "%.4f", mean))")
            }
        }
        if !missing.isEmpty {
            print("ANIMATION_FRAME_MISSING \(missing.joined(separator: " "))")
        }
        let average = frameCount > 0 ? totalError / Double(frameCount) : 0
        print("ANIMATION_FRAME_SUMMARY fixtures=\(fixtures.count) frames=\(frameCount) "
            + "mean=\(String(format: "%.4f", average)) max=\(String(format: "%.4f", maxError)) "
            + "missing=\(missing.count)")
        XCTAssertTrue(missing.isEmpty, "the dump is incomplete: \(missing.joined(separator: ", "))")
    }

    // MARK: - Helpers

    private static func dumpDirectory() -> URL? {
        if let path = ProcessInfo.processInfo.environment["SVGRENDERKIT_ANIMATION_RASTERS"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        let pointer = repositoryRoot.appendingPathComponent(".animation-rasters")
        guard let path = try? String(contentsOf: pointer, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// The image drawn onto an opaque white canvas at a fixed size, as RGBA bytes.
    private static func pixels(_ image: UIImage, size: Int) -> [UInt8]? {
        guard let cgImage = image.cgImage else { return nil }
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: &bytes, width: size, height: size, bitsPerComponent: 8,
                                      bytesPerRow: size * 4, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))
        return bytes
    }
}
