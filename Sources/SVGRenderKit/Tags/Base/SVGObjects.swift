import UIKit

/// Base model representing a single parsed SVG object.
open class SVGObject {
    var xmlElement: XMLElement

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

    var href: SVGFuncIRI?

    /// Initializes an SVG object from its XML element and optional additional attributes.
    public init(xmlElement: XMLElement, addDict: [String: String]? = nil) throws {
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
        if var `class` = attributeDict["class"] {
            if !`class`.hasPrefix(".") {
                `class` = "." + `class`
            }
            self.classStr = `class`
        } else {
            self.classStr = nil
        }
        if let href = attributeDict["xlink:href"] {
            self.href = try SVGFuncIRI.get(content: href)
        } else if let href = attributeDict["href"] {
            self.href = try SVGFuncIRI.get(content: href)
        }
        self.xmlElement = xmlElement
        _init()
    }

    internal func _init() {

    }
}

/// Base model for SVG objects that belong to a parent group.
open class SVGChildObject: SVGObject {
    var parent: SVGGroupProtocol
    /// Initializes a child object from its XML element, optional attributes, and parent group.
    public required init(xmlElement: XMLElement, addDict: [String: String]? = nil, parent: SVGGroupProtocol) throws {
        self.parent = parent
        try super.init(xmlElement: xmlElement, addDict: addDict)
    }
}
