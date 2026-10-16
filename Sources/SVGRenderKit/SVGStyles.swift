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

    /// The `text-anchor` alignment (`start`, `middle`, or `end`) for `<text>` elements.
    open var textAnchor: String?

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
        if let textAnchor = child.textAnchor, textAnchor != "inherit" { newElem.textAnchor = textAnchor }
        if let fill = child.fill { newElem.fill = fill }
        if let color = child.color { newElem.color = color }
        if let fillOpacity = child.fillOpacity { newElem.fillOpacity = fillOpacity }
        if let fillRule = child.fillRule, fillRule != .inherit { newElem.fillRule = fillRule }
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
        if let clipRule = child.clipRule, clipRule != .inherit { newElem.clipRule = clipRule }
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
            if case .px(let value)? = self.fontSize { parentSize = value } else { parentSize = 16.0 }
            newElem.fontSize = .px(fontSize.resolvedPx(relativeTo: parentSize))
        }

        return newElem
    }

    func set(element: SVGSourceStyleElement) {
        display = element.display
        visibility = element.visibility
        textAnchor = element.textAnchor
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

    /// Whether this style carries a property that composites the element as a whole
    /// (`opacity`, `clip-path`, `mask`, `filter`) — the ones that must not be inherited
    /// by a `<use>` clone's content (B119-1).
    var hasGroupCompositing: Bool {
        return opacity != nil || clipPath != nil || mask != nil || filter != nil
    }

    /// This style without the group-compositing properties (`opacity`, `clip-path`, `mask`,
    /// `filter`). Those apply to a group — or to a `<use>` clone — as a whole, so they must
    /// not be inherited by its content: doing so applies them a second time (B119-1).
    func withoutGroupCompositing() -> SVGSourceStyleElement {
        let copy = SVGSourceStyleElement()
        copy.set(element: self)
        copy.opacity = nil
        copy.clipPath = nil
        copy.mask = nil
        copy.filter = nil
        return copy
    }

    func set(styleStr: String) throws {
        try set(attributeDict: SVGSourceStyleElement.declarations(from: styleStr))
    }

    /// Applies an element's presentation attributes and then its inline `style`, which
    /// outranks them (B129).
    func set(attributesAndInlineStyle attributeDict: [String: String]) throws {
        try set(attributeDict: attributeDict)
        if let str = attributeDict["style"] { try set(styleStr: str) }
    }

    /// Parses an inline `style` or a CSS declaration block into a property dictionary.
    /// Per CSS: a value may itself contain `:`, a trailing `!important` is not part of the
    /// value, and the last declaration of a property wins (B109).
    static func declarations(from styleStr: String) -> [String: String] {
        var result: [String: String] = [:]
        for declaration in splitDeclarations(stripComments(styleStr)) {
            let parts = declaration.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let key = SVGUtils.trimmed(string: String(parts[0])).lowercased()
            guard !key.isEmpty else { continue }
            var value = SVGUtils.trimmed(string: String(parts[1]))
            if value.lowercased().hasSuffix("!important") {
                value = SVGUtils.trimmed(string: String(value.dropLast("!important".count)))
            }
            result[key] = value
        }
        return result
    }

    /// Removes CSS `/* … */` comments (an unterminated one runs to the end).
    private static func stripComments(_ text: String) -> String {
        guard text.contains("/*") else { return text }
        var out = ""
        var rest = Substring(text)
        while let open = rest.range(of: "/*") {
            out += rest[..<open.lowerBound]
            guard let close = rest[open.upperBound...].range(of: "*/") else { return out }
            rest = rest[close.upperBound...]
        }
        return out + rest
    }

    /// Splits on `;` outside parentheses and quotes, so `url(data:image/png;base64,…)` stays whole.
    private static func splitDeclarations(_ text: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        var quote: Character?
        for character in text {
            if let q = quote {
                if character == q { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "(" {
                depth += 1
            } else if character == ")" {
                depth = max(0, depth - 1)
            } else if character == ";" && depth == 0 {
                parts.append(current)
                current = ""
                continue
            }
            current.append(character)
        }
        parts.append(current)
        return parts.filter { !SVGUtils.trimmed(string: $0).isEmpty }
    }

    /// Applies a set of properties. A malformed value is logged and ignored rather
    /// than thrown, so a single bad property never fails the whole document (B85).
    func set(attributeDict: [String: String]) throws {
        if let str = attributeDict["display"], !str.isEmpty { ignoring("display") { try setDisplay(str: str) } }
        if let str = attributeDict["visibility"], !str.isEmpty { setVisibility(str: str) }
        if let str = attributeDict["text-anchor"], !str.isEmpty { textAnchor = str.trimmed }
        if let str = attributeDict["fill"], !str.isEmpty { ignoring("fill") { try setFill(str: str) } }
        if let str = attributeDict["color"], !str.isEmpty { setColor(str: str) }
        if let str = attributeDict["opacity"], !str.isEmpty { ignoring("opacity") { try setOpacity(str: str) } }
        if let str = attributeDict["fill-opacity"], !str.isEmpty { ignoring("fill-opacity") { try setFillOpacity(str: str) } }
        if let str = attributeDict["fill-rule"], !str.isEmpty { setFillRule(str: str) }

        if let str = attributeDict["stroke"], !str.isEmpty { ignoring("stroke") { try setStroke(str: str) } }
        if let str = attributeDict["stroke-opacity"], !str.isEmpty { ignoring("stroke-opacity") { try setStrokeOpacity(str: str) } }
        if let str = attributeDict["stroke-width"], !str.isEmpty { ignoring("stroke-width") { try setStrokeWidth(str: str) } }
        if let str = attributeDict["stroke-linecap"], !str.isEmpty { try setStrokeLinecap(str: str) }
        if let str = attributeDict["stroke-linejoin"], !str.isEmpty { try setStrokeLinejoin(str: str) }
        if let str = attributeDict["stroke-miterlimit"], !str.isEmpty { ignoring("stroke-miterlimit") { try setStrokeMiterlimit(str: str) } }
        if let str = attributeDict["stroke-dasharray"], !str.isEmpty { ignoring("stroke-dasharray") { try setStrokeDasharray(str: str) } }
        if let str = attributeDict["stroke-dashoffset"], !str.isEmpty { ignoring("stroke-dashoffset") { try setStrokeDashoffset(str: str) } }

        if let str = attributeDict["clip-path"], !str.isEmpty { ignoring("clip-path") { try setClipPath(str: str) } }
        if let str = attributeDict["clip-rule"], !str.isEmpty { setClipRule(str: str) }
        if let str = attributeDict["mask"], !str.isEmpty { ignoring("mask") { try setMask(str: str) } }
        if let str = attributeDict["marker-start"], !str.isEmpty { ignoring("marker-start") { try setMarkerStart(str: str) } }
        if let str = attributeDict["marker-mid"], !str.isEmpty { ignoring("marker-mid") { try setMarkerMid(str: str) } }
        if let str = attributeDict["marker-end"], !str.isEmpty { ignoring("marker-end") { try setMarkerEnd(str: str) } }
        if let str = attributeDict["filter"], !str.isEmpty { ignoring("filter") { try setFilter(str: str) } }

        if let str = attributeDict["font-family"], !str.isEmpty { setFontFamily(str: str) }
        if let str = attributeDict["font-style"], !str.isEmpty { ignoring("font-style") { try setFontStyle(str: str) } }
        if let str = attributeDict["font-weight"], !str.isEmpty { ignoring("font-weight") { try setFontWeight(str: str) } }
        if let str = attributeDict["font-size"], !str.isEmpty { setFontSize(str: str) }
    }

    /// Runs one property parser, logging and swallowing its error (B85).
    private func ignoring(_ property: String, _ body: () throws -> Void) {
        do { try body() } catch { SVGLog.addSLog(errorStr: "ignored \(property): \(error)") }
    }

    func setDisplay(str: String) throws {
        if let f = SVGDisplaytype.init(rawValue: str) {
            display = f
        } else {
            throw SVGError.content(text: "display not supported: \(str)")
        }
    }

    func setVisibility(str: String) {
        // `inherit` and unknown values leave the property unset, so the inherited value
        // stays; forcing `visible` would un-hide a child of a hidden parent (B129).
        visibility = SVGVisibility(rawValue: SVGUtils.trimmed(string: str).lowercased())
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
        // An invalid colour is an invalid declaration: the previous value stays.
        if let parsed = SVGColors.parse(string: trimmed) { color = parsed }
    }

    /// An alpha value: a plain number or a percentage (`"50%"` means 0.5), clamped
    /// to [0, 1] the way CSS does. `nil` means the value is not a number at all — the
    /// caller logs and ignores it (B85, B119-5).
    private static func alphaValue(_ str: String) -> CGFloat? {
        let trimmed = SVGUtils.trimmed(string: str)
        let isPercent = trimmed.hasSuffix("%")
        let raw = isPercent ? String(trimmed.dropLast()) : trimmed
        guard let number = Float(raw), number.isFinite else { return nil }
        let value = CGFloat(isPercent ? number / 100 : number)
        return min(max(value, 0), 1)
    }

    func setFillOpacity(str: String) throws {
        guard let value = SVGSourceStyleElement.alphaValue(str) else {
            throw SVGError.content(text: "wrong fillOpacity: \(str)")
        }
        fillOpacity = value
    }

    /// `opacity` accepts a percentage and is clamped to [0, 1] the way CSS does, so an
    /// out-of-range value paints at the nearest end instead of being dropped (B119-5).
    func setOpacity(str: String) throws {
        guard let value = SVGSourceStyleElement.alphaValue(str) else {
            throw SVGError.content(text: "wrong opacity: \(str)")
        }
        opacity = Float(value)
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
        guard let value = SVGSourceStyleElement.alphaValue(str) else {
            throw SVGError.content(text: "wrong strokeOpacity: \(str)")
        }
        strokeOpacity = value
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
        } else if case .px(let value)? = try? SVGLength.get(string: str) {
            // `stroke-dashoffset="5px"` — accept an absolute length unit.
            strokeDashoffset = value
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
        overrideElements: [String: SVGSourceStyleElement]?,
        maskScale: CGFloat = 1
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
            applyFillColor(self.color ?? .black, to: pathLayer, opacity: fillOpacity)
        case .color(let color):
            applyFillColor(color, to: pathLayer, opacity: fillOpacity)
        case .funcIRI(let iri):
            try applyFillReference(iri, fallback: nil, mainLayer: mainLayer, pathLayer: pathLayer, path: path, group: group, opacity: fillOpacity)
        case .funcIRIWithFallback(let iri, let fallback):
            try applyFillReference(iri, fallback: fallback, mainLayer: mainLayer, pathLayer: pathLayer, path: path, group: group, opacity: fillOpacity)
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
            applyStrokeColor(self.color ?? .black, to: pathLayer, width: resolvedStrokeWidth, opacity: strokeOpacity)
        case .color(let color):
            applyStrokeColor(color, to: pathLayer, width: resolvedStrokeWidth, opacity: strokeOpacity)
        case .funcIRI(let iri):
            try applyStrokeReference(iri, fallback: nil, mainLayer: mainLayer, path: path, pathLayer: pathLayer, viewBox: strokeViewBox, group: group, width: resolvedStrokeWidth, opacity: strokeOpacity)
        case .funcIRIWithFallback(let iri, let fallback):
            try applyStrokeReference(iri, fallback: fallback, mainLayer: mainLayer, path: path, pathLayer: pathLayer, viewBox: strokeViewBox, group: group, width: resolvedStrokeWidth, opacity: strokeOpacity)
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
        // The SVG default is 4; leaving the attribute unset must not keep CALayer's own default
        // (10) in place, or sharp corners grow miter spikes that browsers cut off (B123).
        pathLayer.miterLimit = strokeMiterlimit ?? 4
        if let strokeDasharray = self.strokeDasharray {
            pathLayer.lineDashPattern = strokeDasharray.map { NSNumber(value: Double($0)) }
        }
        if let strokeDashoffset = self.strokeDashoffset {
            pathLayer.lineDashPhase = strokeDashoffset
        }

        var clipMaskLayer: CALayer?
        if let clipPath = clipPath {
            switch clipPath {
            case .local(let key):
                if let clipPathObj = group.getClipPath(byKey: key, fromParents: true) {
                    let rendering = try clipPathObj.createLayer(overrideElements: overrideElements)
                    if clipPathObj.clipPathUnits == .objectBoundingBox {
                        // The clip path's coordinates are in [0,1] object-bounding-box
                        // units; map them onto the element's bbox via
                        // translate(origin) · scale(size). The clip path's own transform
                        // applies in those units — before the mapping — so it goes on the
                        // left of `CATransform3DConcat`, whose first argument is applied
                        // first (B119-12).
                        let bbox = path.svgBounds(transformedBy: nil)
                        var t = CATransform3DIdentity
                        t = CATransform3DTranslate(t, bbox.origin.x, bbox.origin.y, 0)
                        t = CATransform3DScale(t, bbox.width, bbox.height, 1)
                        rendering.transform = CATransform3DConcat(rendering.transform, t)
                    }
                    clipMaskLayer = rendering
                } else {
                    SVGLog.addSLog(errorStr: "skipped clip-path: url(#\(key)) not found")
                }
            case .web(let url):
                SVGLog.addSLog(errorStr: "skipped clip-path: external url \(url) not supported")
            }
        }

        var appliedMaskLayer: CALayer?
        if let mask = self.mask {
            switch mask {
            case .local(let key):
                if let maskObj = group.getMask(byKey: key, fromParents: true) {
                    let options = group.getSvgOptions()
                    appliedMaskLayer = try maskObj.maskLayer(bbox: path.svgBounds(transformedBy: nil), viewBox: options.viewBox, overrideElements: overrideElements, elementScale: maskScale)
                } else {
                    SVGLog.addSLog(errorStr: "skipped mask: url(#\(key)) not found")
                }
            case .web(let url):
                SVGLog.addSLog(errorStr: "skipped mask: external url \(url) not supported")
            }
        }

        mainLayer.mask = combineClipAndMask(clip: clipMaskLayer, mask: appliedMaskLayer)

        // Walking the whole path is only needed when a vertex-based marker is set.
        let vertices = (self.markerStart != nil || self.markerMid != nil) ? SVGUtils.markerVertices(path: path) : []

        // marker-start
        if let markerStart = self.markerStart, let first = vertices.first {
            try applyMarker(iri: markerStart, at: (first.point, first.outgoing ?? .zero), mainLayer: mainLayer, group: group, strokeWidth: resolvedStrokeWidth, overrideElements: overrideElements)
        }

        // marker-mid (all vertices except the start and end of the whole path). `orient="auto"`
        // bisects the incoming and outgoing tangents at the vertex (B107); a vertex where only
        // one segment meets (the ends of a subpath) follows that segment.
        if let markerMid = self.markerMid, vertices.count >= 3 {
            for vertex in vertices[1..<(vertices.count - 1)] {
                let tangent: CGPoint
                switch (vertex.incoming, vertex.outgoing) {
                case let (incoming?, outgoing?): tangent = SVGUtils.bisector(incoming, outgoing)
                case let (incoming?, nil): tangent = incoming
                case let (nil, outgoing?): tangent = outgoing
                case (nil, nil): tangent = .zero
                }
                try applyMarker(iri: markerMid, at: (vertex.point, tangent), mainLayer: mainLayer, group: group, strokeWidth: resolvedStrokeWidth, overrideElements: overrideElements)
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
                    let options = group.getSvgOptions()
                    if filter.bakesBitmap { options.usesMasks = true }
                    filter.apply(to: mainLayer, bbox: path.svgBounds(transformedBy: nil), scale: options.renderScale * maskScale)
                } else {
                    SVGLog.addSLog(errorStr: "skipped filter: url(#\(key)) not found")
                }
            case .web(let url):
                SVGLog.addSLog(errorStr: "skipped filter: external url \(url) not supported")
            }
        }
    }

    /// Resolves a `fill="url(#…)"` reference: the gradient or pattern when it exists, the
    /// paint's fallback when the reference cannot be resolved, and nothing at all for
    /// `none` (SVG 2, B119-5).
    private func applyFillReference(_ iri: SVGFuncIRI, fallback: SVGPaint?, mainLayer: CAShapeLayer, pathLayer: CAShapeLayer, path: UIBezierPath, group: SVGShapesContainer, opacity: CGFloat?) throws {
        switch iri {
        case .local(let key):
            if let gradient = group.getGradient(byKey: key, fromParents: true) {
                try applyGradient(mainLayer: mainLayer, pathLayer: pathLayer, path: path, gradient: gradient, group: group, opacity: Float(opacity ?? 1.0))
            } else if let pattern = group.getPattern(byKey: key, fromParents: true) {
                applyPattern(pathLayer: pathLayer, pattern: pattern, group: group, path: path, opacity: opacity)
            } else {
                SVGLog.addSLog(errorStr: "skipped fill: url(#\(key)) not found")
                applyFillFallback(fallback, to: pathLayer, opacity: opacity)
            }
        case .web(let url):
            SVGLog.addSLog(errorStr: "skipped fill: external url \(url) not supported")
            applyFillFallback(fallback, to: pathLayer, opacity: opacity)
        }
    }

    /// The `stroke="url(#…)"` counterpart of `applyFillReference`.
    private func applyStrokeReference(_ iri: SVGFuncIRI, fallback: SVGPaint?, mainLayer: CAShapeLayer, path: UIBezierPath, pathLayer: CAShapeLayer, viewBox: CGRect, group: SVGShapesContainer, width: CGFloat, opacity: CGFloat) throws {
        switch iri {
        case .local(let key):
            if let gradient = group.getGradient(byKey: key, fromParents: true) {
                try applyStrokeGradient(mainLayer: mainLayer, path: path, gradient: gradient, group: group, opacity: opacity)
            } else if let pattern = group.getPattern(byKey: key, fromParents: true) {
                applyStrokePattern(mainLayer: mainLayer, path: path, pattern: pattern, viewBox: viewBox, opacity: opacity)
            } else {
                SVGLog.addSLog(errorStr: "skipped stroke: url(#\(key)) not found")
                applyStrokeFallback(fallback, to: pathLayer, width: width, opacity: opacity)
            }
        case .web(let url):
            SVGLog.addSLog(errorStr: "skipped stroke: external url \(url) not supported")
            applyStrokeFallback(fallback, to: pathLayer, width: width, opacity: opacity)
        }
    }

    /// Paints the path with a solid color, honouring `fill-opacity`.
    private func applyFillColor(_ color: UIColor, to pathLayer: CAShapeLayer, opacity: CGFloat?) {
        if let opacity = opacity {
            pathLayer.fillColor = color.withAlphaComponent(color.cgColor.alpha * opacity).cgColor
        } else {
            pathLayer.fillColor = color.cgColor
        }
    }

    /// Paints the stroke with a solid color, honouring `stroke-opacity`.
    private func applyStrokeColor(_ color: UIColor, to pathLayer: CAShapeLayer, width: CGFloat, opacity: CGFloat) {
        pathLayer.lineWidth = width
        pathLayer.strokeColor = color.withAlphaComponent(color.cgColor.alpha * opacity).cgColor
    }

    /// The solid color a paint degrades to when its `url(#…)` reference cannot be resolved:
    /// the paint's own fallback (`fill="url(#x) #fff"`), or `nil` for no paint at all —
    /// SVG 2 paints `none` there, and leaving a `CAShapeLayer` untouched would keep its
    /// default black fill (B119-5).
    private func fallbackColor(_ paint: SVGPaint?) -> UIColor? {
        guard let paint = paint else { return nil }
        switch paint {
        case .color(let color): return color
        case .currentColor: return self.color ?? .black
        case .none, .funcIRI, .funcIRIWithFallback: return nil
        }
    }

    private func applyFillFallback(_ paint: SVGPaint?, to pathLayer: CAShapeLayer, opacity: CGFloat?) {
        if let color = fallbackColor(paint) {
            applyFillColor(color, to: pathLayer, opacity: opacity)
        } else {
            pathLayer.fillColor = nil
        }
    }

    private func applyStrokeFallback(_ paint: SVGPaint?, to pathLayer: CAShapeLayer, width: CGFloat, opacity: CGFloat) {
        if let color = fallbackColor(paint) {
            applyStrokeColor(color, to: pathLayer, width: width, opacity: opacity)
        } else {
            pathLayer.strokeColor = nil
        }
    }

    /// Applies group-compositing properties (`visibility`, `opacity`, `clip-path`,
    /// `mask`, `filter`) to a group's composite layer. Unlike fill/stroke, these
    /// are not inherited to child shapes; they composite the whole group.
    ///
    /// - parameter maskScale: the accumulated scale of the element's own and its ancestors'
    ///   transforms, so the mask is rasterized as sharply as the element is drawn (B119-6).
    func applyGroupComposite(to layer: CALayer, bbox: @autoclosure () -> CGRect, container: SVGShapesContainer, overrideElements: [String: SVGSourceStyleElement]?, maskScale: CGFloat = 1) throws {
        // `visibility` is inherited and applied per element, not on the container layer:
        // hiding the group layer would also hide a descendant that overrides it back to
        // `visible` (B107). Shapes, images and text each apply their own visibility.

        if let opacity = self.opacity {
            layer.opacity = (opacity >= 0 && opacity <= 1) ? opacity : 1
        }

        var clipMaskLayer: CALayer?
        if let clipPath = self.clipPath {
            switch clipPath {
            case .local(let key):
                guard let clipPathObj = container.getClipPath(byKey: key, fromParents: true) else {
                    SVGLog.addSLog(errorStr: "skipped clip-path: url(#\(key)) not found")
                    break
                }
                let rendering = try clipPathObj.createLayer(overrideElements: overrideElements)
                if clipPathObj.clipPathUnits == .objectBoundingBox {
                    // Map [0,1] object-bounding-box units onto the group's bbox:
                    // translate(origin) · scale(size). The clip path's own transform applies
                    // in those units, before the mapping, hence the argument order (B119-12).
                    let bbox = bbox()
                    var t = CATransform3DIdentity
                    t = CATransform3DTranslate(t, bbox.origin.x, bbox.origin.y, 0)
                    t = CATransform3DScale(t, bbox.width, bbox.height, 1)
                    rendering.transform = CATransform3DConcat(rendering.transform, t)
                }
                // userSpaceOnUse: the clip is in the element's own user space, so the
                // group's transform moves it together with the content — exactly as for
                // a shape. Do not counter-transform it (B95).
                clipMaskLayer = rendering
            case .web(let url):
                SVGLog.addSLog(errorStr: "skipped clip-path: external url \(url) not supported")
            }
        }

        var appliedMaskLayer: CALayer?
        if let mask = self.mask {
            switch mask {
            case .local(let key):
                guard let maskObj = container.getMask(byKey: key, fromParents: true) else {
                    SVGLog.addSLog(errorStr: "skipped mask: url(#\(key)) not found")
                    break
                }
                let options = container.getSvgOptions()
                appliedMaskLayer = try maskObj.maskLayer(bbox: bbox(), viewBox: options.viewBox, overrideElements: overrideElements, elementScale: maskScale)
            case .web(let url):
                SVGLog.addSLog(errorStr: "skipped mask: external url \(url) not supported")
            }
        }

        layer.mask = combineClipAndMask(clip: clipMaskLayer, mask: appliedMaskLayer)

        if let filter = self.filter {
            switch filter {
            case .local(let key):
                guard let filterObj = container.getFilter(byKey: key, fromParents: true) else {
                    SVGLog.addSLog(errorStr: "skipped filter: url(#\(key)) not found")
                    break
                }
                let options = container.getSvgOptions()
                if filterObj.bakesBitmap { options.usesMasks = true }
                filterObj.apply(to: layer, bbox: bbox(), scale: options.renderScale * maskScale)
            case .web(let url):
                SVGLog.addSLog(errorStr: "skipped filter: external url \(url) not supported")
            }
        }
    }

    /// Applies a `clip-path` and a `mask` to the same layer. They intersect, so the clip
    /// becomes a mask of the mask layer instead of replacing it (B89).
    private func combineClipAndMask(clip: CALayer?, mask: CALayer?) -> CALayer? {
        guard let clip = clip else { return mask }
        guard let mask = mask else { return clip }
        // The mask layer's content is offset by its frame origin while the clip lives in
        // the layer's own space, so shift the clip into the mask layer's local space.
        let origin = mask.frame.origin
        if origin != .zero {
            clip.transform = CATransform3DConcat(clip.transform, CATransform3DMakeTranslation(-origin.x, -origin.y, 0))
        }
        mask.mask = clip
        return mask
    }

    private func applyPattern(pathLayer: CAShapeLayer, pattern: SVGPattern, group: SVGShapesContainer, path: UIBezierPath, opacity: CGFloat?) {
        if let color = pattern.fillColor(bbox: path.svgBounds(transformedBy: nil), viewBox: group.getSvgOptions().viewBox, opacity: opacity) {
            pathLayer.fillColor = color
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
        var cgPath = path.cgPath
        // A dashed gradient stroke must be dashed too (B107).
        if let dash = self.strokeDasharray, !dash.isEmpty {
            cgPath = cgPath.copy(dashingWithPhase: self.strokeDashoffset ?? 0, lengths: dash)
        }
        return cgPath.copy(
            strokingWithWidth: strokeWidthPixels(viewBox: viewBox),
            lineCap: lineCap,
            lineJoin: lineJoin,
            miterLimit: self.strokeMiterlimit ?? 4)
    }

    private func applyStrokeGradient(mainLayer: CAShapeLayer, path: UIBezierPath, gradient: SVGBaseGradient, group: SVGShapesContainer, opacity: CGFloat) throws {
        // A gradient without stops paints nothing (SVG 1.1 §13.2), so the stroke is
        // simply not painted — the document keeps rendering (B119-5).
        guard gradient.isEnable() else {
            SVGLog.addSLog(errorStr: "skipped stroke: gradient without stops")
            return
        }
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
        guard let color = pattern.fillColor(bbox: path.svgBounds(transformedBy: nil), viewBox: viewBox, opacity: opacity) else { return }
        let stroked = strokedPath(from: path, viewBox: viewBox)
        let patternLayer = CAShapeLayer()
        patternLayer.path = stroked
        patternLayer.fillColor = color
        mainLayer.insertSublayer(patternLayer, at: 0)
    }

    private func applyMarker(iri: SVGFuncIRI, at info: (point: CGPoint, tangent: CGPoint), mainLayer: CAShapeLayer, group: SVGShapesContainer, strokeWidth: CGFloat, overrideElements: [String: SVGSourceStyleElement]?) throws {
        switch iri {
        case .local(let key):
            guard let marker = group.getMarker(byKey: key, fromParents: true) else {
                SVGLog.addSLog(errorStr: "skipped marker: url(#\(key)) not found")
                return
            }
            try placeMarker(marker, at: info, mainLayer: mainLayer, strokeWidth: strokeWidth, overrideElements: overrideElements)
        case .web(let url):
            SVGLog.addSLog(errorStr: "skipped marker: external url \(url) not supported")
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
            // The gradient is painted through the path's silhouette, so the element's
            // fill-rule must be honored — otherwise an even-odd path fills its holes (B100).
            maskLayer.fillRule = (fillRule ?? .nonzero) == .evenodd ? .evenOdd : .nonZero
            if let gradLayer = gradient.getGradientLayer(maskLayer: maskLayer, path: path, viewBox: options.viewBox, currentColor: self.color ?? .black) {
                if let opacity = opacity {
                    gradLayer.opacity = opacity
                }
                mainLayer.insertSublayer(gradLayer, at: 0)
            }
        } else {
            // Same for a fill: no stops means `none` (SVG 1.1 §13.2) — and clearing the
            // fill is required, CoreAnimation would otherwise paint the default black.
            pathLayer.fillColor = nil
            SVGLog.addSLog(errorStr: "skipped fill: gradient without stops")
        }
    }
}
