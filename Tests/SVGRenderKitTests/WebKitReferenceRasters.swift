import UIKit

/// The *browser* oracle's rasters for the corpus parity test (B122), so the same kit raster can be
/// judged by CoreSVG and by a browser in one report.
///
/// The rasters come from the Example app: `WebKitParityRunner` renders the corpus in a `WKWebView`
/// and writes one PNG per fixture. They cannot be produced here — WebKit's WebContent process
/// refuses to start in a bare unit-test bundle (on iOS 26 the logs show an `RBS` assertion that
/// the target "does not have entitlement com.apple.developer.web-browser-engine.*").
/// `Scripts/webkit-parity.sh` runs the app and records where it wrote the dump, so a later test run
/// picks the rasters up through `dumpDirectory()`.
enum WebKitReferenceRasters {

    /// The directory to read the browser rasters from: `SVGRENDERKIT_WEBKIT_RASTERS` when the
    /// environment carries it, otherwise the location `Scripts/webkit-parity.sh` recorded in
    /// `<repo>/.webkit-rasters`. `nil` when there is no dump at all — a plain test run then reports
    /// the CoreSVG parity alone.
    static func dumpDirectory() -> URL? {
        if let path = ProcessInfo.processInfo.environment["SVGRENDERKIT_WEBKIT_RASTERS"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        let pointer = CorpusLoader.repositoryRoot.appendingPathComponent(".webkit-rasters")
        guard let path = try? String(contentsOf: pointer, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Loads every `<fixture name>.png` under `directory`, plus the reasons the app recorded for
    /// fixtures the browser could not render (`failures.tsv`, one `name<TAB>reason` per line).
    /// Fixtures with neither are reported by the caller as missing.
    static func load(from directory: URL) -> (images: [String: Data], failures: [String: String]) {
        var images: [String: Data] = [:]
        var failures: [String: String] = [:]

        // The names are relative paths, so the enumerated file URLs are matched by path
        // components against the resolved directory: `/tmp` is a symlink to `/private/tmp`, and a
        // string prefix test would silently drop every file (B122).
        let base = directory.resolvingSymlinksInPath().pathComponents
        let keys: [URLResourceKey] = [.isRegularFileKey]
        if let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) {
            for case let url as URL in enumerator {
                guard url.pathExtension.lowercased() == "png", let data = try? Data(contentsOf: url) else { continue }
                let components = url.resolvingSymlinksInPath().pathComponents
                guard components.count > base.count, components.starts(with: base) else { continue }
                let name = components.dropFirst(base.count).joined(separator: "/")
                guard name.hasSuffix(".png") else { continue }
                images[String(name.dropLast(".png".count))] = data
            }
        }

        if let report = try? String(contentsOf: directory.appendingPathComponent("failures.tsv"), encoding: .utf8) {
            for line in report.split(separator: "\n") {
                let parts = line.split(separator: "\t", maxSplits: 1)
                guard let name = parts.first else { continue }
                failures[String(name)] = parts.count > 1 ? String(parts[1]) : "the browser reported no reason"
            }
        }
        return (images, failures)
    }
}
