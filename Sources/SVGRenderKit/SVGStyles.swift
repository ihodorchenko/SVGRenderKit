import UIKit

/// A parsed font size, which may be absolute (px) or relative to the parent (`%` / `em`).
enum SVGFontSize {
    case px(CGFloat)
    case percent(CGFloat)
    case em(CGFloat)

    /// Resolves the size to an absolute point value using the parent font size.
    func resolvedPx(relativeTo parent: CGFloat) -> CGFloat {
        switch self {
        case .px(let value): return value
        case .percent(let value): return parent * value
        case .em(let value): return parent * value
        }
    }
}

/// Holds parsed style values (fill, stroke, opacity, etc.) read from an SVG element,
/// and applies them to a rendered layer.
open class SVGSourceStyleElement {

    /// The display mode (inline, block, or none) controlling whether the element is rendered.
    open var display: SVGDisplaytype?

    /// The fill paint applied to the interior of the shape.
    open var fill: SVGPaint?
    /// The opacity of the fill, overriding the fill color's alpha when set.
    open var fillOpacity: CGFloat?
    /// The rule used to determine which regions are inside the shape for filling.
    open var fillRule: SVGFillRuleType?
    /// The overall opacity applied to the entire element.
    open var opacity: Float?

    /// The paint used to draw the outline of the shape.
    open var stroke: SVGPaint?
    /// The opacity of the stroke, overriding the stroke color's alpha when set.
    open var strokeOpacity: CGFloat?
    /// The width of the stroke outline.
    open var strokeWidth: SVGLength?

    /// The shape of the stroke line caps.
    open var strokeLinecap: SVGLineCap?
    /// The shape of the stroke line joins.
    open var strokeLinejoin: SVGLineJoin?
    /// The limit for miter joins.
    open var strokeMiterlimit: CGFloat?

    /// The dash pattern applied to the stroke (`nil` for a solid stroke).
    open var strokeDasharray: [CGFloat]?
    /// The offset into the dash pattern.
    open var strokeDashoffset: CGFloat?

    /// A reference to the clip path that masks the element.
    open var clipPath: SVGFuncIRI?

    var fontFamily: String?
    var fontStyle: SVGFontStyle?
    var fontWeight: Float?
    var fontSize: SVGFontSize?

    /// Creates an empty style element with no values set.
    public init() {
    }

    /// Creates a style element initialized from fill and stroke colors and a stroke width.
    public init(fill: UIColor?, stroke: UIColor?, strokeWidth: SVGLength?) {
        if let fill = fill {
            self.fill = SVGPaint.color(color: fill)
        }
        if let stroke = stroke {
            self.stroke = SVGPaint.color(color: stroke)
        }
        self.strokeWidth = strokeWidth
    }

    func combine(child: SVGSourceStyleElement) -> SVGSourceStyleElement {
        let newElem: SVGSourceStyleElement = SVGSourceStyleElement()
        newElem.set(element: self)
        if let display = child.display { newElem.display = display }
        if let fill = child.fill { newElem.fill = fill }
        if let fillOpacity = child.fillOpacity { newElem.fillOpacity = fillOpacity }
        if let fillRule = child.fillRule { newElem.fillRule = fillRule }
        if let opacity = child.opacity { newElem.opacity = opacity }
        if let stroke = child.stroke { newElem.stroke = stroke }
        if let strokeOpacity = child.strokeOpacity { newElem.strokeOpacity = strokeOpacity }
        if let strokeWidth = child.strokeWidth { newElem.strokeWidth = strokeWidth }
        if let strokeLinecap = child.strokeLinecap { newElem.strokeLinecap = strokeLinecap }
        if let strokeLinejoin = child.strokeLinejoin { newElem.strokeLinejoin = strokeLinejoin }
        if let strokeMiterlimit = child.strokeMiterlimit { newElem.strokeMiterlimit = strokeMiterlimit }
        if let strokeDasharray = child.strokeDasharray { newElem.strokeDasharray = strokeDasharray }
        if let strokeDashoffset = child.strokeDashoffset { newElem.strokeDashoffset = strokeDashoffset }
        if let clipPath = child.clipPath { newElem.clipPath = clipPath }

        if let fontFamily = child.fontFamily { newElem.fontFamily = fontFamily }
        if let fontStyle = child.fontStyle { newElem.fontStyle = fontStyle }
        if let fontWeight = child.fontWeight { newElem.fontWeight = fontWeight }
        if let fontSize = child.fontSize {
            let parentSize: CGFloat
            if case .px(let value)? = self.fontSize { parentSize = value } else { parentSize = 17.0 }
            newElem.fontSize = .px(fontSize.resolvedPx(relativeTo: parentSize))
        }

        return newElem
    }

    func set(element: SVGSourceStyleElement) {
        display = element.display
        fill = element.fill
        fillOpacity = element.fillOpacity
        fillRule = element.fillRule
        opacity = element.opacity
        stroke = element.stroke
        strokeOpacity = element.strokeOpacity
        strokeWidth = element.strokeWidth
        strokeLinecap = element.strokeLinecap
        strokeLinejoin = element.strokeLinejoin
        strokeMiterlimit = element.strokeMiterlimit
        strokeDasharray = element.strokeDasharray
        strokeDashoffset = element.strokeDashoffset
        clipPath = element.clipPath

        fontFamily = element.fontFamily
        fontStyle = element.fontStyle
        fontWeight = element.fontWeight
        fontSize = element.fontSize
    }

    func set(styleStr: String, force: Bool = false) throws {
        let params: [String] = SVGUtils.split(string: styleStr, separator: ";")

        var paramsDict: [String : String] = [:]
        for param in params {
            let arr = SVGUtils.split(string: param, separator: ":")
            if arr.count == 2 {
                let key = SVGUtils.trimmed(string: arr[0]).lowercased()
                let value = SVGUtils.trimmed(string: arr[1])
                if paramsDict[key] == nil || force {
                    paramsDict[key] = value
                }
            }
        }
        try set(attributeDict: paramsDict)
    }

    func set(attributeDict: [String: String]) throws {
        if let str = attributeDict["display"], !str.isEmpty { try setDisplay(str: str) }
        if let str = attributeDict["fill"], !str.isEmpty { try setFill(str: str) }
        if let str = attributeDict["opacity"], !str.isEmpty { try setOpacity(str: str) }
        if let str = attributeDict["fill-opacity"], !str.isEmpty { try setFillOpacity(str: str) }
        if let str = attributeDict["fill-rule"], !str.isEmpty { setFillRule(str: str) }

        if let str = attributeDict["stroke"], !str.isEmpty { try setStroke(str: str) }
        if let str = attributeDict["stroke-opacity"], !str.isEmpty { try setStrokeOpacity(str: str) }
        if let str = attributeDict["stroke-width"], !str.isEmpty { try setStrokeWidth(str: str) }
        if let str = attributeDict["stroke-linecap"], !str.isEmpty { try setStrokeLinecap(str: str) }
        if let str = attributeDict["stroke-linejoin"], !str.isEmpty { try setStrokeLinejoin(str: str) }
        if let str = attributeDict["stroke-miterlimit"], !str.isEmpty { try setStrokeMiterlimit(str: str) }
        if let str = attributeDict["stroke-dasharray"], !str.isEmpty { try setStrokeDasharray(str: str) }
        if let str = attributeDict["stroke-dashoffset"], !str.isEmpty { try setStrokeDashoffset(str: str) }

        if let str = attributeDict["clip-path"], !str.isEmpty { try setClipPath(str: str) }

        if let str = attributeDict["font-family"], !str.isEmpty { setFontFamily(str: str) }
        if let str = attributeDict["font-style"], !str.isEmpty { try setFontStyle(str: str) }
        if let str = attributeDict["font-weight"], !str.isEmpty { try setFontWeight(str: str) }
        if let str = attributeDict["font-size"], !str.isEmpty { setFontSize(str: str) }
    }

    func setDisplay(str: String) throws {
        if let f = SVGDisplaytype.init(rawValue: str) {
            display = f
        } else {
            throw SVGError.content(text: "display not supported: \(str)")
        }
    }

    func setFill(str: String) throws {
        fill = try SVGPaint.get(string: str)
    }

    func setFillOpacity(str: String) throws {
        if let f: Float = Float(str) {
            fillOpacity = CGFloat(f)
        } else {
            throw SVGError.content(text: "wrong fillOpacity: \(str)")
        }
    }

    func setOpacity(str: String) throws {
        if let f: Float = Float(str), f >= 0, f <= 1 {
            opacity = f
        } else {
            throw SVGError.content(text: "wrong opacity: \(str)")
        }
    }

    func setFillRule(str: String) {
        if let f = SVGFillRuleType.init(rawValue: str) {
            fillRule = f
        }
    }

    func setStroke(str: String) throws {
        stroke = try SVGPaint.get(string: str)
    }

    func setStrokeOpacity(str: String) throws {
        if let f: Float = Float(str), f >= 0, f <= 1 {
            strokeOpacity = CGFloat(f)
        } else {
            throw SVGError.content(text: "wrong strokeOpacity: \(str)")
        }
    }

    func setStrokeWidth(str: String) throws {
        self.strokeWidth = try SVGLength.get(string: str)
    }

    func setStrokeLinecap(str: String) throws {
        if let value = SVGLineCap(rawValue: str) {
            strokeLinecap = value
        } else if str != "inherit" {
            throw SVGError.content(text: "wrong stroke-linecap: \(str)")
        }
    }

    func setStrokeLinejoin(str: String) throws {
        if let value = SVGLineJoin(rawValue: str) {
            strokeLinejoin = value
        } else if str != "inherit" {
            throw SVGError.content(text: "wrong stroke-linejoin: \(str)")
        }
    }

    func setStrokeMiterlimit(str: String) throws {
        if let f = Float(str), f >= 1 {
            strokeMiterlimit = CGFloat(f)
        } else {
            throw SVGError.content(text: "wrong stroke-miterlimit: \(str)")
        }
    }

    func setStrokeDasharray(str: String) throws {
        let trimmed = SVGUtils.trimmed(string: str)
        if trimmed == "none" {
            strokeDasharray = nil
            return
        }

        var separators = CharacterSet.whitespacesAndNewlines
        separators.insert(",")
        let parts = SVGUtils.split(string: trimmed, separatorSet: separators)

        var values: [CGFloat] = []
        for part in parts {
            guard let f = Float(part) else {
                throw SVGError.content(text: "wrong stroke-dasharray value: \(part)")
            }
            values.append(CGFloat(f))
        }

        // A zero-length dash pattern is equivalent to a solid stroke.
        if values.isEmpty || values.reduce(0, +) == 0 {
            strokeDasharray = nil
            return
        }

        // An odd-length pattern is doubled so it repeats evenly.
        if values.count % 2 == 1 {
            values.append(contentsOf: values)
        }
        strokeDasharray = values
    }

    func setStrokeDashoffset(str: String) throws {
        if let f = Float(str) {
            strokeDashoffset = CGFloat(f)
        } else {
            throw SVGError.content(text: "wrong stroke-dashoffset: \(str)")
        }
    }

    func setClipPath(str: String) throws {
        self.clipPath = try SVGFuncIRI.get(fullStr: str)
    }

    func setFontFamily(str: String) {
        self.fontFamily = str
    }

    func setFontStyle(str: String) throws {
        if let style = SVGFontStyle.init(rawValue: str) {
            fontStyle = style
        } else {
            throw SVGError.content(text: "wrong font-style: \(str)")
        }
    }

    func setFontWeight(str: String) throws {
        switch str {
        case "normal":
            fontWeight = 400
            break
        case "bold":
            fontWeight = 700
            break
        case "bolder":
            fontWeight = 900
            break
        case "lighter":
            fontWeight = 100
            break
        default:
            if let f: Float = Float(str), f >= 0 {
                fontWeight = f
            } else {
                throw SVGError.content(text: "wrong font-weight: \(str)")
            }
            break
        }
    }

    func setFontSize(str: String) {
        var string = str.trimmed
        if string.hasSuffix("px") {
            string.removeLast(2)
            string = string.trimmed
            if let f = Float(string) { fontSize = .px(CGFloat(f)) }
        } else if string.hasSuffix("%") {
            string.removeLast(1)
            string = string.trimmed
            if let f = Float(string) { fontSize = .percent(CGFloat(f / 100.0)) }
        } else if string.hasSuffix("em") {
            string.removeLast(2)
            string = string.trimmed
            if let f = Float(string) { fontSize = .em(CGFloat(f)) }
        } else if let f = Float(string) {
            fontSize = .px(CGFloat(f))
        }
    }
}

extension SVGSourceStyleElement {
    internal func styling(
        mainLayer: CAShapeLayer,
        pathLayer: CAShapeLayer,
        path: UIBezierPath,
        group: SVGShapesContainer,
        overrideElements: [String: SVGSourceStyleElement]?
    ) throws {
        let display = self.display ?? .inline
        let fill = self.fill ?? .color(color: .black)
        let fillOpacity = self.fillOpacity
        let fillRule = self.fillRule ?? .nonzero
        let opacity = self.opacity ?? 1.0
        let stroke = self.stroke ?? .none
        let strokeOpacity = self.strokeOpacity ?? 1
        let strokeWidth = self.strokeWidth ?? .px(value: 1)
        let clipPath = self.clipPath

        switch display {
        case .inline, .block:
            break
        case .none:
            mainLayer.opacity = 0
            return
        }

        switch fill {
        case .none:
            pathLayer.fillColor = nil
        case .currentColor:
            break
        case .color(let color):
            if let fillOpacity = fillOpacity {
                pathLayer.fillColor = color.withAlphaComponent(fillOpacity).cgColor
            } else {
                pathLayer.fillColor = color.cgColor
            }
        case .funcIRI(let iri):
            switch iri {
            case .local(let key):
                if let gradient = group.getGradient(byKey: key, fromParents: true) {
                    try applyGradient(mainLayer: mainLayer, pathLayer: pathLayer, path: path, gradient: gradient, group: group, opacity: Float(fillOpacity ?? 1.0))
                } else {
                    throw SVGError.content(text: "local iri not found by key: \(key)")
                }
            case .web(let url):
                throw SVGError.content(text: "web iri not supported: \(url)")
            }
        }

        switch fillRule {
        case .nonzero:
            pathLayer.fillRule = .nonZero
        case .evenodd:
            pathLayer.fillRule = .evenOdd
        case .inherit:
            pathLayer.fillRule = .nonZero
        }

        if opacity >= 0, opacity <= 1 {
            mainLayer.opacity = opacity
        } else {
            mainLayer.opacity = 1
        }

        switch stroke {
        case .none, .currentColor:
            break
        case .color(let color):
            switch strokeWidth {
            case .px(let value):
                pathLayer.lineWidth = value
            case .percent(let value):
                pathLayer.lineWidth = 1 * value
            }
            pathLayer.strokeColor = color.withAlphaComponent(strokeOpacity).cgColor
        case .funcIRI(let iri):
            throw SVGError.content(text: "stroke iri not supported: \(iri)")
        }

        if let strokeLinecap = self.strokeLinecap {
            switch strokeLinecap {
            case .butt:
                pathLayer.lineCap = .butt
            case .round:
                pathLayer.lineCap = .round
            case .square:
                pathLayer.lineCap = .square
            }
        }
        if let strokeLinejoin = self.strokeLinejoin {
            switch strokeLinejoin {
            case .miter:
                pathLayer.lineJoin = .miter
            case .round:
                pathLayer.lineJoin = .round
            case .bevel:
                pathLayer.lineJoin = .bevel
            }
        }
        if let strokeMiterlimit = self.strokeMiterlimit {
            pathLayer.miterLimit = strokeMiterlimit
        }
        if let strokeDasharray = self.strokeDasharray {
            pathLayer.lineDashPattern = strokeDasharray.map { NSNumber(value: Double($0)) }
        }
        if let strokeDashoffset = self.strokeDashoffset {
            pathLayer.lineDashPhase = strokeDashoffset
        }

        if let clipPath = clipPath {
            switch clipPath {
            case .local(let key):
                if let rendering = try group.getClipPath(byKey: key, fromParents: true)?.createLayer(overrideElements: overrideElements) {
                    if let rendering = rendering as? CAShapeLayer {
                        rendering.fillRule = .nonZero
                    }
                    mainLayer.mask = rendering
                } else {
                    throw SVGError.content(text: "iri not found: \(key)")
                }
            case .web(let url):
                throw SVGError.content(text: "web iri not supported: \(url)")
            }
        }
    }

    private func applyGradient(
        mainLayer: CAShapeLayer,
        pathLayer: CAShapeLayer,
        path: UIBezierPath,
        gradient: SVGBaseGradient,
        group: SVGShapesContainer,
        opacity: Float? = nil
    ) throws {
        if gradient.isEnable() {
            let options = group.getSvgOptions()
            pathLayer.fillColor = UIColor.clear.cgColor
            let maskLayer = CAShapeLayer()
            maskLayer.path = path.cgPath
            if let gradLayer = gradient.getGradientLayer(maskLayer: maskLayer, path: path, viewBox: options.viewBox) {
                if let opacity = opacity {
                    gradLayer.opacity = opacity
                }
                mainLayer.insertSublayer(gradLayer, at: 0)
            }
        } else {
            throw SVGError.content(text: "wrong content in gradient")
        }
    }
}
