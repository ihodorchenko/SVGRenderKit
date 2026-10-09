import UIKit

class SVGTags<T: SVGObject> {
    var array: [T] = []
    var byId: [String: T] = [:]
    var byClass: [String: [T]] = [:]

    func add(item: T) {
        if let classStr = item.classStr {
            byClass[classStr, default: []].append(item)
        }
        if let id = item.id {
            byId[id] = item
        }
        array.append(item)
    }

    func addRange(items: [T]) {
        for item in items {
            add(item: item)
        }
    }

    internal func exist(id: String) -> Bool {
        return byId[id] != nil
    }

    internal func exist(`class`: String) -> Bool {
        return !(byClass[`class`]?.isEmpty ?? true)
    }

    internal func exist(key: String) -> Bool {
        if byId[key] != nil {
            return true
        }
        return !(byClass[key]?.isEmpty ?? true)
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
