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

    /// Initializes a filter by parsing its `feGaussianBlur` and `feDropShadow` children.
    public required init(xmlElement: XMLElement, addDict: [String: String]? = nil, parent: SVGGroupProtocol) throws {
        try super.init(xmlElement: xmlElement, addDict: addDict, parent: parent)

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
            default:
                break
            }
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
        }
        if let blur = blurStdDeviation, let ciFilter = CIFilter(name: "CIGaussianBlur") {
            ciFilter.setValue(blur, forKey: kCIInputRadiusKey)
            layer.filters = [ciFilter]
        }
    }
}
