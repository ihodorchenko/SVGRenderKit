import UIKit

/// Abstraction for objects that can create a rendered layer.
protocol SVGRendering {
    /// Creates a layer for the object using the given style and override elements.
    func createLayer(addStyle: SVGSourceStyleElement?, overrideElements: [String: SVGSourceStyleElement]?) throws -> CALayer
    /// Creates a layer for the object using the given override elements.
    func createLayer(overrideElements: [String: SVGSourceStyleElement]?) throws -> CALayer
}

extension SVGRendering {
    /// Creates a layer using only the given override elements, with no additional style.
    func createLayer(overrideElements: [String: SVGSourceStyleElement]?) throws -> CALayer {
        return try createLayer(addStyle: nil, overrideElements: overrideElements)
    }
}

/// Abstraction for containers that resolve styles and look up renderable shapes.
///
/// Class-bound so child objects can hold their parent as an `unowned` reference
/// (the parent owns its children and always outlives them): this keeps the parsed
/// document a plain ownership tree instead of a web of retain cycles.
protocol SVGShapesContainer: AnyObject {
    /// Returns the resolved style for a shape, combining inherited and override styles.
    func getStyle(forObject: SVGShapeObject, overrideElements: [String: SVGSourceStyleElement]?) -> SVGSourceStyleElement
    /// Returns only the `<style>`-block rules (tag/class/id selectors) matching a shape.
    ///
    /// Per SVG, these outrank presentation attributes; inline `style` outranks them both.
    func selectorStyle(forObject: SVGShapeObject) -> SVGSourceStyleElement
    /// Returns the rendering options for the SVG document.
    func getSvgOptions() -> SVGOptions

    /// Returns a renderable matching the key, optionally searching parent containers.
    func getRendering(byKey: String, fromParents: Bool) -> SVGRendering?

    /// Returns the gradient matching the key, optionally searching parent containers.
    func getGradient(byKey: String, fromParents: Bool) -> SVGBaseGradient?

    /// Returns the clip path matching the key, optionally searching parent containers.
    func getClipPath(byKey: String, fromParents: Bool) -> SVGClipPath?

    /// Returns the mask matching the key, optionally searching parent containers.
    func getMask(byKey: String, fromParents: Bool) -> SVGMask?

    /// Returns the pattern matching the key, optionally searching parent containers.
    func getPattern(byKey: String, fromParents: Bool) -> SVGPattern?

    /// Returns the marker matching the key, optionally searching parent containers.
    func getMarker(byKey: String, fromParents: Bool) -> SVGMarker?

    /// Returns the filter matching the key, optionally searching parent containers.
    func getFilter(byKey: String, fromParents: Bool) -> SVGFilter?
}

extension SVGShapesContainer {
}

/// Abstraction for group containers that look up their child objects.
protocol SVGGroupProtocol: SVGShapesContainer {
    /// Returns the child object matching the key, optionally searching parent groups.
    func getObject(byKey: String, fromParents: Bool) -> SVGObject?

    /// Returns the group matching the key, optionally searching parent groups.
    func getG(byKey: String, fromParents: Bool) -> SVGGTag?

    /// Returns the shape matching the key, optionally searching parent groups.
    func getShape(byKey: String, fromParents: Bool) -> SVGShapeObject?

    /// Returns the symbol matching the key, optionally searching parent groups.
    func getSymbol(byKey: String, fromParents: Bool) -> SVGSymbol?

    /// Returns the linear gradient matching the key, optionally searching parent groups.
    func getLinearGradient(byKey: String, fromParents: Bool) -> SVGLinearGradientTag?

    /// Returns the radial gradient matching the key, optionally searching parent groups.
    func getRadialGradients(byKey: String, fromParents: Bool) -> SVGRadialGradientTag?

    /// Returns the `<image>` matching the key, optionally searching parent groups.
    func getImage(byKey: String, fromParents: Bool) -> SVGImage?
}

/// A rendering container (mask / pattern / marker / clipPath) that can host a `<g>`.
/// The group lookups are delegated to its parent, so the container can act as the
/// group's parent without duplicating the whole container protocol.
protocol SVGGroupHosting: SVGGroupProtocol {
    var parent: SVGGroupProtocol { get }
}

extension SVGGroupHosting {
    func getObject(byKey: String, fromParents: Bool) -> SVGObject? {
        return parent.getObject(byKey: byKey, fromParents: true)
    }
    func getG(byKey: String, fromParents: Bool) -> SVGGTag? {
        return parent.getG(byKey: byKey, fromParents: true)
    }
    func getShape(byKey: String, fromParents: Bool) -> SVGShapeObject? {
        return parent.getShape(byKey: byKey, fromParents: true)
    }
    func getSymbol(byKey: String, fromParents: Bool) -> SVGSymbol? {
        return parent.getSymbol(byKey: byKey, fromParents: true)
    }
    func getLinearGradient(byKey: String, fromParents: Bool) -> SVGLinearGradientTag? {
        return parent.getLinearGradient(byKey: byKey, fromParents: true)
    }
    func getRadialGradients(byKey: String, fromParents: Bool) -> SVGRadialGradientTag? {
        return parent.getRadialGradients(byKey: byKey, fromParents: true)
    }
    func getImage(byKey: String, fromParents: Bool) -> SVGImage? {
        return parent.getImage(byKey: byKey, fromParents: true)
    }
}

extension SVGShapesContainer {
    /// Containers without `<style>` support contribute no selector rules.
    func selectorStyle(forObject: SVGShapeObject) -> SVGSourceStyleElement {
        return SVGSourceStyleElement()
    }
}
