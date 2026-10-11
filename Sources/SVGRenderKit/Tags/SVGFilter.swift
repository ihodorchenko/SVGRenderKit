import UIKit
import CoreImage

/// A drop-shadow filter primitive (`feDropShadow`).
struct SVGDropShadow {
    var dx: CGFloat = 0
    var dy: CGFloat = 0
    var stdDeviation: CGFloat = 0
    var color: UIColor = .black
    var opacity: CGFloat = 1
}

/// A `<filter>` element containing a small subset of filter primitives.
open class SVGFilter: SVGChildObject {
    class override var key: String { get { return "filter" }}

    /// The `feGaussianBlur` standard deviation, if the filter contains one.
    var blurStdDeviation: CGFloat?
    /// The `feDropShadow` effect, if the filter contains one.
    var dropShadow: SVGDropShadow?

    /// Initializes a filter by parsing its `feGaussianBlur`, `feDropShadow`, and the
    /// SVG 1.1 drop-shadow primitive chain (`feOffset` + `feFlood`).
    public required init(xmlElement: XMLElement, addDict: [String: String]? = nil, parent: SVGGroupProtocol) throws {
        try super.init(xmlElement: xmlElement, addDict: addDict, parent: parent)

        var offsetDX: CGFloat = 0
        var offsetDY: CGFloat = 0
        var floodColor: UIColor = .black
        var floodOpacity: CGFloat = 1
        var hasOffsetOrFlood = false

        for child in xmlElement.xmlChildren {
            switch child.name {
            case "feGaussianBlur":
                if let str = child.attribute(by: "stdDeviation")?.text, let f = Float(str.trimmed) {
                    blurStdDeviation = CGFloat(f)
                }
            case "feDropShadow":
                var shadow = SVGDropShadow()
                if let str = child.attribute(by: "dx")?.text, let f = Float(str.trimmed) { shadow.dx = CGFloat(f) }
                if let str = child.attribute(by: "dy")?.text, let f = Float(str.trimmed) { shadow.dy = CGFloat(f) }
                if let str = child.attribute(by: "stdDeviation")?.text, let f = Float(str.trimmed) { shadow.stdDeviation = CGFloat(f) }
                if let str = child.attribute(by: "flood-color")?.text { shadow.color = SVGColors.getColor(string: str) }
                if let str = child.attribute(by: "flood-opacity")?.text, let f = Float(str.trimmed) { shadow.opacity = CGFloat(f) }
                dropShadow = shadow
            case "feOffset":
                hasOffsetOrFlood = true
                if let str = child.attribute(by: "dx")?.text, let f = Float(str.trimmed) { offsetDX = CGFloat(f) }
                if let str = child.attribute(by: "dy")?.text, let f = Float(str.trimmed) { offsetDY = CGFloat(f) }
            case "feFlood":
                hasOffsetOrFlood = true
                if let str = child.attribute(by: "flood-color")?.text { floodColor = SVGColors.getColor(string: str) }
                if let str = child.attribute(by: "flood-opacity")?.text, let f = Float(str.trimmed) { floodOpacity = CGFloat(f) }
            default:
                break
            }
        }

        // SVG 1.1 expresses a drop-shadow as an feOffset + feFlood [+ feGaussianBlur]
        // primitive chain. Fold it into the same shadow spec used by feDropShadow.
        if dropShadow == nil, hasOffsetOrFlood {
            var shadow = SVGDropShadow()
            shadow.dx = offsetDX
            shadow.dy = offsetDY
            shadow.stdDeviation = blurStdDeviation ?? 0
            shadow.color = floodColor
            shadow.opacity = floodOpacity
            dropShadow = shadow
        }
    }
}

extension SVGFilter {
    /// Applies the parsed filter effects to the given layer.
    func apply(to layer: CALayer) {
        if let shadow = dropShadow {
            layer.shadowColor = shadow.color.cgColor
            layer.shadowOpacity = Float(shadow.opacity)
            layer.shadowRadius = shadow.stdDeviation
            layer.shadowOffset = CGSize(width: shadow.dx, height: shadow.dy)
            // The blur radius is folded into the shadow; don't also blur the layer.
            return
        }
        if let blur = blurStdDeviation, let ciFilter = CIFilter(name: "CIGaussianBlur") {
            ciFilter.setValue(blur, forKey: kCIInputRadiusKey)
            layer.filters = [ciFilter]
        }
    }
}
