import UIKit

/// A shared cache that stores parsed SVG roots keyed by an MD5 hash.
open class SVGCache: @unchecked Sendable {
    /// Whether the cache is used when parsing SVGs.
    public var isSVGParserUseCache: Bool {
        get { return SVGConfiguration.shared.isParserCacheEnabled }
        set { SVGConfiguration.shared.isParserCacheEnabled = newValue }
    }

    /// The notification name that triggers all `SVGView` instances to reload, or `nil` to disable it.
    public var updateNotificationName: NSNotification.Name? {
        get { return SVGConfiguration.shared.updateNotificationName }
        set { SVGConfiguration.shared.updateNotificationName = newValue }
    }

    private let lock = NSLock()
    /// The shared singleton cache instance.
    static public let s = SVGCache()

    let maxCount: Int = 100
    private struct Entry {
        let root: SVGRoot
        var lastUsed: UInt64
    }
    private var entries: [String: Entry] = [:]
    private var tick: UInt64 = 0

    private init() {
    }

    /// Removes all cached parsed SVG roots.
    open func resetCache() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
    }

    func get(md5: String) -> SVGRoot? {
        guard isSVGParserUseCache else { return nil }
        lock.lock()
        defer { lock.unlock() }
        guard var entry = entries[md5] else { return nil }
        // A hit refreshes recency, so frequently used documents are the last to be evicted.
        tick &+= 1
        entry.lastUsed = tick
        entries[md5] = entry
        return entry.root
    }

    func set(md5: String, object: SVGRoot) {
        guard isSVGParserUseCache else { return }
        lock.lock()
        defer { lock.unlock() }
        if entries[md5] == nil, entries.count >= maxCount,
           let oldest = entries.min(by: { $0.value.lastUsed < $1.value.lastUsed })?.key {
            entries.removeValue(forKey: oldest)
        }
        tick &+= 1
        entries[md5] = Entry(root: object, lastUsed: tick)
    }
}
