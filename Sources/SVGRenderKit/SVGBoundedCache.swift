import Foundation

/// A small thread-safe cache that holds at most `limit` entries, evicting everything when full.
///
/// Used for derived render data (pattern tiles, mask bitmaps, decoded images, fonts) that is cheap to
/// recompute occasionally but expensive to recompute for every shape or `<use>` expansion. A plain
/// clear-on-overflow policy keeps it allocation-light and bounds memory without LRU bookkeeping.
final class SVGBoundedCache<Key: Hashable, Value>: @unchecked Sendable {
    private var storage: [Key: Value] = [:]
    private let lock = NSLock()
    private let limit: Int

    init(limit: Int) {
        self.limit = limit
    }

    func value(for key: Key) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    func set(_ value: Value, for key: Key) {
        lock.lock()
        defer { lock.unlock() }
        if storage.count >= limit { storage.removeAll(keepingCapacity: true) }
        storage[key] = value
    }

    /// Returns the cached value, computing and storing it with `make` on a miss.
    func value(for key: Key, make: () -> Value?) -> Value? {
        if let cached = value(for: key) { return cached }
        guard let created = make() else { return nil }
        set(created, for: key)
        return created
    }
}
