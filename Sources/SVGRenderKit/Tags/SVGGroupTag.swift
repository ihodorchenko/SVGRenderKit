import UIKit

/// A group of SVG elements rendered as a single `<g>` container.
open class SVGGTag: SVGGroupObject {
    class override var key: String { get { return "g" }}

    /// Initializes a `<g>` group from an XML element and its parent group.
    public required init(xmlElement: XMLElement, addDict: [String: String]? = nil, parent: SVGGroupProtocol) throws {
        try super.init(xmlElement: xmlElement, addDict: addDict, parent: parent)
    }
}

extension SVGGTag: SVGRendering {
    /// Builds and returns a layer containing the rendered layers of this group's child elements.
    public func createLayer(addStyle: SVGSourceStyleElement?, overrideElements: [String: SVGSourceStyleElement]?) throws -> CALayer {
        let mainLayer: CAShapeLayer = CAShapeLayer()

        if let sourceStyle = sourceStyle, let display = sourceStyle.display {
            switch display {
            case .inline:
                break
            case .block:
                break
            case .none:
                mainLayer.opacity = 0
                return mainLayer
            }
        }

        for layerElement in layerElements.array {
            if let group = layerElement as? SVGGTag {
                let layer = try group.createLayer(overrideElements: overrideElements)
                if layer.sublayers?.count ?? 0 > 0 {
                    mainLayer.addSublayer(layer)
                }
            } else if let path = layerElement as? SVGShapeObject {
                let layer = try path.createLayer(overrideElements: overrideElements)
                mainLayer.addSublayer(layer)
            } else if let path = layerElement as? SVGUseTag {
                let layer = try path.createLayer(overrideElements: overrideElements)
                mainLayer.addSublayer(layer)
            }
        }

        if let transform = transform {
            mainLayer.transform = transform
        }

        return mainLayer
    }
}

/// A container group for reusable `<defs>` definitions that are not rendered directly.
open class SVGDefsGroupTag: SVGGroupObject {
    class override var key: String { get { return "defs" }}
}
