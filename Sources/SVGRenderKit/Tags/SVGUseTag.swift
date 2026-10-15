import UIKit

/// Resolves and renders an SVG `<use>` element referencing another element by URL.
open class SVGUseTag: SVGObject, SVGRendering {
    class override var key: String { get { return "use" }}

    /// The owning parent. `unowned`: the parent owns this `<use>` and always outlives it.
    unowned var parent: SVGShapesContainer

    /// Presentation attributes only (no inline `style`); these rank below `<style>` rules.
    var presentationStyle: SVGSourceStyleElement = SVGSourceStyleElement()
    /// Inline `style` attribute only; ranks above `<style>` rules.
    var inlineStyle: SVGSourceStyleElement = SVGSourceStyleElement()

    var transform: CATransform3D?

    var x: CGFloat = 0
    var y: CGFloat = 0
    var width: CGFloat?
    var height: CGFloat?

    /// Initializes a `<use>` tag by parsing its `href`, `x`, `y`, and `transform` attributes.
    public required init(xmlElement: XMLElement, addDict: [String: String]? = nil, parent: SVGShapesContainer) throws {
        self.parent = parent
        try super.init(xmlElement: xmlElement, addDict: addDict)

        // Presentation attributes are applied first, then the inline `style`, which
        // outranks them; `<style>`-block rules slot between the two (B108, B119-12).
        let presentation: SVGSourceStyleElement = SVGSourceStyleElement()
        try presentation.set(attributeDict: attributeDict)
        presentationStyle = presentation

        let inline: SVGSourceStyleElement = SVGSourceStyleElement()
        if let str = attributeDict["style"] {
            try inline.set(styleStr: str, force: false)
        }
        inlineStyle = inline

        // `x`/`y` are lengths in the current user space; a unit suffix or a percentage
        // must not fail the document (B108). A percentage has no resolvable viewport
        // here, so it degrades to 0.
        if let str = attributeDict["x"] { x = SVGUseTag.offset(str) }
        if let str = attributeDict["y"] { y = SVGUseTag.offset(str) }
        if let str = attributeDict["width"], let f = Float(str.trimmed) {
            width = CGFloat(f)
        }
        if let str = attributeDict["height"], let f = Float(str.trimmed) {
            height = CGFloat(f)
        }

        if let str = attributeDict["transform"] {
            transform = try SVGTransform.get(string: str)
        }
    }

    /// The `<use>`'s own style: presentation attributes, then the `<style>`-block rules that
    /// match the element itself (a `class` or `id` on the `<use>` counts), then its inline
    /// `style` (B108, B119-12).
    private func ownStyle() -> SVGSourceStyleElement {
        var style = presentationStyle
        if let selectorStyle = (parent as? SVGGroupObject)?.selectorStyle(for: self) {
            style = style.combine(child: selectorStyle)
        }
        return style.combine(child: inlineStyle)
    }

    /// The `<use>`'s own style with the caller's per-element overrides on top.
    private func resolvedOwnStyle(overrideElements: [String: SVGSourceStyleElement]?) -> SVGSourceStyleElement {
        var style = ownStyle()
        if let overrideElements = overrideElements {
            if let tagElem = overrideElements[key] {
                style = style.combine(child: tagElem)
            }
            for className in classNames {
                if let classElem = overrideElements[className] {
                    style = style.combine(child: classElem)
                }
            }
            if let id = id, let idElem = overrideElements[id] {
                style = style.combine(child: idElem)
            }
        }
        return style
    }

    /// An `x`/`y` offset in user units, degrading a percentage or a malformed value to 0.
    private static func offset(_ string: String) -> CGFloat {
        guard let length = try? SVGLength.get(string: string) else { return 0 }
        switch length {
        case .px(let value): return value
        case .percent: return 0
        }
    }

    /// Bounds of the referenced content in the `<use>`'s own user space — the space in
    /// which its `clip-path` / `mask` / `filter` resolve. The clone is placed by the
    /// `x`/`y` translate and the `<use>`'s own transform (SVG 1.1 §5.6), so both are part
    /// of this space and the shift must not be applied a second time anywhere else
    /// (B119-8, B119-12).
    var contentBounds: CGRect? {
        guard case .local(let key)? = href,
              let rendering = parent.getRendering(byKey: key, fromParents: true) else { return nil }
        var bounds: CGRect
        if let shape = rendering as? SVGShapeObject {
            bounds = shape.path.bounds.applying(svgTransform: shape.transform)
        } else if let group = rendering as? SVGGroupObject {
            bounds = group.contentBounds.applying(svgTransform: group.transform)
        } else if let image = rendering as? SVGImage {
            bounds = image.frame(viewBox: parent.getSvgOptions().viewBox).applying(svgTransform: image.transform)
        } else {
            return nil
        }
        guard !bounds.isNull, !bounds.isEmpty else { return nil }
        // A `<symbol>` reference is fitted into the viewport the `<use>` establishes.
        if let symbol = rendering as? SVGSymbol, let viewBox = symbol.viewBox {
            bounds = bounds.applying(svgTransform: viewportFit(symbol, viewBox: viewBox))
        }
        bounds = bounds.offsetBy(dx: x, dy: y)
        return bounds.applying(svgTransform: transform)
    }

    /// The view-box fit a `<use>` of a `<symbol>` applies: the symbol's `viewBox`
    /// (`origin`/size) mapped into the viewport the `<use>` establishes (its
    /// `width`/`height`, else the viewBox size), centred per `preserveAspectRatio`.
    private func viewportFit(_ symbol: SVGSymbol, viewBox: CGRect) -> CATransform3D {
        let containerSize = CGSize(width: width ?? viewBox.width, height: height ?? viewBox.height)
        let resolved = symbol.preserveAspectRatio.resolve(viewBox: viewBox, containerSize: containerSize)
        // CATransform3D helpers *pre*-multiply: the last call is applied to the point
        // first. Desired mapping: translate(center) · scale · translate(-origin), so
        // the centering shift is in container space and must not be scaled.
        var transform = CATransform3DIdentity
        transform = CATransform3DTranslate(transform, resolved.translateX, resolved.translateY, 0)
        transform = CATransform3DScale(transform, resolved.scaleX, resolved.scaleY, 1)
        transform = CATransform3DTranslate(transform, -viewBox.origin.x, -viewBox.origin.y, 0)
        return transform
    }

    /// Resolves the referenced element and returns its layer, applying any `x`, `y`, and transform offsets.
    public func createLayer(addStyle: SVGSourceStyleElement?, overrideElements: [String: SVGSourceStyleElement]?) throws -> CALayer {
        if let href = href {
            switch href {
            case .local(let key):
                if let rendering = parent.getRendering(byKey: key, fromParents: true) {
                    // Guard against reference cycles (`<g id="a"><use href="#a"/></g>`) and cap
                    // the total expansions per render, so a fan-out chain
                    // (`<g id="b"><use href="#a"/><use href="#a"/></g>` …) cannot blow up to
                    // 2ⁿ layers (B102). Tracked per thread: a cached tree may render on
                    // several threads at once.
                    switch SVGInputLimits.enterUse(ObjectIdentifier(self)) {
                    case .cycle:
                        // A `<use>` that references one of its own ancestors is dropped and
                        // logged; the rest of the document still renders (B119-5).
                        SVGLog.addSLog(errorStr: "skipped <use> '\(key)': circular reference")
                        return CALayer()
                    case .tooDeep:
                        SVGLog.addSLog(errorStr: "skipped <use> '\(key)': nesting limit \(SVGInputLimits.maxUseDepth) reached")
                        return CALayer()
                    case .overBudget:
                        SVGLog.addSLog(errorStr: "skipped <use> '\(key)': expansion limit \(SVGInputLimits.maxUseExpansions) reached")
                        return CALayer()
                    case .ok:
                        break
                    }
                    defer { SVGInputLimits.exitUse(ObjectIdentifier(self)) }
                    // The clone inherits the `<use>`'s inheritable properties: what an
                    // enclosing `<use>` clone passes in, then what this `<use>` inherits
                    // from its ancestors, then its own properties. The compositing ones
                    // (`opacity`, `clip-path`, `mask`, `filter`) stay out of it — they
                    // apply to the clone as a whole, below (B119-1/-4, SVG 1.1 §5.6).
                    let own = resolvedOwnStyle(overrideElements: overrideElements)
                    var childStyle = addStyle ?? SVGSourceStyleElement()
                    if let ancestors = (parent as? SVGGroupObject)?.inheritedChainStyle() {
                        childStyle = childStyle.combine(child: ancestors)
                    }
                    childStyle = childStyle.combine(child: own.withoutGroupCompositing())
                    let cloneLayer = try rendering.createLayer(addStyle: childStyle, overrideElements: overrideElements)

                    // Per SVG 1.1 §5.6 the referenced content is wrapped as
                    // `<g transform="[use.transform] translate(x,y)">`, with the
                    // viewBox fit innermost. CATransform3DConcat(a, b) applies `a` to
                    // the point first, so the factors are appended left to right and
                    // the referenced element's own transform — which stays on its
                    // layer — ends up innermost of all (B119-2).
                    var placement: CATransform3D = CATransform3DIdentity
                    if let symbol = rendering as? SVGSymbol, let viewBox = symbol.viewBox {
                        placement = viewportFit(symbol, viewBox: viewBox)
                    }
                    if x != 0 || y != 0 {
                        placement = CATransform3DConcat(placement, CATransform3DMakeTranslation(x, y, 0))
                    }
                    if let transform = transform {
                        placement = CATransform3DConcat(placement, transform)
                    }
                    if !CATransform3DIsIdentity(placement) {
                        cloneLayer.transform = CATransform3DConcat(cloneLayer.transform, placement)
                    }

                    // The `<use>`'s own opacity / clip-path / mask / filter composite the
                    // referenced content as a whole, like a `<g>` (SVG 1.1 §5.6). They go on
                    // a wrapper layer so that the clone keeps its own ones (B119-1, B119-3)
                    // and so that they resolve in the `<use>`'s user space, which the
                    // x/y translate and the `<use>`'s own transform only place in the
                    // parent (B119-8, B119-12). A `<use>` without them is its clone.
                    if !own.hasGroupCompositing {
                        return cloneLayer
                    }
                    let wrapper = CAShapeLayer()
                    wrapper.addSublayer(cloneLayer)
                    try own.applyGroupComposite(to: wrapper, bbox: contentBounds ?? .zero, container: parent, overrideElements: overrideElements)
                    return wrapper
                } else {
                    SVGLog.addSLog(errorStr: "skipped <use> '\(key)': referenced element not found")
                    return CALayer()
                }
            case .web:
                SVGLog.addSLog(errorStr: "skipped <use> '\(key)': external url not supported")
                return CALayer()
            }
        } else {
            SVGLog.addSLog(errorStr: "skipped <use>: missing 'href'")
            return CALayer()
        }
    }
}
