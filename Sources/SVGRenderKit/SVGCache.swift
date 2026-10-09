import UIKit

fileprivate extension Array where Element: Equatable {
    func getIndexes(of element: Element) -> [Int] {
        return self.enumerated().compactMap { ($0.element == element) ? $0.offset : nil }
    }
}

/// A shared cache that stores parsed SVG roots keyed by an MD5 hash.
open class SVGCache {
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

    private let accessQueue = DispatchQueue(label: "SynchronizedArrayAccess")
    /// The shared singleton cache instance.
    static public let s = SVGCache()

    let maxCount: Int = 100
    var parserCache: [String: SVGRoot] = [:]
    var parserIDs: [String] = []

    private init() {
    }

    /// Removes all cached parsed SVG roots.
    open func resetCache() {
        parserCache.removeAll()
        parserIDs.removeAll()
    }

    func get(md5: String) -> SVGRoot? {
        if isSVGParserUseCache {
            var obj: SVGRoot?
            accessQueue.sync {
                obj = parserCache[md5]
            }
            return obj
        } else {
            return nil
        }
    }

    func set(md5: String, object: SVGRoot) {
        if isSVGParserUseCache {
            accessQueue.sync {
                if parserIDs.count > maxCount {
                    if let first = parserIDs.first {
                        parserCache.removeValue(forKey: first)
                    }
                    parserIDs.removeFirst()
                }
                parserCache[md5] = object
                let indexes = parserIDs.getIndexes(of: md5)
                if indexes.count > 0 {
                    parserIDs.remove(at: indexes[0])
                }
                parserIDs.append(md5)
            }
        }
    }
}
