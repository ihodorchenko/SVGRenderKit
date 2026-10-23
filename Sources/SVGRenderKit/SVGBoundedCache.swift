import UIKit

/// A small thread-safe cache that holds at most `limit` entries (and, when a `cost` is given, at most
/// `costLimit` bytes in total), evicting everything when full.
///
/// Used for derived render data (pattern tiles, mask bitmaps, decoded images, fonts) that is cheap to
/// recompute occasionally but expensive to recompute for every shape or `<use>` expansion. A plain
/// clear-on-overflow policy keeps it allocation-light and bounds memory without LRU bookkeeping.
final class SVGBoundedCache<Key: Hashable, Value>: @unchecked Sendable {
    private var storage: [Key: Value] = [:]
    private let lock = NSLock()
    private let limit: Int
    private let costLimit: Int
    private let cost: (Value) -> Int
    private var totalCost = 0

    /// - Parameters:
    ///   - cost: The size in bytes of a value; counted against `costLimit`. A value larger than the
    ///     whole budget is still stored (alone), so a hit behaves exactly as without a budget.
    init(limit: Int, costLimit: Int = .max, cost: @escaping (Value) -> Int = { _ in 0 }) {
        self.limit = limit
        self.costLimit = costLimit
        self.cost = cost
    }

    func value(for key: Key) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    func set(_ value: Value, for key: Key) {
        lock.lock()
        defer { lock.unlock() }
        let size = cost(value)
        if let old = storage[key] { totalCost -= cost(old); storage[key] = nil }
        if storage.count >= limit || (size > 0 && totalCost + size > costLimit) {
            storage.removeAll(keepingCapacity: true)
            totalCost = 0
        }
        storage[key] = value
        totalCost += size
    }

    /// Returns the cached value, computing and storing it with `make` on a miss. `make` always
    /// produces a value, so so does this.
    func value(for key: Key, make: () -> Value) -> Value {
        if let cached = value(for: key) { return cached }
        let created = make()
        set(created, for: key)
        return created
    }

    /// Like the overload above, for a `make` that can fail: a `nil` is returned and not cached.
    func value(for key: Key, make: () -> Value?) -> Value? {
        if let cached = value(for: key) { return cached }
        guard let created = make() else { return nil }
        set(created, for: key)
        return created
    }
}

/// Memory accounting for the bitmap caches.
enum SVGBitmapCost {
    /// Total bytes a bitmap cache may hold: 16 tiles can each reach the 4096 px cap (64 MB), so the
    /// entry count alone does not bound memory.
    static let budget = 96 * 1024 * 1024

    static func bytes(_ image: CGImage) -> Int { image.bytesPerRow * image.height }
    static func bytes(_ image: UIImage) -> Int { image.cgImage.map(bytes) ?? 0 }
}
