import UIKit

/// Base class for drawable SVG shapes that own a `UIBezierPath` and can render it to a layer.
class SVGShapeObject: SVGObject, SVGRendering {
    /// Presentation attributes only (no inline `style`); these rank below `<style>` rules.
    var presentationStyle: SVGSourceStyleElement!
    /// Inline `style` attribute only (normal priority).
    var inlineStyle: SVGSourceStyleElement!
    /// The `!important` declarations of the inline `style`; they outrank every rule.
    var inlineImportantStyle: SVGSourceStyleElement!
    /// The owning parent. `unowned`: the parent owns this shape and always outlives
    /// it, so a strong reference would retain-cycle the document.
    unowned var parent: SVGShapesContainer

    var transform: CATransform3D?
    
    var path: UIBezierPath = UIBezierPath()

    var animations: [SVGAnimation] = []
    /// Inline `style` declarations of this shape that belong to CSS animations
    /// (`animation`/`animation-*`). They are not presentation properties, so `inlineStyle`
    /// does not keep them; the runtime CSS subset resolves them separately.
    private var cssAnimationDeclarations: [(property: String, value: String)] = []
    /// The `!important` animation declarations of the inline `style`.
    private var cssImportantAnimationDeclarations: [(property: String, value: String)] = []

    /// Initializes a shape object from an XML element and its parent shapes container.
    required init(xmlElement: XMLElement, addDict: [String: String]? = nil, parent: SVGShapesContainer) throws {
        self.parent = parent
        try super.init(xmlElement: xmlElement, addDict: addDict)

        // Presentation attributes are applied first, then inline `style`, which outranks them.
        let presentation = SVGSourceStyleElement()
        try presentation.set(attributeDict: attributeDict)
        self.presentationStyle = presentation

        let inlineParts = attributeDict["style"].map { SVGSourceStyleElement.styles(from: $0) }
            ?? (normal: SVGSourceStyleElement(), important: SVGSourceStyleElement())
        inlineStyle = inlineParts.normal
        inlineImportantStyle = inlineParts.important
        if let str = attributeDict["style"] {
            for declaration in SVGSourceStyleElement.declarationsWithImportance(from: str)
            where declaration.property == "animation" || declaration.property.hasPrefix("animation-") {
                let pair = (property: declaration.property, value: declaration.value)
                if declaration.important {
                    cssImportantAnimationDeclarations.append(pair)
                } else {
                    cssAnimationDeclarations.append(pair)
                }
            }
        }

        if let str = attributeDict["transform"] {
            transform = try SVGTransform.get(string: str)
        }
        self.animations = SVGAnimation.parse(children: xmlElement.xmlChildren)
    }

    /// Cascade for the shape itself: (inherited ← `addStyle`) → presentation attributes
    /// → `<style>` rules → inline `style`.
    ///
    /// `addStyle` comes from an instantiating `<use>` and is the *lowest* priority:
    /// the referenced shape's own properties win (SVG 1.1 §5.6 — the cloned content
    /// inherits from the `use` element, it is not overridden by it).
    func resolvedStyle(overrideElements: [String: SVGSourceStyleElement]?, addStyle: SVGSourceStyleElement? = nil) -> SVGSourceStyleElement {
        var inherited = parent.getStyle(forObject: self, overrideElements: overrideElements)
        if let addStyle = addStyle {
            inherited = inherited.combine(child: addStyle)
        }
        return inherited
            .combine(child: presentationStyle)
            .combine(child: parent.selectorStyle(forObject: self))
            .combine(child: inlineStyle)
            .combine(child: parent.importantSelectorStyle(forObject: self))
            .combine(child: inlineImportantStyle)
    }

    /// Builds and returns the `CALayer` that renders this shape's path with the combined styles applied.
    func createLayer(addStyle: SVGSourceStyleElement?, overrideElements: [String: SVGSourceStyleElement]?) throws -> CALayer {
        let mainLayer: CAShapeLayer = CAShapeLayer()
        let pathLayer: CAShapeLayer = CAShapeLayer()
        pathLayer.path = self.path.cgPath
        mainLayer.addSublayer(pathLayer)

        var sourceStyle: SVGSourceStyleElement = resolvedStyle(overrideElements: overrideElements, addStyle: addStyle)
        if let overrideElements = overrideElements {
            if let tagElem = overrideElements[self.key] {
                sourceStyle = sourceStyle.combine(child: tagElem)
            }
            for className in self.classNames {
                if let idElem = overrideElements[className] {
                    sourceStyle = sourceStyle.combine(child: idElem)
                }
            }
            if let id = self.id, let idElem = overrideElements[id] {
                sourceStyle = sourceStyle.combine(child: idElem)
            }
        }

        // A mask bitmap is stretched by the shape's own transform and by its ancestors', so
        // it has to be rasterized that much larger to stay sharp (B119-6).
        let maskScale = (transform?.svgScaleFactor ?? 1) * ((parent as? SVGGroupObject)?.accumulatedScale() ?? 1)
        try sourceStyle.styling(mainLayer: mainLayer, pathLayer: pathLayer, path: path, group: parent, overrideElements: overrideElements, maskScale: maskScale)

        if let transform = transform {
            mainLayer.transform = transform
        }

        // CSS animations (the runtime subset) ride the same attach/deferred path as SMIL.
        let cssAnimations = cssAnimations(style: sourceStyle)
        if let options = getSvgOptions() {
            options.attach(animations + cssAnimations, to: mainLayer, pathLayer: pathLayer)
        } else {
            for animation in animations + cssAnimations {
                animation.apply(to: mainLayer, pathLayer: pathLayer, epoch: nil)
            }
        }

        return mainLayer
    }

    /// The CSS animations of this shape: the document's `<style>` rules matching it plus its
    /// inline `style`. Only the properties of `SVGCSSAnimations.supportedProperties` are built;
    /// the rest are logged and skipped there.
    private func cssAnimations(style: SVGSourceStyleElement) -> [SVGAnimation] {
        let declarations = parent.animationDeclarations(forObject: self) + cssAnimationDeclarations
            + parent.importantAnimationDeclarations(forObject: self) + cssImportantAnimationDeclarations
        guard !declarations.isEmpty else { return [] }
        return SVGCSSAnimations.animations(
            specs: SVGCSSAnimations.specs(from: declarations),
            keyframes: { [parent] name in parent.keyframes(named: name) },
            baseDashoffset: style.strokeDashoffset ?? 0
        )
    }

    class func create(xml: XMLElement, parent: SVGShapesContainer) throws -> SVGShapeObject? {
        switch xml.name {
        case SVGPath.key:
            return try SVGPath(xmlElement: xml, parent: parent)
        case SVGShapeRect.key:
            return try SVGShapeRect(xmlElement: xml, parent: parent)
        case SVGShapeCircle.key:
            return try SVGShapeCircle(xmlElement: xml, parent: parent)
        case SVGShapeEllipse.key:
            return try SVGShapeEllipse(xmlElement: xml, parent: parent)
        case SVGShapeLine.key:
            return try SVGShapeLine(xmlElement: xml, parent: parent)
        case SVGShapePolyline.key:
            return try SVGShapePolyline(xmlElement: xml, parent: parent)
        case SVGShapePolygon.key:
            return try SVGShapePolygon(xmlElement: xml, parent: parent)
        case SVGTextTag.key:
            return try SVGTextTag(xmlElement: xml, parent: parent)
        default:
            return nil
        }
    }

    internal func getSvgOptions() -> SVGOptions? {
        return parent.getSvgOptions()
    }

    /// Resolves a length attribute string into a value in the document's user space.
    ///
    /// Absolute CSS units (`px`, `pt`, `pc`, `in`, `cm`, `mm`) and bare numbers map
    /// to user units directly; a percentage is resolved against `reference` (a
    /// viewBox width/height, or the normalized diagonal for radii). Relative units
    /// (`em`, `ex`, …) and malformed values are out of scope and degrade to zero
    /// rather than failing the whole document.
    func resolveLength(_ raw: String?, reference: CGFloat) -> CGFloat {
        guard let raw = raw else { return 0 }
        let length = (try? SVGLength.get(string: raw)) ?? .px(value: 0)
        switch length {
        case .px(let value):
            return value
        case .percent(let value):
            return value * reference
        }
    }

    func getGradient(byKey: String, fromParents: Bool) -> SVGBaseGradient? {
        // A shape owns no gradients; only the parent chain can resolve one.
        return fromParents ? parent.getGradient(byKey: byKey, fromParents: true) : nil
    }
}

/// A drawable shape that renders an SVG `<path>` element's `d` attribute.
class SVGPath: SVGShapeObject {
    class override var key: String { get { return "path" }}

    /// Initializes a path by parsing its `d` attribute into a `UIBezierPath`.
    required init(xmlElement: XMLElement, addDict: [String: String]? = nil, parent: SVGShapesContainer) throws {
        try super.init(xmlElement: xmlElement, addDict: addDict, parent: parent)

        if let str = attributeDict["d"] {
            let result = SVGParseString.parseSVGPath(pathString: str)
            if let bezierPath = result.path {
                // Render the part of the path that parsed; a trailing error is logged.
                self.path = bezierPath
            }
            if let svgError = result.error {
                SVGLog.addSLog(errorStr: "path 'd': \(svgError)")
                if result.path == nil {
                    // No usable geometry (e.g. an empty or non-MoveTo `d`): skip the element.
                    throw svgError
                }
            }
        }
    }
}
