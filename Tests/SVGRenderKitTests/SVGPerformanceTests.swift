import XCTest
@testable import SVGRenderKit

/// Performance benchmarks for parsing, layer building, rendering and `SVGView` creation.
///
/// Fixtures are generated in code (deterministically) so no resource files are needed. Each test
/// reports wall-clock time, CPU and memory; stage boundaries are also visible in Instruments as
/// `SVGSignpost` points of interest.
@MainActor
final class SVGPerformanceTests: XCTestCase {

    // MARK: - Setup

    private var savedCacheFlag = true

    override func setUp() {
        super.setUp()
        savedCacheFlag = SVGCache.s.isSVGParserUseCache
        SVGCache.s.resetCache()
    }

    override func tearDown() {
        SVGCache.s.isSVGParserUseCache = savedCacheFlag
        SVGCache.s.resetCache()
        super.tearDown()
    }

    private var options: XCTMeasureOptions {
        let opts = XCTMeasureOptions()
        opts.iterationCount = 5
        return opts
    }

    private var metrics: [XCTMetric] { [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()] }

    // MARK: - Fixtures

    /// Small deterministic linear congruential generator, so fixtures are identical on every run.
    private struct LCG {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state >> 33
        }
        /// A value in `0..<upper`.
        mutating func int(_ upper: Int) -> Int { Int(next() % UInt64(upper)) }
        /// A value in `0..<upper` with a fractional part.
        mutating func coord(_ upper: Int) -> String {
            String(format: "%.2f", Double(next() % UInt64(upper * 100)) / 100.0)
        }
        mutating func hex() -> String { String(format: "#%06x", Int(next() % 0xFFFFFF)) }
    }

    private static let icon = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
        <circle cx="12" cy="12" r="10" fill="#2196f3"/>
        <path d="M7 12l3 3 7-7" fill="none" stroke="#ffffff" stroke-width="2" stroke-linecap="round"/>
    </svg>
    """

    /// 60 paths, each with ~200 line/cubic/quadratic segments.
    private static let pathHeavyMap: String = {
        var rng = LCG(state: 1)
        var body = ""
        for _ in 0..<60 {
            var d = "M\(rng.coord(1000)) \(rng.coord(1000))"
            for _ in 0..<200 {
                switch rng.int(3) {
                case 0: d += " L\(rng.coord(1000)) \(rng.coord(1000))"
                case 1: d += " C\(rng.coord(1000)) \(rng.coord(1000)) \(rng.coord(1000)) \(rng.coord(1000)) \(rng.coord(1000)) \(rng.coord(1000))"
                default: d += " Q\(rng.coord(1000)) \(rng.coord(1000)) \(rng.coord(1000)) \(rng.coord(1000))"
                }
            }
            body += "<path d=\"\(d) Z\" fill=\"\(rng.hex())\" fill-opacity=\"0.3\" stroke=\"\(rng.hex())\" stroke-width=\"0.5\"/>\n"
        }
        return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 1000 1000\" width=\"1000\" height=\"1000\">\n\(body)</svg>"
    }()

    /// 100 shapes filled with 50 linear and 50 radial gradients.
    private static let gradientHeavy: String = {
        var rng = LCG(state: 2)
        var defs = ""
        var shapes = ""
        for i in 0..<50 {
            defs += """
            <linearGradient id="l\(i)" x1="0" y1="0" x2="1" y2="1">
                <stop offset="0" stop-color="\(rng.hex())"/><stop offset="0.5" stop-color="\(rng.hex())" stop-opacity="0.8"/><stop offset="1" stop-color="\(rng.hex())"/>
            </linearGradient>
            <radialGradient id="r\(i)" cx="0.5" cy="0.5" r="0.5">
                <stop offset="0" stop-color="\(rng.hex())"/><stop offset="0.6" stop-color="\(rng.hex())"/><stop offset="1" stop-color="\(rng.hex())" stop-opacity="0"/>
            </radialGradient>

            """
        }
        for i in 0..<100 {
            let id = i % 2 == 0 ? "l\(i / 2)" : "r\(i / 2)"
            let x = (i % 10) * 60 + 5, y = (i / 10) * 60 + 5
            shapes += i % 3 == 0
                ? "<circle cx=\"\(x + 25)\" cy=\"\(y + 25)\" r=\"25\" fill=\"url(#\(id))\"/>\n"
                : "<rect x=\"\(x)\" y=\"\(y)\" width=\"50\" height=\"50\" rx=\"6\" fill=\"url(#\(id))\"/>\n"
        }
        return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 600 600\" width=\"600\" height=\"600\"><defs>\n\(defs)</defs>\n\(shapes)</svg>"
    }()

    /// Several patterns and masks, each applied to a handful of shapes.
    private static let patternAndMask: String = {
        var rng = LCG(state: 3)
        var defs = ""
        var shapes = ""
        for i in 0..<5 {
            defs += """
            <pattern id="p\(i)" width="\(8 + i * 2)" height="\(8 + i * 2)" patternUnits="userSpaceOnUse">
                <rect width="\(8 + i * 2)" height="\(8 + i * 2)" fill="\(rng.hex())"/>
                <circle cx="4" cy="4" r="3" fill="\(rng.hex())"/>
            </pattern>
            <mask id="m\(i)"><rect width="200" height="200" fill="#ffffff"/><circle cx="100" cy="100" r="\(30 + i * 10)" fill="#000000"/></mask>

            """
        }
        for i in 0..<40 {
            let x = (i % 8) * 100, y = (i / 8) * 100
            shapes += "<rect x=\"\(x)\" y=\"\(y)\" width=\"90\" height=\"90\" fill=\"url(#p\(i % 5))\"/>\n"
            shapes += "<g transform=\"translate(\(x) \(y)) scale(0.45)\"><rect width=\"200\" height=\"200\" fill=\"\(rng.hex())\" mask=\"url(#m\(i % 5))\"/></g>\n"
        }
        return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 800 500\" width=\"800\" height=\"500\"><defs>\n\(defs)</defs>\n\(shapes)</svg>"
    }()

    /// A small PNG rendered at runtime, so the base64 payload is a real image.
    private static func base64PNG() -> String {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32))
        let data = renderer.pngData { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 8, y: 8, width: 16, height: 16))
        }
        return data.base64EncodedString()
    }

    /// One embedded raster image referenced by 100 `<use>` elements.
    private static let imageUse: String = {
        var uses = ""
        for i in 0..<100 {
            uses += "<use xlink:href=\"#img\" x=\"\((i % 10) * 40)\" y=\"\((i / 10) * 40)\"/>\n"
        }
        return """
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 400 400" width="400" height="400">
        <defs><g id="img"><image width="32" height="32" xlink:href="data:image/png;base64,\(base64PNG())"/></g></defs>
        \(uses)</svg>
        """
    }()

    /// 20 nested groups with 200 shapes inside the innermost one, each clipped.
    private static let nestedClip: String = {
        var rng = LCG(state: 5)
        var opening = "", closing = ""
        for i in 0..<20 {
            opening += "<g transform=\"translate(\(i % 3) \(i % 2))\" opacity=\"0.99\"\(i % 4 == 0 ? " clip-path=\"url(#c)\"" : "")>\n"
            closing += "</g>\n"
        }
        var shapes = ""
        for i in 0..<200 {
            let x = (i % 20) * 25, y = (i / 20) * 25
            shapes += "<rect x=\"\(x)\" y=\"\(y)\" width=\"20\" height=\"20\" fill=\"\(rng.hex())\" clip-path=\"url(#c)\"/>\n"
        }
        return """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 500 250" width="500" height="250">
        <defs><clipPath id="c"><circle cx="250" cy="125" r="400"/></clipPath></defs>
        \(opening)\(shapes)\(closing)</svg>
        """
    }()

    private var fixtures: [(name: String, svg: String)] {
        [("icon", Self.icon), ("pathHeavy", Self.pathHeavyMap), ("gradients", Self.gradientHeavy),
         ("patternMask", Self.patternAndMask), ("imageUse", Self.imageUse), ("nestedClip", Self.nestedClip)]
    }

    // MARK: - Helpers

    /// Parses `svg` without any cache involvement.
    private func coldParse(_ svg: String) {
        SVGCache.s.isSVGParserUseCache = false
        do {
            _ = try SVGParser.getParser(svgString: svg)
        } catch {
            XCTFail("parse failed: \(error)")
        }
    }

    private func measureColdParse(_ svg: String) {
        measure(metrics: metrics, options: options) {
            coldParse(svg)
        }
    }

    private func measureGetLayer(_ svg: String) throws {
        SVGCache.s.isSVGParserUseCache = false
        let parser = try SVGParser.getParser(svgString: svg)
        measure(metrics: metrics, options: options) {
            do {
                _ = try parser.getLayer(overrideElements: nil)
            } catch {
                XCTFail("getLayer failed: \(error)")
            }
        }
    }

    /// Box for passing a render result out of the `@Sendable` completion handler.
    private final class ResultBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _result: Result<Data, Error>?
        var result: Result<Data, Error>? {
            get { lock.lock(); defer { lock.unlock() }; return _result }
            set { lock.lock(); defer { lock.unlock() }; _result = newValue }
        }
    }

    /// Renders through the callback API and blocks until the completion handler fires.
    /// Safe on any thread except the library's work queue.
    private nonisolated static func renderBlocking(_ svg: String, scale: CGFloat, name: String?) -> Result<Data, Error> {
        let semaphore = DispatchSemaphore(value: 0)
        let box = ResultBox()
        SVGRenderer.render(.string(svg, name: name), format: .png, scale: scale) { result in
            box.result = result
            semaphore.signal()
        }
        semaphore.wait()
        return box.result ?? .failure(SVGError.unexpectedError(text: "no result"))
    }

    private func measureRender(_ svg: String, scale: CGFloat) {
        SVGCache.s.isSVGParserUseCache = false
        measure(metrics: metrics, options: options) {
            switch Self.renderBlocking(svg, scale: scale, name: nil) {
            case .success(let data): XCTAssertFalse(data.isEmpty)
            case .failure(let error): XCTFail("render failed: \(error)")
            }
        }
    }

    // MARK: - Cold parse

    func testPerf_coldParse_icon() { measureColdParse(Self.icon) }
    func testPerf_coldParse_pathHeavyMap() { measureColdParse(Self.pathHeavyMap) }
    // MARK: - Isolation (where does cold-parse time go?)
    // The pathHeavyMap fixture only emits absolute commands (M/L/C/Q/Z), so there is no
    // absolute-only / relative-only split.

    func testPerf_isolate_xmlParseOnly() {
        let svg = Self.pathHeavyMap
        measure(metrics: metrics, options: options) {
            _ = SWXMLHash.parse(svg)
        }
    }

    func testPerf_isolate_pathDataOnly() throws {
        let svg = Self.pathHeavyMap
        let regex = try NSRegularExpression(pattern: "\\sd=\"([^\"]*)\"")
        let ns = svg as NSString
        let ds = regex.matches(in: svg, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range(at: 1)) }
        XCTAssertEqual(ds.count, 60)
        measure(metrics: metrics, options: options) {
            for d in ds {
                _ = SVGParseString.parseSVGPath(pathString: d)
            }
        }
    }

    func testPerf_coldParse_gradientHeavy() { measureColdParse(Self.gradientHeavy) }
    func testPerf_coldParse_patternAndMask() { measureColdParse(Self.patternAndMask) }
    func testPerf_coldParse_imageUse() { measureColdParse(Self.imageUse) }
    func testPerf_coldParse_nestedClip() { measureColdParse(Self.nestedClip) }

    // MARK: - Warm cache

    /// A cache hit must skip the XML parse: 100 lookups of the same name and markup.
    func testPerf_warmCacheHit_pathHeavyMap() throws {
        SVGCache.s.isSVGParserUseCache = true
        SVGCache.s.resetCache()
        let svg = Self.pathHeavyMap
        _ = try SVGParser.getParser(svgString: svg, name: "perf-map") // primes the cache
        measure(metrics: metrics, options: options) {
            for _ in 0..<100 {
                do {
                    _ = try SVGParser.getParser(svgString: svg, name: "perf-map")
                } catch {
                    XCTFail("cache hit failed: \(error)")
                }
            }
        }
    }

    func testPerf_warmCacheHit_gradientHeavy() throws {
        SVGCache.s.isSVGParserUseCache = true
        SVGCache.s.resetCache()
        let svg = Self.gradientHeavy
        _ = try SVGParser.getParser(svgString: svg, name: "perf-gradients")
        measure(metrics: metrics, options: options) {
            for _ in 0..<100 {
                do {
                    _ = try SVGParser.getParser(svgString: svg, name: "perf-gradients")
                } catch {
                    XCTFail("cache hit failed: \(error)")
                }
            }
        }
    }

    // MARK: - Layer building only

    func testPerf_getLayer_icon() throws { try measureGetLayer(Self.icon) }
    func testPerf_getLayer_pathHeavyMap() throws { try measureGetLayer(Self.pathHeavyMap) }
    func testPerf_getLayer_gradientHeavy() throws { try measureGetLayer(Self.gradientHeavy) }
    func testPerf_getLayer_patternAndMask() throws { try measureGetLayer(Self.patternAndMask) }
    func testPerf_getLayer_imageUse() throws { try measureGetLayer(Self.imageUse) }
    func testPerf_getLayer_nestedClip() throws { try measureGetLayer(Self.nestedClip) }

    // MARK: - SVGRenderer PNG export

    func testPerf_renderPNG_1x_pathHeavyMap() { measureRender(Self.pathHeavyMap, scale: 1) }
    func testPerf_renderPNG_3x_pathHeavyMap() { measureRender(Self.pathHeavyMap, scale: 3) }
    func testPerf_renderPNG_1x_gradientHeavy() { measureRender(Self.gradientHeavy, scale: 1) }
    func testPerf_renderPNG_3x_gradientHeavy() { measureRender(Self.gradientHeavy, scale: 3) }
    func testPerf_renderPNG_1x_patternAndMask() { measureRender(Self.patternAndMask, scale: 1) }
    func testPerf_renderPNG_3x_patternAndMask() { measureRender(Self.patternAndMask, scale: 3) }
    func testPerf_renderPNG_1x_nestedClip() { measureRender(Self.nestedClip, scale: 1) }
    func testPerf_renderPNG_3x_nestedClip() { measureRender(Self.nestedClip, scale: 3) }

    // MARK: - Concurrency

    /// Counts failures from concurrent workers.
    private final class FailureCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func increment() { lock.lock(); count += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    }

    /// Submits `count` renders from concurrent threads and returns how many failed.
    private nonisolated static func concurrentRenders(_ svg: String, count: Int, name: String) -> Int {
        let failures = FailureCounter()
        DispatchQueue.concurrentPerform(iterations: count) { _ in
            if case .failure = renderBlocking(svg, scale: 1, name: name) { failures.increment() }
        }
        return failures.value
    }

    /// 50 renders submitted at once from concurrent threads (they serialize on the library's work queue).
    func testPerf_concurrentRender50_gradientHeavy() {
        SVGCache.s.isSVGParserUseCache = true
        let svg = Self.gradientHeavy
        measure(metrics: metrics, options: options) {
            SVGCache.s.resetCache()
            XCTAssertEqual(Self.concurrentRenders(svg, count: 50, name: "perf-concurrent"), 0)
        }
    }

    // MARK: - SVGView

    /// Creates 50 views, lays them out and waits until each has built its layer tree.
    func testPerf_svgViewCreateAndLayout50() {
        SVGCache.s.isSVGParserUseCache = true
        let svg = Self.gradientHeavy
        measure(metrics: metrics, options: options) {
            SVGCache.s.resetCache()
            var views: [SVGView] = []
            for _ in 0..<50 {
                let view = SVGView(frame: CGRect(x: 0, y: 0, width: 120, height: 120))
                view.set(svgString: svg, name: "perf-view")
                view.layoutIfNeeded()
                views.append(view)
            }
            let deadline = Date().addingTimeInterval(30)
            while views.contains(where: { $0.shapeLayer == nil }) && Date() < deadline {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            }
            for view in views { view.layoutIfNeeded() }
            XCTAssertFalse(views.contains { $0.shapeLayer == nil }, "some views did not finish loading")
        }
    }

    // MARK: - Corpus

    func testPerf_corpus_coldParse() throws {
        let corpus = CorpusLoader.load()
        try XCTSkipIf(corpus.isEmpty, "corpus is empty")
        SVGCache.s.isSVGParserUseCache = false
        var errors = 0
        measure(metrics: metrics, options: options) {
            errors = 0
            for fixture in corpus {
                do { _ = try SVGParser.getParser(svgString: fixture.svg) } catch { errors += 1 }
            }
        }
        print("corpus coldParse: \(corpus.count) files, \(errors) errors")
    }

    func testPerf_corpus_getLayer() throws {
        let corpus = CorpusLoader.load()
        try XCTSkipIf(corpus.isEmpty, "corpus is empty")
        SVGCache.s.isSVGParserUseCache = false
        let parsers = corpus.compactMap { try? SVGParser.getParser(svgString: $0.svg) }
        var errors = 0
        measure(metrics: metrics, options: options) {
            errors = 0
            for parser in parsers {
                do { _ = try parser.getLayer(overrideElements: nil) } catch { errors += 1 }
            }
        }
        print("corpus getLayer: \(parsers.count)/\(corpus.count) parsed, \(errors) errors")
    }

    func testPerf_corpus_xmlOnly() throws {
        let corpus = CorpusLoader.load()
        try XCTSkipIf(corpus.isEmpty, "corpus is empty")
        measure(metrics: metrics, options: options) {
            for fixture in corpus { _ = SWXMLHash.parse(fixture.svg) }
        }
    }
}
