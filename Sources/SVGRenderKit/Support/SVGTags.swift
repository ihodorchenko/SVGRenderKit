import UIKit

class SVGTags<T: SVGObject> {
    var array: [T] = []
    var byId: [String: T] = [:]
    var byClass: [String: [T]] = [:]

    func add(item: T) {
        for className in item.classNames {
            byClass[className, default: []].append(item)
        }
        // The first element with an `id` wins, as in browsers: a duplicate `id` further down
        // the document must not shadow the earlier element (B88).
        if let id = item.id, byId[id] == nil {
            byId[id] = item
        }
        array.append(item)
    }

    internal func get(key: String) -> T? {
        if let v = byId[key] {
            return v
        }
        return byClass[key]?.last
    }

    /// Returns all objects matching the given class selector.
    internal func getAll(byClass classStr: String) -> [T] {
        return byClass[classStr] ?? []
    }
}
