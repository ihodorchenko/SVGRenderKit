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
    /// SVG 1.1 drop-shadow primitive chain (`feOffset` + `feFlood`) as well as the
    /// Figma/Sketch drop-shadow chain (`feColorMatrix` color tint).
    public required init(xmlElement: XMLElement, addDict: [String: String]? = nil, parent: SVGGroupProtocol) throws {
        try super.init(xmlElement: xmlElement, addDict: addDict, parent: parent)

        var offsetDX: CGFloat = 0
        var offsetDY: CGFloat = 0
        var floodColor: UIColor = .black
        var floodOpacity: CGFloat = 1
        var hasOffsetOrFlood = false
        var hasOffset = false
        // A shadow color/opacity produced by an feColorMatrix tint (Figma exports
        // drop-shadows as an alpha extraction matrix followed by a constant-color
        // matrix; the latter carries the shadow's RGB and opacity).
        var tintColor: UIColor?
        var tintOpacity: CGFloat = 1

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
                hasOffset = true
                if let str = child.attribute(by: "dx")?.text, let f = Float(str.trimmed) { offsetDX = CGFloat(f) }
                if let str = child.attribute(by: "dy")?.text, let f = Float(str.trimmed) { offsetDY = CGFloat(f) }
            case "feFlood":
                hasOffsetOrFlood = true
                if let str = child.attribute(by: "flood-color")?.text { floodColor = SVGColors.getColor(string: str) }
                if let str = child.attribute(by: "flood-opacity")?.text, let f = Float(str.trimmed) { floodOpacity = CGFloat(f) }
            case "feColorMatrix":
                if let type = child.attribute(by: "type")?.text, type.trimmed == "matrix",
                   let values = child.attribute(by: "values")?.text,
                   let matrix = SVGFilter.parseColorMatrix(values) {
                    // A shadow tint matrix maps its input to a constant RGB color:
                    // R' = v4, G' = v9, B' = v14, A' = v18 · A. It is distinguishable
                    // from the alpha-extraction matrix (whose RGB constants are zero).
                    let r = CGFloat(matrix[4])
                    let g = CGFloat(matrix[9])
                    let b = CGFloat(matrix[14])
                    let a = CGFloat(matrix[18])
                    if r != 0 || g != 0 || b != 0 {
                        tintColor = UIColor(red: r, green: g, blue: b, alpha: 1)
                        tintOpacity = a
                    }
                }
            default:
                break
            }
        }

        // Figma/Sketch drop-shadow: an feOffset + feGaussianBlur + feColorMatrix
        // color tint. The tint overrides the (transparent) feFlood background fix.
        if dropShadow == nil, hasOffset, let tintColor = tintColor {
            var shadow = SVGDropShadow()
            shadow.dx = offsetDX
            shadow.dy = offsetDY
            shadow.stdDeviation = blurStdDeviation ?? 0
            shadow.color = tintColor
            shadow.opacity = tintOpacity
            dropShadow = shadow
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

    /// Parses a 4×5 `feColorMatrix` `values` list (20 numbers) into an array.
    private static func parseColorMatrix(_ raw: String) -> [Float]? {
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ","))
        let tokens = raw.components(separatedBy: separators).filter { !$0.isEmpty }
        guard tokens.count >= 20 else { return nil }
        var values: [Float] = []
        values.reserveCapacity(20)
        for token in tokens.prefix(20) {
            guard let f = Float(token) else { return nil }
            values.append(f)
        }
        return values
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
