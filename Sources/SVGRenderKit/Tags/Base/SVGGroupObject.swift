import UIKit

/// Container for a group's child groups, shapes, gradients, clip paths, and use elements.
open class SVGGroupObject: SVGChildObject, SVGGroupProtocol {

    var transform: CATransform3D?

    /// Renderable children in document order (groups, shapes, and use elements).
    private(set) var layerElements: SVGTags<SVGObject> = SVGTags<SVGObject>()
    var defs: SVGDefsGroupTag? {
        didSet {
            defs?.parent = self
        }
    }
    /// Every child object, used for id/class lookups regardless of type.
    private(set) var all: SVGTags<SVGObject> = SVGTags<SVGObject>()

    var sourceStyle: SVGSourceStyleElement?
    var styleTag: SVGStyleTag?

    /// Initializes a group object from its XML element, parsing its children.
    public required init(xmlElement: XMLElement, addDict: [String: String]? = nil, parent: SVGGroupProtocol) throws {
        try super.init(xmlElement: xmlElement, addDict: addDict, parent: parent)

        let tsStyle: SVGSourceStyleElement = SVGSourceStyleElement()
        if let str = attributeDict["style"] {
            try tsStyle.set(styleStr: str, force: false)
        }
        try tsStyle.set(attributeDict: attributeDict)
        sourceStyle = tsStyle

        if let str = attributeDict["transform"] {
            transform = try SVGTransform.get(string: str)
        }
        
        for children in xmlElement.xmlChildren {
            try parse(children: children)
        }
    }

    /// Returns the rendering options for the SVG document.
    public func getSvgOptions() -> SVGOptions {
        return parent.getSvgOptions()
    }
}

extension SVGGroupObject {
    internal func parse(children: XMLElement) throws {
        switch children.name {
        case SVGLinearGradientTag.key:
            try addIfNeedLinearGradient(children: children)
            break
        case SVGRadialGradientTag.key:
            try addIfNeedRadialGradient(children: children)
            break
        case SVGStyleTag.key:
            let styleTag: SVGStyleTag = try SVGStyleTag(xmlElement: children, parent: self)
            self.styleTag = styleTag
            break
        case SVGGTag.key:
            let newGroup: SVGGTag = try SVGGTag(xmlElement: children, parent: self)
            try self.add(groups: [newGroup])
            break
        case SVGUseTag.key:
            let use: SVGUseTag = try SVGUseTag(xmlElement: children, parent: self)
            try self.add(uses: [use])
            break
        case SVGDefsGroupTag.key:
            let defs: SVGDefsGroupTag = try SVGDefsGroupTag(xmlElement: children, parent: self)
            self.defs = defs
            break
        case SVGClipPath.key:
            let cp: SVGClipPath = try SVGClipPath(xmlElement: children, parent: self)
            try self.add(clipPaths: [cp])
            break
        default:
            if let shapeTag = try SVGShapeObject.create(xml: children, parent: self) {
                try self.add(shapes: [shapeTag])
            }
            break
        }
    }
}

extension SVGGroupObject {
    @discardableResult fileprivate func addIfNeedLinearGradient(children: XMLElement) throws -> SVGLinearGradientTag {
        if let id = children.attribute(by: "id")?.text, let obj = all.get(key: id) as? SVGLinearGradientTag {
            return obj
        }
        if let classStr = children.attribute(by: "class")?.text, let obj = all.get(key: classStr) as? SVGLinearGradientTag {
            return obj
        }
        let obj = try SVGLinearGradientTag(xmlElement: children, parent: self)
        try self.add(linearGradients: [obj])
        return obj
    }

    @discardableResult fileprivate func addIfNeedRadialGradient(children: XMLElement) throws -> SVGRadialGradientTag {
        if let id = children.attribute(by: "id")?.text, let obj = all.get(key: id) as? SVGRadialGradientTag {
            return obj
        }
        if let classStr = children.attribute(by: "class")?.text, let obj = all.get(key: classStr) as? SVGRadialGradientTag {
            return obj
        }
        let obj = try SVGRadialGradientTag(xmlElement: children, parent: self)
        try self.add(radialGradients: [obj])
        return obj
    }

    /// Adds the given groups as children of this group.
    public func add(groups: [SVGGTag]) throws {
        for group in groups {
            group.parent = self
            self.all.add(item: group)
            self.layerElements.add(item: group)
        }
    }

    /// Adds the given use elements as children of this group.
    public func add(uses: [SVGUseTag]) throws {
        for use in uses {
            use.parent = self
            self.all.add(item: use)
            self.layerElements.add(item: use)
        }
    }

    /// Adds the given shapes as children of this group.
    public func add(shapes: [SVGShapeObject]) throws {
        for shape in shapes {
            shape.parent = self
            self.all.add(item: shape)
            self.layerElements.add(item: shape)
        }
    }

    /// Adds the given clip paths to this group.
    public func add(clipPaths: [SVGClipPath]) throws {
        for path in clipPaths {
            path.parent = self
            self.all.add(item: path)
        }
    }

    /// Adds the given linear gradients to this group.
    public func add(linearGradients: [SVGLinearGradientTag]) throws {
        for gradient in linearGradients {
            gradient.parent = self
            self.all.add(item: gradient)
        }
    }

    /// Adds the given radial gradients to this group.
    public func add(radialGradients: [SVGRadialGradientTag]) throws {
        for gradient in radialGradients {
            gradient.parent = self
            self.all.add(item: gradient)
        }
    }
}

extension SVGGroupObject {

    /// Returns the child object matching the key, optionally searching parent groups.
    public func getObject(byKey: String, fromParents: Bool) -> SVGObject? {
        if let o = all.get(key: byKey) {
            return o
        }
        return fromParents ? parent.getObject(byKey: byKey, fromParents: fromParents) : nil
    }

    /// Returns the group matching the key, optionally searching parent groups.
    public func getG(byKey: String, fromParents: Bool) -> SVGGTag? {
        if let defs = defs {
            if let gr = defs.getG(byKey: byKey, fromParents: false) {
                return gr
            }
        }
        if let gr = all.get(key: byKey) as? SVGGTag {
            return gr
        }
        return fromParents ? parent.getG(byKey: byKey, fromParents: fromParents) : nil
    }

    /// Returns the shape matching the key, optionally searching parent groups.
    public func getShape(byKey: String, fromParents: Bool) -> SVGShapeObject? {
        if let defs = defs {
            if let gr = defs.getShape(byKey: byKey, fromParents: false) {
                return gr
            }
        }
        if let gr = all.get(key: byKey) as? SVGShapeObject {
            return gr
        }
        return fromParents ? parent.getShape(byKey: byKey, fromParents: fromParents) : nil
    }

    /// Returns a renderable (shape or group) matching the key, optionally searching parent groups.
    public func getRendering(byKey: String, fromParents: Bool) -> SVGRendering? {
        if let share = getShape(byKey: byKey, fromParents: true) {
            return share
        }
        if let gr = getG(byKey: byKey, fromParents: true) {
            return gr
        }
        return fromParents ? parent.getRendering(byKey: byKey, fromParents: fromParents) : nil
    }

    /// Returns the linear gradient matching the key, optionally searching parent groups.
    public func getLinearGradient(byKey: String, fromParents: Bool) -> SVGLinearGradientTag? {
        if let defs = defs {
            if let gr = defs.getLinearGradient(byKey: byKey, fromParents: false) {
                return gr
            }
        }
        if let gr = all.get(key: byKey) as? SVGLinearGradientTag {
            return gr
        }
        return fromParents ? parent.getLinearGradient(byKey: byKey, fromParents: fromParents) : nil
    }

    /// Returns the radial gradient matching the key, optionally searching parent groups.
    public func getRadialGradients(byKey: String, fromParents: Bool) -> SVGRadialGradientTag? {
        if let defs = defs {
            if let gr = defs.getRadialGradients(byKey: byKey, fromParents: false) {
                return gr
            }
        }
        if let gr = all.get(key: byKey) as? SVGRadialGradientTag {
            return gr
        }
        return fromParents ? parent.getRadialGradients(byKey: byKey, fromParents: fromParents) : nil
    }

    /// Resolves the style for a shape by combining inherited, tag, class, id, and override styles.
    public func getStyle(
        forObject: SVGShapeObject,
        overrideElements: [String: SVGSourceStyleElement]?) -> SVGSourceStyleElement
    {
        var style: SVGSourceStyleElement = self.parent.getStyle(
            forObject: forObject, overrideElements: overrideElements)
        if let selfStyle = self.sourceStyle {
            style = style.combine(child: selfStyle)
        }
        func styleTagFunc(styleTag: SVGStyleTag) {
            if let tagStyle = styleTag.byTagDict[forObject.key] {
                style = style.combine(child: tagStyle)
            }
            if let classStr = forObject.classStr, let classStyle = styleTag.byClassDict[classStr] {
                style = style.combine(child: classStyle)
            }
            if let idStr = forObject.id, let idStyle = styleTag.byIdDict[idStr] {
                style = style.combine(child: idStyle)
            }
        }
        if let styleTag = self.styleTag {
            styleTagFunc(styleTag: styleTag)
        }
        if let defs = self.defs, let styleTag = defs.styleTag {
            styleTagFunc(styleTag: styleTag)
        }
        if let overrideElements = overrideElements {
            if let tagElem = overrideElements[self.key] {
                style = style.combine(child: tagElem)
            }
            if let classStr = self.classStr, let idElem = overrideElements[classStr] {
                style = style.combine(child: idElem)
            }
            if let id = self.id, let idElem = overrideElements[id] {
                style = style.combine(child: idElem)
            }
        }

        return style
    }

    /// Returns the gradient (linear or radial) matching the key, optionally searching parent groups.
    public func getGradient(byKey: String, fromParents: Bool) -> SVGBaseGradient? {
        if let gr = getLinearGradient(byKey: byKey, fromParents: fromParents) {
            return gr
        }
        if let gr = getRadialGradients(byKey: byKey, fromParents: fromParents) {
            return gr
        }
        return nil
    }

    /// Returns the clip path matching the key, optionally searching parent groups.
    public func getClipPath(byKey: String, fromParents: Bool) -> SVGClipPath? {
        if let defs = defs {
            if let gr = defs.getClipPath(byKey: byKey, fromParents: false) {
                return gr
            }
        }
        if let o = all.get(key: byKey) as? SVGClipPath {
            return o
        }
        return fromParents ? parent.getClipPath(byKey: byKey, fromParents: fromParents) : nil
    }
}
