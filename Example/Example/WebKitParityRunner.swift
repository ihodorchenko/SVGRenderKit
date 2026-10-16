import UIKit
import WebKit

/// Produces the *browser* oracle for the corpus parity test (B122): renders the whole SVG corpus
/// with `WKWebView` and writes the rasters as PNGs, so the test bundle can judge the kit's raster
/// with a browser as well as with CoreSVG.
///
/// Why the browser lives in the app: WebKit's WebContent process refuses to start in a bare
/// unit-test bundle — on iOS 26 the logs show an `RBS` assertion that the target "does not have
/// entitlement com.apple.developer.web-browser-engine.*" — so the rasters have to be produced from
/// an app. `Scripts/webkit-parity.sh` drives this runner and then points
/// `SVGRenderParityTests.testCorpusParity` at the dump (`SVGRENDERKIT_WEBKIT_RASTERS=<dir>`), so
/// both oracles end up judging the very same kit raster.
///
/// Launch arguments: `-webkitParity <corpus-dir> [batch-size] [dump-dir]`. `AppDelegate` starts
/// the runner when the flag is present; the app exits when the corpus is done (0 = every fixture
/// was rendered, 1 = something is missing).
///
/// Layout: the kit draws a document by fitting its `viewBox` into the output box (`SVGOptions`
/// plus `SVGPreserveAspectRatio.resolve`), so the page is asked for exactly that — the root
/// `<svg>` tag gets an explicit intrinsic size equal to the fitted box (which also makes the
/// browser rasterize the vector at canvas resolution instead of upscaling a small intrinsic box),
/// and the box is drawn where the kit puts it. The corpus is `xMidYMid meet` throughout; other
/// alignments and `slice` are approximated, so a fixture that needs them must be triaged rather
/// than trusted.
@MainActor
enum WebKitParityRunner {

    /// The canvas every fixture is drawn into — must match the parity test's `size`.
    private static let size = CGSize(width: 256, height: 256)

    /// Wall-clock budget for the whole pass; a hostile page must not keep the app alive forever.
    private static let budget: TimeInterval = 600

    /// How many times a page that stopped answering is replaced before the pass gives up.
    private static let pageRetries = 3

    /// A reason a batch or a fixture has no browser raster.
    enum Failure: Error {
        case pageUnavailable(String)
        case unexpectedResult(String)
    }

    /// One fixture prepared for the browser: the markup with an intrinsic size equal to the box,
    /// and that box on the canvas.
    private struct Prepared {
        let name: String
        let markup: String
        let box: CGRect
    }

    /// What one batch produced.
    private struct Outcome {
        var images: [String: Data] = [:]
        var failures: [String: String] = [:]
        var sizeNotes: [String] = []

        mutating func merge(_ other: Outcome) {
            images.merge(other.images) { _, new in new }
            failures.merge(other.failures) { _, new in new }
            sizeNotes += other.sizeNotes
        }
    }

    // MARK: - Launch

    /// Starts the dump when the app was launched with `-webkitParity <corpus-dir>`; returns
    /// `false` for a normal launch.
    static func runIfRequested() -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-webkitParity") else { return false }
        let values = Array(arguments.dropFirst(flag + 1))
        guard let corpusPath = values.first, !corpusPath.isEmpty else {
            print("WEBKIT_PARITY_ERROR usage: -webkitParity <corpus-dir> [batch-size] [dump-dir]")
            exit(2)
        }
        let batchSize = values.count > 1 ? max(1, Int(values[1]) ?? 5) : 5
        let dumpDirectory = values.count > 2
            ? URL(fileURLWithPath: values[2], isDirectory: true)
            : FileManager.default.temporaryDirectory.appendingPathComponent("svgrkit-webkit-rasters", isDirectory: true)

        Task {
            let failures = await dump(corpus: URL(fileURLWithPath: corpusPath, isDirectory: true),
                                      into: dumpDirectory,
                                      batchSize: batchSize)
            fflush(stdout)
            exit(failures == 0 ? 0 : 1)
        }
        return true
    }

    // MARK: - The pass

    /// Renders every `.svg` under `corpus` and writes each raster into `directory` as
    /// `<fixture name>.png`, preserving subdirectories. Returns the number of fixtures without a
    /// raster (the browser could not load the document, or the page stopped answering).
    private static func dump(corpus: URL, into directory: URL, batchSize: Int) async -> Int {
        let fixtures = loadCorpus(corpus)
        guard !fixtures.isEmpty else {
            print("WEBKIT_PARITY_ERROR no .svg under \(corpus.path)")
            return 1
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            print("WEBKIT_PARITY_ERROR cannot create \(directory.path): \(error)")
            return 1
        }

        let prepared = fixtures.map { prepare(name: $0.name, svg: $0.svg, canvas: size) }
        print("WEBKIT_DUMP_DIR \(directory.path)")
        print("WEBKIT_DUMP_START fixtures=\(prepared.count) batch=\(batchSize) canvas=\(Int(size.width))x\(Int(size.height))")

        let deadline = Date().addingTimeInterval(budget)
        let started = Date()
        var page = Page(size: size)
        var failures: [String: String] = [:]
        var dumped = 0
        var retries = 0
        var done = 0
        var pageGaveUp = false

        for batch in chunks(prepared, size: batchSize) {
            if pageGaveUp {
                // A page that keeps dying cannot be revived; the rest of the corpus would only cost
                // timeouts, so the pass ends here and the summary says what is missing.
                for fixture in batch { failures[fixture.name] = "the browser page kept dying" }
                done += batch.count
                continue
            }
            if Date() > deadline {
                for fixture in batch { failures[fixture.name] = "the browser pass exceeded its \(Int(budget))s budget" }
                done += batch.count
                continue
            }
            var outcome = await page.render(batch)
            if outcome.failures.count == batch.count {
                // Nothing in the batch answered: the page itself is dead (a fixture that only
                // poisons its own batch is isolated by `Page.render`), so replace it and retry —
                // up to `pageRetries` times, after which the pass stops.
                if retries < pageRetries {
                    retries += 1
                    print("WEBKIT_DUMP_PAGE_RESTART \(retries) — the batch answered nothing")
                    page = Page(size: size)
                    outcome = await page.render(batch)
                }
                if outcome.failures.count == batch.count {
                    pageGaveUp = true
                    print("WEBKIT_DUMP_PAGE_DEAD — giving up after \(retries) restarts")
                }
            }
            for (name, png) in outcome.images {
                do {
                    try write(png, named: name, into: directory)
                    dumped += 1
                } catch {
                    failures[name] = "cannot write the raster: \(error)"
                }
            }
            for (name, reason) in outcome.failures { failures[name] = reason }
            for note in outcome.sizeNotes { print("WEBKIT_DUMP_SIZE \(note)") }
            done += batch.count
            print("WEBKIT_DUMP_PROGRESS \(done)/\(prepared.count)")
        }

        let seconds = String(format: "%.1f", Date().timeIntervalSince(started))
        print("WEBKIT_DUMP_SUMMARY dumped=\(dumped) failed=\(failures.count) total=\(prepared.count) seconds=\(seconds)")
        for name in failures.keys.sorted() {
            print("WEBKIT_DUMP_FAIL \(name) (\(failures[name] ?? ""))")
        }

        // The test bundle reads the reasons from here: it never sees this process' output.
        let report = failures.keys.sorted().map { "\($0)\t\(failures[$0] ?? "")" }.joined(separator: "\n")
        try? report.write(to: directory.appendingPathComponent("failures.tsv"), atomically: true, encoding: .utf8)
        return failures.count
    }

    // MARK: - Page

    /// One loaded page: renders batches through it, and is replaced when WebKit loses the
    /// WebContent process behind it.
    @MainActor
    private final class Page {
        private var webView: WKWebView
        private let canvas: CGSize

        init(size: CGSize) {
            canvas = size
            webView = Page.makeWebView(size: size)
        }

        private static func makeWebView(size: CGSize) -> WKWebView {
            let webView = WKWebView(frame: CGRect(origin: .zero, size: size))
            webView.loadHTMLString("<!doctype html><html><body></body></html>", baseURL: nil)
            return webView
        }

        /// Renders one batch. A batch that answers nothing is retried fixture by fixture: one
        /// document that takes the page down then costs one raster, not the whole batch.
        func render(_ batch: [Prepared], timeout: Double = 30) async -> Outcome {
            do {
                return split(try await call(batch, timeout: timeout), batch: batch)
            } catch {
                let reason = "\(error)"
                guard batch.count > 1 else { return Outcome(failures: [batch[0].name: reason]) }
                var outcome = Outcome()
                for fixture in batch {
                    outcome.merge(await render([fixture], timeout: 5))
                }
                return outcome
            }
        }

        /// Calls the page's render function, retrying while the freshly loaded document is not
        /// ready yet, and never waiting longer than `timeout` for one call: `callAsyncJavaScript`'s
        /// completion never fires when the page's WebContent process dies, so the call is polled
        /// instead of awaited and a dead page degrades into a failed batch.
        private func call(_ batch: [Prepared], timeout: Double) async throws -> [String: Any] {
            let arguments: [String: Any] = [
                "items": batch.map { fixture in
                    ["name": fixture.name, "uri": dataURI(fixture.markup),
                     "x": Double(fixture.box.origin.x), "y": Double(fixture.box.origin.y),
                     "boxWidth": Double(fixture.box.width), "boxHeight": Double(fixture.box.height)]
                },
                "width": Double(canvas.width),
                "height": Double(canvas.height)
            ]
            var lastError: Error = Failure.pageUnavailable("the page never became ready")
            // The first calls also cover the page load, so they get more room; after that a page
            // that does not answer within a few seconds is treated as dead and the batch fails fast.
            let timeouts: [Double] = [15, 15, 5, 5, 5, 5]
            for attempt in 0..<timeouts.count {
                if attempt > 0 { try? await Task.sleep(nanoseconds: 100_000_000) }
                do {
                    let json = try await callOnce(arguments: arguments, timeout: min(timeouts[attempt], timeout))
                    guard let text = json as? String, let data = text.data(using: .utf8),
                          let dictionary = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        throw Failure.unexpectedResult("the page returned \(json.map { "\($0)" } ?? "nothing")")
                    }
                    return dictionary
                } catch {
                    lastError = error
                }
            }
            throw Failure.pageUnavailable("\(lastError)")
        }

        private func callOnce(arguments: [String: Any], timeout: Double) async throws -> Any? {
            let box = Answer()
            webView.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .page) { result in
                box.store(result)
            }
            let deadline = Date().addingTimeInterval(timeout)
            while box.result == nil, Date() < deadline {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            guard let result = box.result else {
                throw Failure.pageUnavailable("no answer within \(Int(timeout))s (the WebContent process died?)")
            }
            return try result.get()
        }

        /// The completion of one page call, handed from WebKit's main-thread callback to the
        /// polling loop (both run on the main thread; the box only exists to satisfy the closures).
        private final class Answer: @unchecked Sendable {
            var result: Result<Any, Error>?

            func store(_ result: Result<Any, Error>) {
                self.result = result
            }
        }

        private func split(_ dictionary: [String: Any], batch: [Prepared]) -> Outcome {
            var outcome = Outcome()
            for fixture in batch {
                let value = dictionary[fixture.name]
                guard let value = value, !(value is NSNull) else {
                    outcome.failures[fixture.name] = "the browser did not load the document"
                    continue
                }
                guard let entry = value as? [String: Any],
                      let dataURL = entry["png"] as? String,
                      let data = pngData(from: dataURL) else {
                    outcome.failures[fixture.name] = "the page returned no raster"
                    continue
                }
                if let natural = entry["natural"] as? [Any], natural.count == 2,
                   let width = (natural[0] as? NSNumber)?.doubleValue,
                   let height = (natural[1] as? NSNumber)?.doubleValue,
                   abs(width - fixture.box.width) > 2 || abs(height - fixture.box.height) > 2 {
                    // The browser laid the document out in a different box than the kit draws it
                    // in: worth knowing about when a fixture diverges (a `%` width, a stray unit).
                    outcome.sizeNotes.append("\(fixture.name) natural=\(Int(width))x\(Int(height)) "
                        + "box=\(format(fixture.box.width))x\(format(fixture.box.height))")
                }
                outcome.images[fixture.name] = data
            }
            return outcome
        }

        private func dataURI(_ svg: String) -> String {
            "data:image/svg+xml;base64," + Data(svg.utf8).base64EncodedString()
        }

        private func pngData(from dataURL: String) -> Data? {
            guard let comma = dataURL.firstIndex(of: ",") else { return nil }
            return Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...]))
        }
    }

    // MARK: - Layout

    /// Prepares one fixture: derives the document's `viewBox` and the box it is fitted into the
    /// way the kit does (`SVGOptions.init` plus `SVGPreserveAspectRatio.resolve`), then rewrites
    /// the root tag to carry exactly that box as the document's intrinsic size.
    private static func prepare(name: String, svg: String, canvas: CGSize) -> Prepared {
        let attributes = rootAttributes(svg)
        var viewBox: CGRect?
        if let raw = attributes["viewbox"] {
            viewBox = parseViewBox(raw)
        }
        if viewBox == nil {
            // No (usable) viewBox: the kit takes the viewport, with a 100×100 square when a
            // dimension is missing or is not a pixel length (B101), and treats it as the viewBox.
            let width = pixels(attributes["width"]) ?? pixels(attributes["height"]) ?? 100
            let height = pixels(attributes["height"]) ?? pixels(attributes["width"]) ?? 100
            viewBox = CGRect(x: 0, y: 0, width: width, height: height)
        }
        guard let viewBox = viewBox, viewBox.width > 0, viewBox.height > 0 else {
            return Prepared(name: name, markup: svg, box: CGRect(origin: .zero, size: canvas))
        }
        let box = fitted(viewBox.size, into: canvas, preserveAspectRatio: attributes["preserveaspectratio"])
        return Prepared(name: name, markup: forcing(svg, viewBox: viewBox, box: box.size), box: box)
    }

    /// The box the document's `viewBox` occupies on the canvas — the same rect `SVGView` scales
    /// its layer to.
    private static func fitted(_ viewBox: CGSize, into canvas: CGSize, preserveAspectRatio raw: String?) -> CGRect {
        var align = "xMidYMid"
        var slice = false
        for token in (raw ?? "").split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\n" }) {
            switch token {
            case "defer", "meet": continue
            case "slice": slice = true
            case "none": align = "none"
            case let value where value.hasPrefix("x"): align = String(value)
            default: continue
            }
        }
        let scaleX = canvas.width / viewBox.width
        let scaleY = canvas.height / viewBox.height
        if align == "none" {
            return CGRect(x: 0, y: 0, width: viewBox.width * scaleX, height: viewBox.height * scaleY)
        }
        let scale = slice ? max(scaleX, scaleY) : min(scaleX, scaleY)
        let size = CGSize(width: viewBox.width * scale, height: viewBox.height * scale)
        // The token is `xMidYMid`-style — the `Y` is capitalized — so the axes are spelled out
        // rather than matched with a case-sensitive `contains` (B122: a wrong match offset the
        // browser's drawing vertically for every non-square document).
        let fractions: (x: CGFloat, y: CGFloat)
        switch align {
        case "xMinYMin": fractions = (0, 0)
        case "xMidYMin": fractions = (0.5, 0)
        case "xMaxYMin": fractions = (1, 0)
        case "xMinYMid": fractions = (0, 0.5)
        case "xMaxYMid": fractions = (1, 0.5)
        case "xMinYMax": fractions = (0, 1)
        case "xMidYMax": fractions = (0.5, 1)
        case "xMaxYMax": fractions = (1, 1)
        default: fractions = (0.5, 0.5) // `xMidYMid`, and the kit's fallback for anything else
        }
        return CGRect(origin: CGPoint(x: (canvas.width - size.width) * fractions.x,
                                      y: (canvas.height - size.height) * fractions.y), size: size)
    }

    /// Rewrites the root `<svg>` tag: an explicit intrinsic size equal to `box` (so the browser
    /// rasterizes the vector at canvas resolution instead of upscaling a small intrinsic box) and
    /// the `viewBox` the kit uses — including its origin, which the browser would otherwise drop
    /// (the kit translates the layer by `-viewBox.origin`, B122).
    private static func forcing(_ svg: String, viewBox: CGRect, box: CGSize) -> String {
        guard let range = rootTagRange(svg) else { return svg }
        var tag = String(svg[range])
        for name in ["width", "height", "viewBox"] {
            let pattern = "(?:\\s|^)\(name)\\s*=\\s*(\"[^\"]*\"|'[^']*')"
            tag = tag.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        var additions = " width=\"\(format(box.width))\" height=\"\(format(box.height))\""
        additions += " viewBox=\"\(format(viewBox.origin.x)) \(format(viewBox.origin.y)) \(format(viewBox.width)) \(format(viewBox.height))\""
        var insertion = tag.index(before: tag.endIndex)
        if tag[tag.index(before: insertion)] == "/" { insertion = tag.index(before: insertion) }
        tag.insert(contentsOf: additions, at: insertion)
        return svg.replacingCharacters(in: range, with: tag)
    }

    /// The range of the root `<svg …>` tag, from `<` through its closing `>`: a quoted value may
    /// contain a `>`, and most corpus files carry a commented-out `<svg>` before the real one
    /// (which the kit's XML parser ignores), so the document is scanned rather than matched with a
    /// regex.
    private static func rootTagRange(_ svg: String) -> Range<String.Index>? {
        var index = svg.startIndex
        while index < svg.endIndex {
            guard let start = svg[index...].firstIndex(of: "<") else { return nil }
            if svg[start...].hasPrefix("<!--") {
                guard let end = svg.range(of: "-->", range: start..<svg.endIndex)?.upperBound else { return nil }
                index = end
                continue
            }
            guard let nameEnd = svg.index(start, offsetBy: 4, limitedBy: svg.endIndex),
                  svg[start..<nameEnd].lowercased() == "<svg",
                  nameEnd < svg.endIndex,
                  svg[nameEnd].isWhitespace || svg[nameEnd] == ">" || svg[nameEnd] == "/" else {
                index = svg.index(after: start)
                continue
            }
            var quote: Character?
            var cursor = nameEnd
            while cursor < svg.endIndex {
                let character = svg[cursor]
                if let open = quote {
                    if character == open { quote = nil }
                } else if character == "\"" || character == "'" {
                    quote = character
                } else if character == ">" {
                    return start..<svg.index(after: cursor)
                }
                cursor = svg.index(after: cursor)
            }
            return nil
        }
        return nil
    }

    /// The attributes of a tag, keyed by their lowercased name.
    private static func rootAttributes(_ svg: String) -> [String: String] {
        guard let range = rootTagRange(svg) else { return [:] }
        let tag = svg[range]
        var result: [String: String] = [:]
        var index = tag.startIndex
        while let equals = tag[index...].firstIndex(of: "=") {
            var nameStart = equals
            while nameStart > tag.startIndex, !tag[tag.index(before: nameStart)].isWhitespace {
                nameStart = tag.index(before: nameStart)
            }
            let name = String(tag[nameStart..<equals]).lowercased()
            var valueStart = tag.index(after: equals)
            while valueStart < tag.endIndex, tag[valueStart].isWhitespace { valueStart = tag.index(after: valueStart) }
            guard valueStart < tag.endIndex, tag[valueStart] == "\"" || tag[valueStart] == "'" else {
                index = tag.index(after: equals)
                continue
            }
            let quote = tag[valueStart]
            let valueBegin = tag.index(after: valueStart)
            guard let valueEnd = tag[valueBegin...].firstIndex(of: quote) else { return result }
            result[name] = String(tag[valueBegin..<valueEnd])
            index = tag.index(after: valueEnd)
        }
        return result
    }

    private static func parseViewBox(_ raw: String) -> CGRect? {
        let parts = raw.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\n" || $0 == "\t" })
        guard parts.count == 4, let x = Double(parts[0]), let y = Double(parts[1]),
              let width = Double(parts[2]), let height = Double(parts[3]) else { return nil }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// A `width`/`height` attribute as device-independent pixels. Anything else — a percentage, a
    /// relative unit, garbage — is not a pixel length and the caller falls back, mirroring how
    /// `SVGOptions` degrades (B101).
    private static func pixels(_ raw: String?) -> CGFloat? {
        guard var number = raw?.trimmingCharacters(in: .whitespaces), !number.isEmpty else { return nil }
        for suffix in ["px", "pt", "pc", "in", "cm", "mm"] where number.lowercased().hasSuffix(suffix) {
            number = String(number.dropLast(suffix.count))
            break
        }
        guard let value = Double(number), value > 0 else { return nil }
        return CGFloat(value)
    }

    /// Enough precision that the browser's box matches the kit's fit.
    private static func format(_ value: CGFloat) -> String {
        String(format: "%.4f", Double(value))
    }

    // MARK: - Corpus

    private static func loadCorpus(_ directory: URL) -> [(name: String, svg: String)] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return [] }
        var fixtures: [(name: String, svg: String)] = []
        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "svg",
                  let data = try? Data(contentsOf: url),
                  let svg = String(data: data, encoding: .utf8) else { continue }
            let name = url.path.replacingOccurrences(of: directory.path + "/", with: "")
            fixtures.append((name, svg))
        }
        return fixtures.sorted { $0.name < $1.name }
    }

    private static func chunks<T>(_ items: [T], size: Int) -> [[T]] {
        guard size > 0 else { return [items] }
        return stride(from: 0, to: items.count, by: size).map { Array(items[$0..<Swift.min($0 + size, items.count)]) }
    }

    private static func write(_ png: Data, named name: String, into directory: URL) throws {
        let url = directory.appendingPathComponent(name + ".png")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url)
    }

    // MARK: - The page's render function

    /// The body of an async function `callAsyncJavaScript` compiles for the page: `items` are the
    /// prepared fixtures (`{name, uri, x, y, boxWidth, boxHeight}`), `width`/`height` are the
    /// canvas, and the result is a JSON string mapping a name to `{png, natural}` — or `null`
    /// when the document did not load, so only encoded pixels cross the bridge.
    private static let script = """
    const out = {};
    const loadImage = (uri) => new Promise((resolve) => {
        const image = new Image();
        image.onload = () => resolve(image);
        image.onerror = () => resolve(null);
        image.src = uri;
    });
    for (const item of items) {
        const image = await loadImage(item.uri);
        if (!image) { out[item.name] = null; continue; }
        const canvas = document.createElement('canvas');
        canvas.width = width;
        canvas.height = height;
        const context = canvas.getContext('2d');
        context.drawImage(image, item.x, item.y, item.boxWidth, item.boxHeight);
        out[item.name] = { png: canvas.toDataURL('image/png'), natural: [image.naturalWidth, image.naturalHeight] };
    }
    return JSON.stringify(out);
    """
}
