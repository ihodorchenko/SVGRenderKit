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
    /// Whether the element is visible (`visible`, `hidden`, or `collapse`).
    open var visibility: SVGVisibility?

    /// The fill paint applied to the interior of the shape.
    open var fill: SVGPaint?
    /// The current text color (`color` property), used to resolve `currentColor`.
    open var color: UIColor?
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
    /// The rule used to determine which regions are inside the clipping path.
    open var clipRule: SVGClipRuleType?

    /// A reference to the mask applied to the element.
    open var mask: SVGFuncIRI?

    /// The marker drawn at the start vertex of the shape.
    open var markerStart: SVGFuncIRI?
    /// The marker drawn at intermediate vertices of the shape.
    open var markerMid: SVGFuncIRI?
    /// The marker drawn at the end vertex of the shape.
    open var markerEnd: SVGFuncIRI?

    /// A reference to the filter applied to the element.
    open var filter: SVGFuncIRI?

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
        if let visibility = child.visibility { newElem.visibility = visibility }
        if let fill = child.fill { newElem.fill = fill }
        if let color = child.color { newElem.color = color }
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
        if let clipRule = child.clipRule { newElem.clipRule = clipRule }
        if let mask = child.mask { newElem.mask = mask }
        if let markerStart = child.markerStart { newElem.markerStart = markerStart }
        if let markerMid = child.markerMid { newElem.markerMid = markerMid }
        if let markerEnd = child.markerEnd { newElem.markerEnd = markerEnd }
        if let filter = child.filter { newElem.filter = filter }

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
        visibility = element.visibility
        fill = element.fill
        color = element.color
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
        clipRule = element.clipRule
        mask = element.mask
        markerStart = element.markerStart
        markerMid = element.markerMid
        markerEnd = element.markerEnd
        filter = element.filter

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
        if let str = attributeDict["visibility"], !str.isEmpty { setVisibility(str: str) }
        if let str = attributeDict["fill"], !str.isEmpty { try setFill(str: str) }
        if let str = attributeDict["color"], !str.isEmpty { setColor(str: str) }
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
        if let str = attributeDict["clip-rule"], !str.isEmpty { setClipRule(str: str) }
        if let str = attributeDict["mask"], !str.isEmpty { try setMask(str: str) }
        if let str = attributeDict["marker-start"], !str.isEmpty { try setMarkerStart(str: str) }
        if let str = attributeDict["marker-mid"], !str.isEmpty { try setMarkerMid(str: str) }
        if let str = attributeDict["marker-end"], !str.isEmpty { try setMarkerEnd(str: str) }
        if let str = attributeDict["filter"], !str.isEmpty { try setFilter(str: str) }

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

    func setVisibility(str: String) {
        // Unknown values degrade to visible rather than failing the document.
        visibility = SVGVisibility(rawValue: str) ?? .visible
    }

    func setFill(str: String) throws {
        fill = try SVGPaint.get(string: str)
    }

    func setColor(str: String) {
        let trimmed = SVGUtils.trimmed(string: str)
        if trimmed == "inherit" || trimmed == "currentColor" {
            color = nil
            return
        }
        color = SVGColors.getColor(string: trimmed)
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
        }
        // Unknown values (including "inherit" and exporters' "null") are ignored.
    }

    func setStrokeLinejoin(str: String) throws {
        if let value = SVGLineJoin(rawValue: str) {
            strokeLinejoin = value
        }
        // Unknown values (including "inherit" and exporters' "null") are ignored.
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
            guard let f = Float(part), f >= 0 else {
                // Invalid dash value (e.g. an exporter's "null"): treat as no dash.
                strokeDasharray = nil
                return
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

    func setClipRule(str: String) {
        if let f = SVGClipRuleType.init(rawValue: str) {
            clipRule = f
        }
    }

    func setMask(str: String) throws {
        self.mask = try SVGFuncIRI.get(fullStr: str)
    }

    func setMarkerStart(str: String) throws {
        self.markerStart = try SVGFuncIRI.get(fullStr: str)
    }

    func setMarkerMid(str: String) throws {
        self.markerMid = try SVGFuncIRI.get(fullStr: str)
    }

    func setMarkerEnd(str: String) throws {
        self.markerEnd = try SVGFuncIRI.get(fullStr: str)
    }

    func setFilter(str: String) throws {
        self.filter = try SVGFuncIRI.get(fullStr: str)
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
        let clipPath = self.clipPath
        let strokeViewBox = group.getSvgOptions().viewBox
        let resolvedStrokeWidth = strokeWidthPixels(viewBox: strokeViewBox)

        switch display {
        case .inline, .block:
            break
        case .none:
            mainLayer.opacity = 0
            return
        }

        if let visibility = self.visibility, visibility != .visible {
            mainLayer.isHidden = true
        }

        switch fill {
        case .none:
            pathLayer.fillColor = nil
        case .currentColor:
            let resolvedColor = self.color ?? .black
            if let fillOpacity = fillOpacity {
                pathLayer.fillColor = resolvedColor.withAlphaComponent(resolvedColor.cgColor.alpha * fillOpacity).cgColor
            } else {
                pathLayer.fillColor = resolvedColor.cgColor
            }
        case .color(let color):
            if let fillOpacity = fillOpacity {
                pathLayer.fillColor = color.withAlphaComponent(color.cgColor.alpha * fillOpacity).cgColor
            } else {
                pathLayer.fillColor = color.cgColor
            }
        case .funcIRI(let iri):
            switch iri {
            case .local(let key):
                if let gradient = group.getGradient(byKey: key, fromParents: true) {
                    try applyGradient(mainLayer: mainLayer, pathLayer: pathLayer, path: path, gradient: gradient, group: group, opacity: Float(fillOpacity ?? 1.0))
                } else if let pattern = group.getPattern(byKey: key, fromParents: true) {
                    applyPattern(pathLayer: pathLayer, pattern: pattern, group: group, path: path, opacity: fillOpacity)
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
        case .none:
            break
        case .currentColor:
            let resolvedColor = self.color ?? .black
            pathLayer.lineWidth = resolvedStrokeWidth
            pathLayer.strokeColor = resolvedColor.withAlphaComponent(resolvedColor.cgColor.alpha * strokeOpacity).cgColor
        case .color(let color):
            pathLayer.lineWidth = resolvedStrokeWidth
            pathLayer.strokeColor = color.withAlphaComponent(color.cgColor.alpha * strokeOpacity).cgColor
        case .funcIRI(let iri):
            switch iri {
            case .local(let key):
                if let gradient = group.getGradient(byKey: key, fromParents: true) {
                    try applyStrokeGradient(mainLayer: mainLayer, path: path, gradient: gradient, group: group, opacity: strokeOpacity)
                } else if let pattern = group.getPattern(byKey: key, fromParents: true) {
                    applyStrokePattern(mainLayer: mainLayer, path: path, pattern: pattern, viewBox: strokeViewBox, opacity: strokeOpacity)
                } else {
                    throw SVGError.content(text: "local stroke iri not found by key: \(key)")
                }
            case .web(let url):
                throw SVGError.content(text: "web stroke iri not supported: \(url)")
            }
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
                if let clipPathObj = group.getClipPath(byKey: key, fromParents: true) {
                    let rendering = try clipPathObj.createLayer(overrideElements: overrideElements)
                    if clipPathObj.clipPathUnits == .objectBoundingBox {
                        // The clip path's coordinates are in [0,1] object-bounding-box
                        // units; map them onto the element's bbox via
                        // translate(origin) · scale(size). CATransform3D helpers
                        // post-multiply, so emit translate first, then scale.
                        let bbox = path.bounds
                        var t = CATransform3DIdentity
                        t = CATransform3DTranslate(t, bbox.origin.x, bbox.origin.y, 0)
                        t = CATransform3DScale(t, bbox.width, bbox.height, 1)
                        rendering.transform = CATransform3DConcat(t, rendering.transform)
                    }
                    mainLayer.mask = rendering
                } else {
                    throw SVGError.content(text: "iri not found: \(key)")
                }
            case .web(let url):
                throw SVGError.content(text: "web iri not supported: \(url)")
            }
        }

        if let mask = self.mask {
            switch mask {
            case .local(let key):
                if let maskObj = group.getMask(byKey: key, fromParents: true) {
                    let options = group.getSvgOptions()
                    let rendering = try maskObj.maskLayer(bbox: path.bounds, viewBox: options.viewBox, overrideElements: overrideElements)
                    mainLayer.mask = rendering
                } else {
                    throw SVGError.content(text: "mask not found: \(key)")
                }
            case .web(let url):
                throw SVGError.content(text: "web mask not supported: \(url)")
            }
        }

        let vertices = SVGUtils.pathVertices(path: path)

        // marker-start
        if let markerStart = self.markerStart {
            let info: (point: CGPoint, tangent: CGPoint)?
            if vertices.count >= 2 {
                info = (vertices[0], CGPoint(x: vertices[1].x - vertices[0].x, y: vertices[1].y - vertices[0].y))
            } else {
                info = vertices.first.map { ($0, CGPoint.zero) }
            }
            if let info = info {
                try applyMarker(iri: markerStart, at: info, mainLayer: mainLayer, group: group, strokeWidth: resolvedStrokeWidth, overrideElements: overrideElements)
            }
        }

        // marker-mid (all vertices except the start and end)
        if let markerMid = self.markerMid, vertices.count >= 3 {
            for i in 1..<(vertices.count - 1) {
                let tangent = CGPoint(x: vertices[i + 1].x - vertices[i].x, y: vertices[i + 1].y - vertices[i].y)
                try applyMarker(iri: markerMid, at: (vertices[i], tangent), mainLayer: mainLayer, group: group, strokeWidth: resolvedStrokeWidth, overrideElements: overrideElements)
            }
        }

        // marker-end
        if let markerEnd = self.markerEnd {
            let endInfo = SVGUtils.pathEndInfo(path: path)
            try applyMarker(iri: markerEnd, at: (endInfo.point, endInfo.tangent), mainLayer: mainLayer, group: group, strokeWidth: resolvedStrokeWidth, overrideElements: overrideElements)
        }

        if let filter = self.filter {
            switch filter {
            case .local(let key):
                if let filter = group.getFilter(byKey: key, fromParents: true) {
                    filter.apply(to: mainLayer)
                } else {
                    throw SVGError.content(text: "filter not found: \(key)")
                }
            case .web(let url):
                throw SVGError.content(text: "web filter not supported: \(url)")
            }
        }
    }

    /// Applies group-compositing properties (`visibility`, `opacity`, `clip-path`,
    /// `mask`, `filter`) to a group's composite layer. Unlike fill/stroke, these
    /// are not inherited to child shapes; they composite the whole group.
    func applyGroupComposite(to layer: CALayer, bbox: CGRect, container: SVGShapesContainer, overrideElements: [String: SVGSourceStyleElement]?) throws {
        if let visibility = self.visibility, visibility != .visible {
            layer.isHidden = true
            return
        }

        if let opacity = self.opacity {
            layer.opacity = (opacity >= 0 && opacity <= 1) ? opacity : 1
        }

        if let clipPath = self.clipPath {
            switch clipPath {
            case .local(let key):
                guard let clipPathObj = container.getClipPath(byKey: key, fromParents: true) else {
                    throw SVGError.content(text: "iri not found: \(key)")
                }
                let rendering = try clipPathObj.createLayer(overrideElements: overrideElements)
                if clipPathObj.clipPathUnits == .objectBoundingBox {
                    // Map [0,1] object-bounding-box units onto the group's bbox.
                    // CATransform3D helpers post-multiply, so translate then scale.
                    var t = CATransform3DIdentity
                    t = CATransform3DTranslate(t, bbox.origin.x, bbox.origin.y, 0)
                    t = CATransform3DScale(t, bbox.width, bbox.height, 1)
                    rendering.transform = CATransform3DConcat(t, rendering.transform)
                } else if !CATransform3DIsIdentity(layer.transform) {
                    // userSpaceOnUse: the clip is in the parent (user) space. Bring
                    // it into this layer's local space so the layer's own transform
                    // maps it back to the user space on screen.
                    rendering.transform = CATransform3DConcat(CATransform3DInvert(layer.transform), rendering.transform)
                }
                layer.mask = rendering
            case .web(let url):
                throw SVGError.content(text: "web iri not supported: \(url)")
            }
        }

        if let mask = self.mask {
            switch mask {
            case .local(let key):
                guard let maskObj = container.getMask(byKey: key, fromParents: true) else {
                    throw SVGError.content(text: "mask not found: \(key)")
                }
                let options = container.getSvgOptions()
                layer.mask = try maskObj.maskLayer(bbox: bbox, viewBox: options.viewBox, overrideElements: overrideElements)
            case .web(let url):
                throw SVGError.content(text: "web mask not supported: \(url)")
            }
        }

        if let filter = self.filter {
            switch filter {
            case .local(let key):
                guard let filterObj = container.getFilter(byKey: key, fromParents: true) else {
                    throw SVGError.content(text: "filter not found: \(key)")
                }
                filterObj.apply(to: layer)
            case .web(let url):
                throw SVGError.content(text: "web filter not supported: \(url)")
            }
        }
    }

    private func applyPattern(pathLayer: CAShapeLayer, pattern: SVGPattern, group: SVGShapesContainer, path: UIBezierPath, opacity: CGFloat?) {
        if let image = pattern.tileImage(bbox: path.bounds, viewBox: group.getSvgOptions().viewBox) {
            let color = UIColor(patternImage: image)
            pathLayer.fillColor = (opacity.map { color.withAlphaComponent(min(max($0, 0), 1)) } ?? color).cgColor
        }
    }

    /// Resolves the stroke width to pixels. A percentage refers to the normalized
    /// diagonal of the viewport — `sqrt((w^2 + h^2) / 2)` — per the SVG spec.
    private func strokeWidthPixels(viewBox: CGRect) -> CGFloat {
        switch self.strokeWidth ?? .px(value: 1) {
        case .px(let value):
            return value
        case .percent(let value):
            let diagonal = sqrt((viewBox.width * viewBox.width + viewBox.height * viewBox.height) / 2)
            return value * diagonal
        }
    }

    private func strokedPath(from path: UIBezierPath, viewBox: CGRect) -> CGPath {
        let lineCap: CGLineCap
        switch self.strokeLinecap ?? .butt {
        case .butt: lineCap = .butt
        case .round: lineCap = .round
        case .square: lineCap = .square
        }
        let lineJoin: CGLineJoin
        switch self.strokeLinejoin ?? .miter {
        case .miter: lineJoin = .miter
        case .round: lineJoin = .round
        case .bevel: lineJoin = .bevel
        }
        return path.cgPath.copy(
            strokingWithWidth: strokeWidthPixels(viewBox: viewBox),
            lineCap: lineCap,
            lineJoin: lineJoin,
            miterLimit: self.strokeMiterlimit ?? 4)
    }

    private func applyStrokeGradient(mainLayer: CAShapeLayer, path: UIBezierPath, gradient: SVGBaseGradient, group: SVGShapesContainer, opacity: CGFloat) throws {
        guard gradient.isEnable() else { throw SVGError.content(text: "wrong content in gradient") }
        let options = group.getSvgOptions()
        let stroked = strokedPath(from: path, viewBox: options.viewBox)
        let maskLayer = CAShapeLayer()
        maskLayer.path = stroked
        if let gradLayer = gradient.getGradientLayer(maskLayer: maskLayer, path: UIBezierPath(cgPath: stroked), viewBox: options.viewBox, currentColor: self.color ?? .black) {
            gradLayer.opacity = Float(min(max(opacity, 0), 1))
            mainLayer.insertSublayer(gradLayer, at: 0)
        }
    }

    private func applyStrokePattern(mainLayer: CAShapeLayer, path: UIBezierPath, pattern: SVGPattern, viewBox: CGRect, opacity: CGFloat) {
        guard let image = pattern.tileImage(bbox: path.bounds, viewBox: viewBox) else { return }
        let stroked = strokedPath(from: path, viewBox: viewBox)
        let patternLayer = CAShapeLayer()
        patternLayer.path = stroked
        patternLayer.fillColor = UIColor(patternImage: image).withAlphaComponent(min(max(opacity, 0), 1)).cgColor
        mainLayer.insertSublayer(patternLayer, at: 0)
    }

    private func applyMarker(iri: SVGFuncIRI, at info: (point: CGPoint, tangent: CGPoint), mainLayer: CAShapeLayer, group: SVGShapesContainer, strokeWidth: CGFloat, overrideElements: [String: SVGSourceStyleElement]?) throws {
        switch iri {
        case .local(let key):
            guard let marker = group.getMarker(byKey: key, fromParents: true) else {
                throw SVGError.content(text: "marker not found: \(key)")
            }
            try placeMarker(marker, at: info, mainLayer: mainLayer, strokeWidth: strokeWidth, overrideElements: overrideElements)
        case .web(let url):
            throw SVGError.content(text: "web marker not supported: \(url)")
        }
    }

    private func placeMarker(_ marker: SVGMarker, at info: (point: CGPoint, tangent: CGPoint), mainLayer: CAShapeLayer, strokeWidth: CGFloat, overrideElements: [String: SVGSourceStyleElement]?) throws {
        let markerLayer = try marker.createLayer(overrideElements: overrideElements)
        // orient="auto" follows the path tangent; a numeric orient is a fixed angle in degrees.
        let angle: CGFloat
        if marker.orient == "auto" {
            angle = atan2(info.tangent.y, info.tangent.x)
        } else {
            angle = (CGFloat(Double(marker.orient) ?? 0)) * .pi / 180
        }
        // markerUnits=strokeWidth scales the marker by the element's stroke width.
        let viewport = marker.viewportMapping()
        let scale: CGFloat = ((marker.markerUnits == .strokeWidth) ? strokeWidth : 1) * viewport.scale
        // Build translate(point) · rotate(angle) · scale · translate(-ref) so the
        // marker's reference point lands on the path point, is scaled for the
        // stroke width, and is rotated to the tangent. CATransform3D helpers
        // post-multiply, hence this construction order.
        var t = CATransform3DIdentity
        t = CATransform3DTranslate(t, info.point.x, info.point.y, 0)
        t = CATransform3DRotate(t, angle, 0, 0, 1)
        t = CATransform3DScale(t, scale, scale, 1)
        t = CATransform3DTranslate(t, -marker.refX, -marker.refY, 0)
        markerLayer.transform = t
        if marker.clipsToViewport, !viewport.clip.isEmpty {
            // Default `overflow: hidden`: clip marker content to its viewport (in content space).
            let clipMask = CAShapeLayer()
            clipMask.path = CGPath(rect: viewport.clip, transform: nil)
            markerLayer.mask = clipMask
        }
        mainLayer.addSublayer(markerLayer)
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
            if let gradLayer = gradient.getGradientLayer(maskLayer: maskLayer, path: path, viewBox: options.viewBox, currentColor: self.color ?? .black) {
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
