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
        let moved = point.applying(CATransform3DGetAffineTransform(base))
        let delta = CGPoint(x: point.x - moved.x, y: point.y - moved.y)
        // `CATransform3DConcat(base, translation)` means "apply `base`, then translate" in the
        // row-vector convention Core Animation uses: the same result as `T(o) · M · T(-o)`.
        return CATransform3DConcat(base, CATransform3DMakeTranslation(delta.x, delta.y, 0))
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
            while index < text.endIndex, text[index].isLetter {
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
