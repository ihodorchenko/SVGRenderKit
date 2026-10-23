import UIKit

/// A reusable `<symbol>` template. Symbols are not rendered directly; they are
/// instantiated via `<use>` and scaled to fit the instantiating element's viewport.
class SVGSymbol: SVGGroupObject {
    class override var key: String { get { return "symbol" } }

    /// The symbol's own view box, if defined.
    private(set) var viewBox: CGRect?
    /// How the view box is fitted and aligned when the symbol is instantiated.
    private(set) var preserveAspectRatio: SVGPreserveAspectRatio = SVGPreserveAspectRatio()

    /// Initializes a symbol by parsing its `viewBox` and `preserveAspectRatio` attributes and children.
    required init(xmlElement: XMLElement, addDict: [String: String]? = nil, parent: SVGGroupProtocol) throws {
        try super.init(xmlElement: xmlElement, addDict: addDict, parent: parent)

        if let str = attributeDict["viewBox"] {
            let cleaned = str.replacingOccurrences(of: ",", with: " ")
            let arr = SVGUtils.split(string: cleaned, separator: " ")
            if arr.count == 4,
               let x = Double(arr[0]), let y = Double(arr[1]),
               let w = Double(arr[2]), let h = Double(arr[3]) {
                viewBox = CGRect(x: x, y: y, width: w, height: h)
            }
        }
        preserveAspectRatio = SVGPreserveAspectRatio.get(string: attributeDict["preserveAspectRatio"])
    }
}

extension SVGSymbol: SVGRendering {
    /// Builds a layer containing the symbol's children, without view-box scaling
    /// (scaling is applied by the instantiating `<use>` element).
    func createLayer(addStyle: SVGSourceStyleElement?, overrideElements: [String: SVGSourceStyleElement]?) throws -> CALayer {
        let mainLayer: CAShapeLayer = CAShapeLayer()

        try appendChildLayers(layerElements.array, to: mainLayer, addStyle: addStyle, overrideElements: overrideElements, skipEmptyGroups: true)

        return mainLayer
    }
}
