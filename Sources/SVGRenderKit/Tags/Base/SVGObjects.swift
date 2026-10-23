import UIKit

/// Base model representing a single parsed SVG object.
class SVGObject {
    var attributeDict: [String: String] = [:]

    var key: String {
        get {
            return type(of: self).key
        }
    }
    class var key: String {
        get {
            return ""
        }
    }

    let id: String?
    let classStr: String?
    /// Every class in the `class` attribute, each prefixed with `.` (`class="a b"` → `[".a", ".b"]`).
    let classNames: [String]

    var href: SVGFuncIRI?

    /// Initializes an SVG object from its XML element and optional additional attributes.
    init(xmlElement: XMLElement, addDict: [String: String]? = nil) throws {
        var attributeDict: [String: String] = xmlElement.attributesDict()
        if let addDict = addDict {
            for elem in addDict {
                attributeDict[elem.key] = elem.value
            }
        }
        self.attributeDict = attributeDict
        if var id = attributeDict["id"] {
            if !id.hasPrefix("#") {
                id = "#" + id
            }
            self.id = id
        } else {
            self.id = nil
        }
        if let `class` = attributeDict["class"] {
            let names = `class`.split(whereSeparator: { $0.isWhitespace }).map { name -> String in
                name.hasPrefix(".") ? String(name) : "." + name
            }
            self.classNames = names
            self.classStr = names.first
        } else {
            self.classNames = []
            self.classStr = nil
        }
        if let href = attributeDict["xlink:href"] {
            // Non-local hrefs (data URIs, external URLs) are resolved by the
            // specific element (e.g. `<image>`); degrade to nil here instead of
            // failing the whole document.
            self.href = try? SVGFuncIRI.get(content: href)
        } else if let href = attributeDict["href"] {
            self.href = try? SVGFuncIRI.get(content: href)
        }
        _init()
    }

    internal func _init() {

    }
}

/// Base model for SVG objects that belong to a parent group.
class SVGChildObject: SVGObject {
    /// The owning parent. `unowned` because the parent owns its children and always
    /// outlives them; a strong reference here would retain-cycle the whole document.
    unowned var parent: SVGGroupProtocol
    /// Initializes a child object from its XML element, optional attributes, and parent group.
    required init(xmlElement: XMLElement, addDict: [String: String]? = nil, parent: SVGGroupProtocol) throws {
        self.parent = parent
        try super.init(xmlElement: xmlElement, addDict: addDict)
    }
}
