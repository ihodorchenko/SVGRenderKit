import UIKit

/// Abstraction for objects that can create a rendered layer.
public protocol SVGRendering {
    /// Creates a layer for the object using the given style and override elements.
    func createLayer(addStyle: SVGSourceStyleElement?, overrideElements: [String: SVGSourceStyleElement]?) throws -> CALayer
    /// Creates a layer for the object using the given override elements.
    func createLayer(overrideElements: [String: SVGSourceStyleElement]?) throws -> CALayer
}

extension SVGRendering {
    /// Creates a layer using only the given override elements, with no additional style.
    public func createLayer(overrideElements: [String: SVGSourceStyleElement]?) throws -> CALayer {
        return try createLayer(addStyle: nil, overrideElements: overrideElements)
    }
}

/// Abstraction for containers that resolve styles and look up renderable shapes.
public protocol SVGShapesContainer {
    /// Returns the resolved style for a shape, combining inherited and override styles.
    func getStyle(forObject: SVGShapeObject, overrideElements: [String: SVGSourceStyleElement]?) -> SVGSourceStyleElement
    /// Returns the rendering options for the SVG document.
    func getSvgOptions() -> SVGOptions

    /// Returns a renderable matching the key, optionally searching parent containers.
    func getRendering(byKey: String, fromParents: Bool) -> SVGRendering?

    /// Returns the gradient matching the key, optionally searching parent containers.
    func getGradient(byKey: String, fromParents: Bool) -> SVGBaseGradient?

    /// Returns the clip path matching the key, optionally searching parent containers.
    func getClipPath(byKey: String, fromParents: Bool) -> SVGClipPath?
}

extension SVGShapesContainer {
}

/// Abstraction for group containers that look up their child objects.
public protocol SVGGroupProtocol: SVGShapesContainer {
    /// Returns the child object matching the key, optionally searching parent groups.
    func getObject(byKey: String, fromParents: Bool) -> SVGObject?

    /// Returns the group matching the key, optionally searching parent groups.
    func getG(byKey: String, fromParents: Bool) -> SVGGTag?

    /// Returns the shape matching the key, optionally searching parent groups.
    func getShape(byKey: String, fromParents: Bool) -> SVGShapeObject?

    /// Returns the linear gradient matching the key, optionally searching parent groups.
    func getLinearGradient(byKey: String, fromParents: Bool) -> SVGLinearGradientTag?

    /// Returns the radial gradient matching the key, optionally searching parent groups.
    func getRadialGradients(byKey: String, fromParents: Bool) -> SVGRadialGradientTag?
}
