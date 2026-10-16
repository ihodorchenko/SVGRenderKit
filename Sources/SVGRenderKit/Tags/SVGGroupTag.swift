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
        let ownStyle = self.ownStyle()

        if let display = ownStyle.display {
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

        try appendChildLayers(layerElements.array, to: mainLayer, addStyle: addStyle, overrideElements: overrideElements, skipEmptyGroups: true)

        if let transform = transform {
            mainLayer.transform = transform
        }

        try ownStyle.applyGroupComposite(to: mainLayer, bbox: contentBounds, container: self, overrideElements: overrideElements, maskScale: accumulatedScale())

        for anim in animations {
            anim.apply(to: mainLayer, pathLayer: nil, epoch: getSvgOptions().animationEpoch)
        }

        return mainLayer
    }
}

/// A container group for reusable `<defs>` definitions that are not rendered directly.
open class SVGDefsGroupTag: SVGGroupObject {
    class override var key: String { get { return "defs" }}
}

/// Renders every drawable child of a container, in document order, into `mainLayer`
/// (shared by `<g>`, `<svg>`, `<symbol>` and `<pattern>`). A `<g>` that produced no sublayers
/// is dropped unless `skipEmptyGroups` is false.
func appendChildLayers(_ elements: [SVGObject], to mainLayer: CALayer, addStyle: SVGSourceStyleElement?,
                       overrideElements: [String: SVGSourceStyleElement]?, skipEmptyGroups: Bool) throws {
    for element in elements {
        let layer: CALayer
        if let group = element as? SVGGTag {
            layer = try group.createLayer(addStyle: addStyle, overrideElements: overrideElements)
            if skipEmptyGroups, (layer.sublayers?.count ?? 0) == 0 { continue }
        } else if let shape = element as? SVGShapeObject {
            layer = try shape.createLayer(addStyle: addStyle, overrideElements: overrideElements)
        } else if let use = element as? SVGUseTag {
            layer = try use.createLayer(addStyle: addStyle, overrideElements: overrideElements)
        } else if let image = element as? SVGImage {
            layer = try image.createLayer(addStyle: addStyle, overrideElements: overrideElements)
        } else {
            continue
        }
        mainLayer.addSublayer(layer)
    }
}

/// A `<mask>`, `<pattern>` or `<marker>`: a container whose children (shapes, `<use>`, `<g>`,
/// `<image>`) are parsed and stored the same way.
protocol SVGContentHosting: SVGGroupHosting {
    var all: SVGTags<SVGObject> { get }
    var groups: SVGTags<SVGGTag> { get }
    var images: SVGTags<SVGImage> { get }
    func add(uses: [SVGUseTag]) throws
    func add(shapes: [SVGShapeObject]) throws
}

extension SVGContentHosting {
    func parse(children: XMLElement) throws {
        switch children.name {
        case SVGUseTag.key:
            let use: SVGUseTag = try SVGUseTag(xmlElement: children, parent: self)
            try self.add(uses: [use])
        case SVGGTag.key:
            let group: SVGGTag = try SVGGTag(xmlElement: children, parent: self)
            self.groups.add(item: group)
            self.all.add(item: group)
        case SVGImage.key:
            let image: SVGImage = try SVGImage(xmlElement: children, parent: self)
            self.images.add(item: image)
            self.all.add(item: image)
        default:
            if let shapeTag = try SVGShapeObject.create(xml: children, parent: self) {
                try self.add(shapes: [shapeTag])
            }
        }
    }
}
