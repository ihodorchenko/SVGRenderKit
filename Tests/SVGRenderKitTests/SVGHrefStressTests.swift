import XCTest
@testable import SVGRenderKit

/// B124 (б) — `resolveHref()` lazily writes to the shared, cached tree while layers are built.
/// Layer building is serialised on `SVGWorkQueue.shared` (SVGView loads and SVGRenderer both go
/// through it), so concurrent callers of the public API must still get identical results.
final class SVGHrefStressTests: XCTestCase {

    private let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">
      <rect width="10" height="20" fill="url(#top)"/>
      <rect x="10" width="10" height="20" fill="url(#rad)" stroke="url(#top)" stroke-width="2"/>
      <defs>
        <linearGradient id="top" xlink:href="#mid" x1="0" x2="1" y1="0" y2="0"/>
        <linearGradient id="mid" xlink:href="#base"/>
        <linearGradient id="base"><stop offset="0" stop-color="#f00"/><stop offset="1" stop-color="#00f"/></linearGradient>
        <radialGradient id="rad" xlink:href="#base" r="0.5"/>
      </defs>
    </svg>
    """

    func testConcurrentRendersOfAHrefChainAgree() async throws {
        let size = CGSize(width: 20, height: 20)
        let svg = self.svg
        let reference = try await SVGRenderer.render(.string(svg, name: nil), size: size, format: .png)
        XCTAssertGreaterThan(reference.count, 100)

        for round in 0..<6 {
            // A fresh name per round: the first renders of a document race to resolve its hrefs.
            let name = "href-stress-\(round)"
            let results = try await withThrowingTaskGroup(of: Data.self) { group -> [Data] in
                for _ in 0..<16 {
                    group.addTask { try await SVGRenderer.render(.string(svg, name: name), size: size, format: .png) }
                }
                return try await group.reduce(into: []) { $0.append($1) }
            }
            for data in results { XCTAssertEqual(data, reference, "round \(round): render differs from the serial one") }
        }
    }
}
