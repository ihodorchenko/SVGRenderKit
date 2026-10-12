import os

/// Points-of-interest signposts around the expensive pipeline stages (parse, layer build, rasterize, encode),
/// visible in Instruments. The cost when no profiler is attached is negligible.
enum SVGSignpost {
    static let log = OSLog(subsystem: "SVGRenderKit", category: .pointsOfInterest)

    /// Runs `body` between a signpost begin/end pair named `name`.
    static func interval<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        defer { os_signpost(.end, log: log, name: name, signpostID: id) }
        return try body()
    }
}
