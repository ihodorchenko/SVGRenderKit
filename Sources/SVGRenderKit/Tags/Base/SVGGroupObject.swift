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

    var animations: [SVGAnimation] = []

    /// Initializes a group object from its XML element, parsing its children.
    public required init(xmlElement: XMLElement, addDict: [String: String]? = nil, parent: SVGGroupProtocol) throws {
        try super.init(xmlElement: xmlElement, addDict: addDict, parent: parent)

        let tsStyle: SVGSourceStyleElement = SVGSourceStyleElement()
        try tsStyle.set(attributeDict: attributeDict)
        if let str = attributeDict["style"] {
            try tsStyle.set(styleStr: str, force: false)
        }
        sourceStyle = tsStyle

        if let str = attributeDict["transform"] {
            transform = try SVGTransform.get(string: str)
        }
        self.animations = SVGAnimation.parse(children: xmlElement.xmlChildren)
        
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
        case SVGSymbol.key:
            let symbol: SVGSymbol = try SVGSymbol(xmlElement: children, parent: self)
            try self.add(symbols: [symbol])
            break
        case SVGMask.key:
            let mask: SVGMask = try SVGMask(xmlElement: children, parent: self)
            try self.add(masks: [mask])
            break
        case SVGPattern.key:
            let pattern: SVGPattern = try SVGPattern(xmlElement: children, parent: self)
            try self.add(patterns: [pattern])
            break
        case SVGMarker.key:
            let marker: SVGMarker = try SVGMarker(xmlElement: children, parent: self)
            try self.add(markers: [marker])
            break
        case SVGFilter.key:
            let filter: SVGFilter = try SVGFilter(xmlElement: children, parent: self)
            try self.add(filters: [filter])
            break
        case SVGImage.key:
            let image: SVGImage = try SVGImage(xmlElement: children, parent: self)
            try self.add(images: [image])
            break
        case "switch":
            // `<switch>` renders only the first child whose conditional-processing
            // attributes we support (SVG 1.1 §5.8). We support none of them, so pick
            // the first child without requiredFeatures/requiredExtensions/systemLanguage
            // and parse it in place — the wrapper itself is transparent and has no
            // style/transform of its own.
            for child in children.xmlChildren {
                if child.attribute(by: "requiredFeatures") == nil,
                   child.attribute(by: "requiredExtensions") == nil,
                   child.attribute(by: "systemLanguage") == nil {
                    try parse(children: child)
                    break
                }
            }
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
        // Keys are stored with a `#` prefix. A duplicate id resolves to the first definition (as in
        // browsers). Class is not a gradient identity, so distinct gradients sharing a class are kept.
        if let id = children.attribute(by: "id")?.text, let obj = all.get(key: id.hasPrefix("#") ? id : "#" + id) as? SVGLinearGradientTag {
            return obj
        }
        let obj = try SVGLinearGradientTag(xmlElement: children, parent: self)
        try self.add(linearGradients: [obj])
        return obj
    }

    @discardableResult fileprivate func addIfNeedRadialGradient(children: XMLElement) throws -> SVGRadialGradientTag {
        // Keys are stored with a `#` prefix. A duplicate id resolves to the first definition (as in
        // browsers). Class is not a gradient identity, so distinct gradients sharing a class are kept.
        if let id = children.attribute(by: "id")?.text, let obj = all.get(key: id.hasPrefix("#") ? id : "#" + id) as? SVGRadialGradientTag {
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

    /// Adds the given symbols to this group. Symbols are registered for lookup
    /// but are not rendered directly.
    public func add(symbols: [SVGSymbol]) throws {
        for symbol in symbols {
            symbol.parent = self
            self.all.add(item: symbol)
        }
    }

    /// Adds the given masks to this group. Masks are registered for lookup but
    /// are not rendered directly.
    public func add(masks: [SVGMask]) throws {
        for mask in masks {
            mask.parent = self
            self.all.add(item: mask)
        }
    }

    /// Adds the given patterns to this group. Patterns are registered for lookup
    /// but are not rendered directly.
    public func add(patterns: [SVGPattern]) throws {
        for pattern in patterns {
            pattern.parent = self
            self.all.add(item: pattern)
        }
    }

    /// Adds the given markers to this group. Markers are registered for lookup
    /// but are not rendered directly.
    public func add(markers: [SVGMarker]) throws {
        for marker in markers {
            marker.parent = self
            self.all.add(item: marker)
        }
    }

    /// Adds the given filters to this group. Filters are registered for lookup
    /// but are not rendered directly.
    public func add(filters: [SVGFilter]) throws {
        for filter in filters {
            filter.parent = self
            self.all.add(item: filter)
        }
    }

    /// Adds the given images as renderable children of this group.
    public func add(images: [SVGImage]) throws {
        for image in images {
            image.parent = self
            self.all.add(item: image)
            self.layerElements.add(item: image)
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

    /// Returns the symbol matching the key, optionally searching parent groups.
    public func getSymbol(byKey: String, fromParents: Bool) -> SVGSymbol? {
        if let defs = defs {
            if let s = defs.getSymbol(byKey: byKey, fromParents: false) {
                return s
            }
        }
        if let s = all.get(key: byKey) as? SVGSymbol {
            return s
        }
        return fromParents ? parent.getSymbol(byKey: byKey, fromParents: fromParents) : nil
    }

    /// Returns a renderable (shape, group, or symbol) matching the key, optionally searching parent groups.
    public func getRendering(byKey: String, fromParents: Bool) -> SVGRendering? {
        if let share = getShape(byKey: byKey, fromParents: true) {
            return share
        }
        if let gr = getG(byKey: byKey, fromParents: true) {
            return gr
        }
        if let symbol = getSymbol(byKey: byKey, fromParents: true) {
            return symbol
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

    /// Resolves the style for a shape: inherited group styles + `<style>`-block
    /// selectors (tag/class/id) + override elements.
    public func getStyle(
        forObject: SVGShapeObject,
        overrideElements: [String: SVGSourceStyleElement]?) -> SVGSourceStyleElement
    {
        let style = inheritedStyle(forObject: forObject, overrideElements: overrideElements)
        return style.combine(child: selectorStyle(forObject: forObject))
    }

    /// `<style>`-block selectors target the shape itself, so they override inherited
    /// group styles. Applied root→leaf so a nested `<style>` wins.
    public func selectorStyle(forObject: SVGShapeObject) -> SVGSourceStyleElement {
        var style = SVGSourceStyleElement()
        for styleTag in styleTags() {
            if let tagStyle = styleTag.byTagDict[forObject.key] {
                style = style.combine(child: tagStyle)
            }
            for className in forObject.classNames {
                if let classStyle = styleTag.byClassDict[className] {
                    style = style.combine(child: classStyle)
                }
            }
            if let idStr = forObject.id, let idStyle = styleTag.byIdDict[idStr] {
                style = style.combine(child: idStyle)
            }
        }
        return style
    }

    /// Walks up the group chain combining inherited group styles (no selectors).
    private func inheritedStyle(
        forObject: SVGShapeObject,
        overrideElements: [String: SVGSourceStyleElement]?) -> SVGSourceStyleElement
    {
        var style: SVGSourceStyleElement
        if let groupParent = parent as? SVGGroupObject {
            style = groupParent.inheritedStyle(forObject: forObject, overrideElements: overrideElements)
        } else {
            style = parent.getStyle(forObject: forObject, overrideElements: overrideElements)
        }
        if let selfStyle = sourceStyle {
            // Group-compositing properties (opacity, clip-path, mask, filter) are
            // applied to the group as a whole, not inherited to child shapes.
            let inheritable = SVGSourceStyleElement()
            inheritable.set(element: selfStyle)
            inheritable.opacity = nil
            inheritable.clipPath = nil
            inheritable.mask = nil
            inheritable.filter = nil
            style = style.combine(child: inheritable)
        }
        if let overrideElements = overrideElements {
            if let tagElem = overrideElements[key] {
                style = style.combine(child: tagElem)
            }
            for className in classNames {
                if let idElem = overrideElements[className] {
                    style = style.combine(child: idElem)
                }
            }
            if let id = id, let idElem = overrideElements[id] {
                style = style.combine(child: idElem)
            }
        }
        return style
    }

    /// Returns the `<style>` blocks in the ancestor chain, root first.
    private func styleTags() -> [SVGStyleTag] {
        var tags: [SVGStyleTag] = []
        if let groupParent = parent as? SVGGroupObject {
            tags = groupParent.styleTags()
        }
        if let styleTag = styleTag {
            tags.append(styleTag)
        }
        if let defs = defs, let styleTag = defs.styleTag {
            tags.append(styleTag)
        }
        return tags
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

    /// Returns the mask matching the key, optionally searching parent groups.
    public func getMask(byKey: String, fromParents: Bool) -> SVGMask? {
        if let defs = defs {
            if let m = defs.getMask(byKey: byKey, fromParents: false) {
                return m
            }
        }
        if let m = all.get(key: byKey) as? SVGMask {
            return m
        }
        return fromParents ? parent.getMask(byKey: byKey, fromParents: fromParents) : nil
    }

    /// Returns the pattern matching the key, optionally searching parent groups.
    public func getPattern(byKey: String, fromParents: Bool) -> SVGPattern? {
        if let defs = defs {
            if let p = defs.getPattern(byKey: byKey, fromParents: false) {
                return p
            }
        }
        if let p = all.get(key: byKey) as? SVGPattern {
            return p
        }
        return fromParents ? parent.getPattern(byKey: byKey, fromParents: fromParents) : nil
    }

    /// Returns the marker matching the key, optionally searching parent groups.
    public func getMarker(byKey: String, fromParents: Bool) -> SVGMarker? {
        if let defs = defs {
            if let m = defs.getMarker(byKey: byKey, fromParents: false) {
                return m
            }
        }
        if let m = all.get(key: byKey) as? SVGMarker {
            return m
        }
        return fromParents ? parent.getMarker(byKey: byKey, fromParents: fromParents) : nil
    }

    /// Returns the filter matching the key, optionally searching parent groups.
    public func getFilter(byKey: String, fromParents: Bool) -> SVGFilter? {
        if let defs = defs {
            if let f = defs.getFilter(byKey: byKey, fromParents: false) {
                return f
            }
        }
        if let f = all.get(key: byKey) as? SVGFilter {
            return f
        }
        return fromParents ? parent.getFilter(byKey: byKey, fromParents: fromParents) : nil
    }
}

extension SVGGroupObject {
    /// The bounding box of this group's rendered content in the group's local
    /// coordinate space (union of descendant shape bounds, ignoring transforms).
    /// Used to resolve `objectBoundingBox` clip paths and masks on a group.
    var contentBounds: CGRect {
        var result = CGRect.null
        for element in layerElements.array {
            if let shape = element as? SVGShapeObject {
                result = result.union(shape.path.bounds)
            } else if let group = element as? SVGGroupObject {
                result = result.union(group.contentBounds)
            } else if let image = element as? SVGImage {
                result = result.union(image.frame(viewBox: getSvgOptions().viewBox))
            } else if let use = element as? SVGUseTag, let bounds = use.contentBounds {
                result = result.union(bounds)
            }
        }
        return result.isNull ? .zero : result
    }
}
