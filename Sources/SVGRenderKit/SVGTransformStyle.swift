import UIKit
import QuartzCore

/// Resolves the CSS `transform`, `transform-origin` and `transform-box` of one element into a
/// matrix in the element's user space.
///
/// CSS semantics implemented here: the `transform` property replaces the `transform` attribute
/// (the attribute is its presentation form and therefore the lowest-priority declaration); a
/// transform is applied around `transform-origin`, whose percentages/lengths are relative to the
/// reference box selected by `transform-box` (`view-box` by default, `fill-box` for the element's
/// own bounding box). A missing `transform-origin` keeps the SVG initial `0 0`.
enum SVGTransformStyle {

    /// The reference boxes and raw origin/box values of one element.
    struct Context {
        /// The document's `viewBox`, in user units.
        let viewBox: CGRect
        /// The element's own bounding box (content bounds for a group), when it has one.
        let bbox: CGRect?
        /// The raw computed `transform-origin`, if any.
        let origin: String?
        /// The raw computed `transform-box`, if any.
        let box: String?

        init(viewBox: CGRect, bbox: CGRect? = nil, origin: String? = nil, box: String? = nil) {
            self.viewBox = viewBox
            self.bbox = bbox
            self.origin = origin
            self.box = box
        }

        /// The box `transform-origin` percentages and `translate()` percentages resolve against.
        var referenceBox: CGRect {
            if let box = box?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
               box == "fill-box", let bbox = bbox, bbox.width > 0, bbox.height > 0 {
                return bbox
            }
            return viewBox
        }
    }

    /// The element's computed transform: the CSS property when present (it replaces the attribute),
    /// otherwise the already parsed `transform` attribute matrix.
    static func resolvedTransform(style: SVGSourceStyleElement,
                                  attributeTransform: CATransform3D?,
                                  context: Context) -> CATransform3D? {
        guard let raw = style.transform, !raw.isEmpty else { return attributeTransform }
        if let matrix = matrix(raw, context: context) { return matrix }
        SVGLog.addSLog(errorStr: "ignored CSS transform '\(raw)': the value cannot be parsed")
        return attributeTransform
    }

    /// The matrix of one raw CSS/SVG transform list, applied around `transform-origin`.
    static func matrix(_ raw: String, context: Context) -> CATransform3D? {
        guard let base = parseFunctions(raw, context: context) else { return nil }
        guard let origin = context.origin, !origin.isEmpty,
              let point = transformOrigin(origin, context: context) else { return base }
        return composed(around: base, origin: point)
    }

    // MARK: - transform-origin

    /// The origin point in user units, or `nil` when the value cannot be parsed (the transform is
    /// then applied around the SVG initial `0 0`).
    static func transformOrigin(_ raw: String, context: Context) -> CGPoint? {
        let tokens = raw.split(whereSeparator: { $0.isWhitespace }).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        guard !tokens.isEmpty else { return nil }
        let box = context.referenceBox
        if tokens.count == 1 {
            if isVerticalKeyword(tokens[0]) {
                guard let y = verticalOffset(tokens[0], box: box) else { return nil }
                return CGPoint(x: box.midX, y: y)
            }
            guard let x = horizontalOffset(tokens[0], box: box) else { return nil }
            return CGPoint(x: x, y: box.midY)
        }
        var xToken = tokens[0]
        var yToken = tokens[1]
        if isVerticalKeyword(xToken), isHorizontalKeyword(yToken) {
            swap(&xToken, &yToken)
        }
        guard let x = horizontalOffset(xToken, box: box),
              let y = verticalOffset(yToken, box: box) else { return nil }
        return CGPoint(x: x, y: y)
    }

    private static func isHorizontalKeyword(_ token: String) -> Bool {
        return token == "left" || token == "right" || token == "center"
    }

    private static func isVerticalKeyword(_ token: String) -> Bool {
        return token == "top" || token == "bottom" || token == "center"
    }

    private static func horizontalOffset(_ token: String, box: CGRect) -> CGFloat? {
        switch token {
        case "left": return box.minX
        case "right": return box.maxX
        case "center": return box.midX
        default: return length(token, axis: box.width).map { box.minX + $0 }
        }
    }

    private static func verticalOffset(_ token: String, box: CGRect) -> CGFloat? {
        switch token {
        case "top": return box.minY
        case "bottom": return box.maxY
        case "center": return box.midY
        default: return length(token, axis: box.height).map { box.minY + $0 }
        }
    }

    // MARK: - Component-wise interpolation (for full turns and large rotations)

    /// One CSS/SVG transform function with resolved numeric arguments.
    struct Component: Equatable {
        enum Kind: Equatable {
            case translate(x: CGFloat, y: CGFloat)
            case scale(x: CGFloat, y: CGFloat)
            case rotate(angle: CGFloat)
            case skewX(angle: CGFloat)
            case skewY(angle: CGFloat)
            case matrix(a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat, e: CGFloat, f: CGFloat)
        }
        let kind: Kind
    }

    /// Parses a transform list into components; `nil` when a function is not representable.
    static func components(_ raw: String, context: Context) -> [Component]? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty || text.lowercased() == "none" { return [] }
        let box = context.referenceBox
        var result: [Component] = []
        var index = text.startIndex
        while index < text.endIndex {
            while index < text.endIndex, text[index].isWhitespace { index = text.index(after: index) }
            guard index < text.endIndex else { break }
            var name = ""
            while index < text.endIndex, text[index].isLetter || text[index].isNumber {
                name.append(text[index])
                index = text.index(after: index)
            }
            guard !name.isEmpty else { return nil }
            while index < text.endIndex, text[index].isWhitespace { index = text.index(after: index) }
            guard index < text.endIndex, text[index] == "(" else { return nil }
            index = text.index(after: index)
            var arguments = ""
            var depth = 1
            while index < text.endIndex, depth > 0 {
                let character = text[index]
                index = text.index(after: index)
                if character == "(" {
                    depth += 1
                    arguments.append(character)
                } else if character == ")" {
                    depth -= 1
                    if depth > 0 { arguments.append(character) }
                } else {
                    arguments.append(character)
                }
            }
            guard depth == 0 else { return nil }
            guard let component = component(function: name.lowercased(), arguments: arguments, box: box) else {
                return nil
            }
            result.append(component)
        }
        return result
    }

    private static func component(function: String, arguments: String, box: CGRect) -> Component? {
        let parts = arguments.split(whereSeparator: { $0 == "," || $0.isWhitespace }).map(String.init)
        switch function {
        case "translate":
            guard let x = length(parts.first, axis: box.width) else { return nil }
            let y = parts.count > 1 ? length(parts[1], axis: box.height) : 0
            guard let y = y else { return nil }
            return Component(kind: .translate(x: CGFloat(x), y: CGFloat(y)))
        case "translatex":
            guard let x = length(parts.first, axis: box.width) else { return nil }
            return Component(kind: .translate(x: CGFloat(x), y: 0))
        case "translatey":
            guard let y = length(parts.first, axis: box.height) else { return nil }
            return Component(kind: .translate(x: 0, y: CGFloat(y)))
        case "translatez":
            return Component(kind: .translate(x: 0, y: 0))
        case "translate3d":
            guard parts.count == 3, let x = length(parts[0], axis: box.width),
                  let y = length(parts[1], axis: box.height) else { return nil }
            return Component(kind: .translate(x: CGFloat(x), y: CGFloat(y)))
        case "scale":
            guard let sx = numbers(parts.first) else { return nil }
            let sy = parts.count > 1 ? numbers(parts[1]) : sx
            guard let sy = sy else { return nil }
            return Component(kind: .scale(x: CGFloat(sx), y: CGFloat(sy)))
        case "scalex":
            guard let sx = numbers(parts.first) else { return nil }
            return Component(kind: .scale(x: CGFloat(sx), y: 1))
        case "scaley":
            guard let sy = numbers(parts.first) else { return nil }
            return Component(kind: .scale(x: 1, y: CGFloat(sy)))
        case "scalez":
            return Component(kind: .scale(x: 1, y: 1))
        case "scale3d":
            guard parts.count == 3, let sx = numbers(parts[0]), let sy = numbers(parts[1]) else { return nil }
            return Component(kind: .scale(x: CGFloat(sx), y: CGFloat(sy)))
        case "rotate", "rotatez":
            guard let angle = angle(parts.first) else { return nil }
            return Component(kind: .rotate(angle: CGFloat(angle)))
        case "rotate3d":
            guard parts.count == 4, let x = numbers(parts[0]), let y = numbers(parts[1]),
                  let z = numbers(parts[2]), let angle = angle(parts[3]),
                  abs(x) < 1e-9, abs(y) < 1e-9, abs(z) > 1e-9 else { return nil }
            return Component(kind: .rotate(angle: CGFloat(angle)))
        case "skewx":
            guard let angle = angle(parts.first) else { return nil }
            return Component(kind: .skewX(angle: CGFloat(angle)))
        case "skewy":
            guard let angle = angle(parts.first) else { return nil }
            return Component(kind: .skewY(angle: CGFloat(angle)))
        case "matrix":
            guard parts.count == 6,
                  let a = numbers(parts[0]), let b = numbers(parts[1]), let c = numbers(parts[2]),
                  let d = numbers(parts[3]), let e = numbers(parts[4]), let f = numbers(parts[5]) else {
                return nil
            }
            return Component(kind: .matrix(a: CGFloat(a), b: CGFloat(b), c: CGFloat(c),
                                           d: CGFloat(d), e: CGFloat(e), f: CGFloat(f)))
        default:
            return nil
        }
    }

    /// `matrix` applied around `origin`: `T(-o) · M · T(o)` in the row-vector convention
    /// (`CATransform3DConcat(a, b)` applies `a` first). Translating by `o` and back must not
    /// cancel the matrix's own translation — the earlier delta formula did, so a `translateY`
    /// animation around `transform-origin` was a no-op.
    static func composed(around matrix: CATransform3D, origin: CGPoint) -> CATransform3D {
        let toOrigin = CATransform3DMakeTranslation(-origin.x, -origin.y, 0)
        let fromOrigin = CATransform3DMakeTranslation(origin.x, origin.y, 0)
        return CATransform3DConcat(CATransform3DConcat(toOrigin, matrix), fromOrigin)
    }

    /// Whether any scale component is zero (a singular matrix Core Animation cannot decompose
    /// reliably; the segment is sampled from the CSS functions instead).
    static func hasDegenerateScale(_ components: [Component]) -> Bool {
        return components.contains { component in
            if case .scale(let x, let y) = component.kind {
                return abs(x) < 1e-6 || abs(y) < 1e-6
            }
            return false
        }
    }

    /// The identity transform list with the same function kinds, so an implicit keyframe (the
    /// underlying `none`) can be interpolated function by function with an explicit one.
    static func identityComponents(matching components: [Component]) -> [Component] {
        return components.map { component in
            switch component.kind {
            case .translate: return Component(kind: .translate(x: 0, y: 0))
            case .scale: return Component(kind: .scale(x: 1, y: 1))
            case .rotate: return Component(kind: .rotate(angle: 0))
            case .skewX: return Component(kind: .skewX(angle: 0))
            case .skewY: return Component(kind: .skewY(angle: 0))
            case .matrix: return Component(kind: .matrix(a: 1, b: 0, c: 0, d: 1, e: 0, f: 0))
            }
        }
    }

    /// Interpolates two compatible transform lists function by function, matching CSS semantics
    /// (angles are interpolated linearly, without the shortest-path rule Core Animation uses when
    /// it decomposes matrices — a 0°→360° turn would otherwise collapse to identity).
    static func interpolatedTransform(_ from: [Component], _ to: [Component],
                                      progress: CGFloat) -> String? {
        guard from.count == to.count else { return nil }
        var pieces: [String] = []
        for (a, b) in zip(from, to) {
            switch (a.kind, b.kind) {
            case (.translate(let ax, let ay), .translate(let bx, let by)):
                pieces.append("translate(\(number(Double(ax + (bx - ax) * progress))), \(number(Double(ay + (by - ay) * progress))))")
            case (.scale(let ax, let ay), .scale(let bx, let by)):
                pieces.append("scale(\(number(Double(ax + (bx - ax) * progress))), \(number(Double(ay + (by - ay) * progress))))")
            case (.rotate(let a), .rotate(let b)):
                pieces.append("rotate(\(number(Double(a + (b - a) * progress))))")
            case (.skewX(let a), .skewX(let b)):
                pieces.append("skewX(\(number(Double(a + (b - a) * progress))))")
            case (.skewY(let a), .skewY(let b)):
                pieces.append("skewY(\(number(Double(a + (b - a) * progress))))")
            case (.matrix(let a1, let b1, let c1, let d1, let e1, let f1),
                  .matrix(let a2, let b2, let c2, let d2, let e2, let f2)):
                func mix(_ x: CGFloat, _ y: CGFloat) -> Double { Double(x + (y - x) * progress) }
                pieces.append("matrix(" + [mix(a1, a2), mix(b1, b2), mix(c1, c2),
                                            mix(d1, d2), mix(e1, e2), mix(f1, f2)]
                    .map(number).joined(separator: ", ") + ")")
            default:
                return nil
            }
        }
        return pieces.joined(separator: " ")
    }

    /// The largest rotation this segment performs (the sum of its `rotate()` angles); used to
    /// decide when the matrix representation would lose the winding.
    static func rotationDelta(_ from: [Component], _ to: [Component]) -> CGFloat? {
        guard from.count == to.count else { return nil }
        var delta: CGFloat = 0
        for (a, b) in zip(from, to) {
            switch (a.kind, b.kind) {
            case (.rotate(let start), .rotate(let end)): delta += abs(end - start)
            default: continue
            }
        }
        return delta
    }

    // MARK: - transform functions

    /// Parses the CSS/SVG function list into a matrix. CSS and the SVG attribute share the
    /// composition order (the first function is the outer one), so the units are converted to the
    /// attribute syntax and the kit's parser builds the matrix.
    private static func parseFunctions(_ raw: String, context: Context) -> CATransform3D? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty || text.lowercased() == "none" { return CATransform3DIdentity }
        let box = context.referenceBox
        var pieces: [String] = []
        var index = text.startIndex
        while index < text.endIndex {
            while index < text.endIndex, text[index].isWhitespace { index = text.index(after: index) }
            guard index < text.endIndex else { break }
            var name = ""
            // CSS function names contain digits too: `translate3d`, `scale3d`, `rotate3d`.
            while index < text.endIndex, text[index].isLetter || text[index].isNumber {
                name.append(text[index])
                index = text.index(after: index)
            }
            guard !name.isEmpty else { return nil }
            while index < text.endIndex, text[index].isWhitespace { index = text.index(after: index) }
            guard index < text.endIndex, text[index] == "(" else { return nil }
            index = text.index(after: index)
            var arguments = ""
            var depth = 1
            while index < text.endIndex, depth > 0 {
                let character = text[index]
                index = text.index(after: index)
                if character == "(" {
                    depth += 1
                    arguments.append(character)
                } else if character == ")" {
                    depth -= 1
                    if depth > 0 { arguments.append(character) }
                } else {
                    arguments.append(character)
                }
            }
            guard depth == 0 else { return nil }
            guard let piece = transformPiece(function: name.lowercased(), arguments: arguments, box: box) else {
                return nil
            }
            pieces.append(piece)
        }
        guard !pieces.isEmpty else { return nil }
        return try? SVGTransform.get(string: pieces.joined(separator: " "))
    }

    private static func transformPiece(function: String, arguments: String, box: CGRect) -> String? {
        let parts = arguments.split(whereSeparator: { $0 == "," || $0.isWhitespace }).map(String.init)
        switch function {
        case "translate":
            guard let x = length(parts.first, axis: box.width) else { return nil }
            let y = parts.count > 1 ? length(parts[1], axis: box.height) : 0
            guard let y = y else { return nil }
            return "translate(\(number(x)), \(number(y)))"
        case "translatex":
            guard let x = length(parts.first, axis: box.width) else { return nil }
            return "translate(\(number(x)), 0)"
        case "translatey":
            guard let y = length(parts.first, axis: box.height) else { return nil }
            return "translate(0, \(number(y)))"
        case "translatez":
            return "translate(0, 0)"
        case "translate3d":
            guard parts.count == 3, let x = length(parts[0], axis: box.width),
                  let y = length(parts[1], axis: box.height) else { return nil }
            return "translate(\(number(x)), \(number(y)))"
        case "scale":
            guard let sx = numbers(parts.first) else { return nil }
            let sy = parts.count > 1 ? numbers(parts[1]) : sx
            guard let sy = sy else { return nil }
            return "scale(\(number(sx)), \(number(sy)))"
        case "scalex":
            guard let sx = numbers(parts.first) else { return nil }
            return "scale(\(number(sx)), 1)"
        case "scaley":
            guard let sy = numbers(parts.first) else { return nil }
            return "scale(1, \(number(sy)))"
        case "scalez":
            return "scale(1, 1)"
        case "scale3d":
            guard parts.count == 3, let sx = numbers(parts[0]), let sy = numbers(parts[1]) else { return nil }
            return "scale(\(number(sx)), \(number(sy)))"
        case "rotate", "rotatez":
            guard let angle = angle(parts.first) else { return nil }
            // The SVG `transform` attribute allows a rotation centre: `rotate(a cx cy)`.
            if parts.count >= 3, let cx = length(parts[1], axis: box.width),
               let cy = length(parts[2], axis: box.height) {
                return "rotate(\(number(angle)), \(number(cx)), \(number(cy)))"
            }
            return "rotate(\(number(angle)))"
        case "rotate3d":
            guard parts.count == 4, let x = numbers(parts[0]), let y = numbers(parts[1]),
                  let z = numbers(parts[2]), let angle = angle(parts[3]),
                  abs(x) < 1e-9, abs(y) < 1e-9, abs(z) > 1e-9 else { return nil }
            return "rotate(\(number(angle)))"
        case "skewx":
            guard let angle = angle(parts.first) else { return nil }
            return "skewX(\(number(angle)))"
        case "skewy":
            guard let angle = angle(parts.first) else { return nil }
            return "skewY(\(number(angle)))"
        case "matrix":
            guard parts.count == 6 else { return nil }
            var entries: [Double] = []
            for part in parts {
                guard let value = Double(part) else { return nil }
                entries.append(value)
            }
            return "matrix(" + entries.map { number($0) }.joined(separator: ", ") + ")"
        default:
            return nil
        }
    }

    /// A CSS length: `px` or a unitless number, or a percentage of `axis` (the reference box's
    /// width for x, height for y).
    private static func length(_ part: String?, axis: CGFloat) -> Double? {
        guard var value = part else { return nil }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasSuffix("%") {
            return Double(value.dropLast()).map { $0 / 100 * Double(axis) }
        }
        if value.hasSuffix("px") { value = String(value.dropLast(2)) }
        return Double(value)
    }

    /// A plain CSS number (a scale factor or a matrix entry).
    private static func numbers(_ part: String?) -> Double? {
        guard let part = part else { return nil }
        return Double(part.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// A CSS angle in degrees.
    private static func angle(_ part: String?) -> Double? {
        guard let raw = part else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasSuffix("deg") { return Double(value.dropLast(3)) }
        if value.hasSuffix("rad") { return Double(value.dropLast(3)).map { $0 * 180 / .pi } }
        if value.hasSuffix("grad") { return Double(value.dropLast(4)).map { $0 * 0.9 } }
        if value.hasSuffix("turn") { return Double(value.dropLast(4)).map { $0 * 360 } }
        return Double(value)
    }

    private static func number(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 { return String(Int(value)) }
        return String(value)
    }
}
