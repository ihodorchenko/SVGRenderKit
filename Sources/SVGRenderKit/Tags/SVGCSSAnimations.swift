import UIKit
import QuartzCore

/// One parsed CSS `animation` declaration: the `animation` shorthand and the `animation-*`
/// longhands folded into the fields the runtime needs.
///
/// CSS animations are not presentation properties, so they are resolved separately from
/// `SVGSourceStyleElement` and translated into the same `SVGAnimation` objects SMIL uses (the
/// existing attach/deferred path then treats both sources identically).
struct SVGCSSAnimationSpec {
    var name: String
    var duration: TimeInterval = 0
    var timingFunction: String = "ease"
    var delay: TimeInterval = 0
    var iterationCount: Double = 1
    var direction: String = "normal"
    var fillMode: String = "none"
    var playState: String = "running"
}

/// The runtime subset of CSS Animations: `@keyframes` and `animation` declarations resolved into
/// `SVGAnimation` objects for the properties the layer renderer can animate.
///
/// Played properties: `transform` (translation/scale/rotation/skew in the 2D plane), `opacity`,
/// `fill`, `stroke` and `stroke-dashoffset` (`CAShapeLayer.lineDashPhase`). A keyframe block that
/// animates anything else is logged and skipped. See CONFORMANCE.md for the profile and the known
/// divergences (Core Animation interpolates matrices by decomposition and colors in its own space).
enum SVGCSSAnimations {

    /// A CSS-animated property the runtime can play.
    enum Property: String, CaseIterable {
        case strokeDashoffset = "stroke-dashoffset"
        case opacity
        case fill
        case stroke
        case transform
    }

    /// The computed base values of an element: a keyframe that omits the property at `0%`/`100%`
    /// falls back to these (CSS Animations L1 §keyframes).
    struct BaseValues {
        var dashoffset: Double = 0
        var opacity: Double = 1
        var fill: CGColor?
        var stroke: CGColor?
        var transform: CATransform3D = CATransform3DIdentity
    }

    /// One parsed keyframe value. The property decides which case is used.
    private enum Value {
        case number(Double)
        case color(CGColor)
        case transform(CATransform3D)
    }

    // MARK: - Declarations -> specs

    /// Expands the cascaded `animation`/`animation-*` declarations (in order) into specs.
    ///
    /// A later shorthand replaces the earlier one and resets the longhands, a longhand after it
    /// overrides one field, and comma-separated lists cycle like CSS (`a 1s, b 2s` is two
    /// animations; `animation-delay:1s` applies to every animation of the list).
    static func specs(from declarations: [(property: String, value: String)]) -> [SVGCSSAnimationSpec] {
        var shorthand: [SVGCSSAnimationSpec] = []
        var longhands: [String: [String]] = [:]
        for declaration in declarations {
            if declaration.property == "animation" {
                shorthand = splitList(declaration.value).map(parseShorthand)
                longhands = [:]
            } else if declaration.property.hasPrefix("animation-") {
                let key = String(declaration.property.dropFirst("animation-".count))
                longhands[key] = splitList(declaration.value)
            }
        }
        let names = nonEmpty(longhands["name"])
        let count = max(shorthand.count, names?.count ?? 0)
        guard count > 0 else { return [] }

        let durations = nonEmpty(longhands["duration"]?.map { parseTime($0) ?? 0 })
        let delays = nonEmpty(longhands["delay"]?.map { parseTime($0) ?? 0 })
        let timings = nonEmpty(longhands["timing-function"]?.map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
        let iterations = nonEmpty(longhands["iteration-count"]?.map { parseIterationCount($0) })
        let directions = nonEmpty(longhands["direction"]?.map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
        let fills = nonEmpty(longhands["fill-mode"]?.map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
        let plays = nonEmpty(longhands["play-state"]?.map { $0.trimmingCharacters(in: .whitespaces).lowercased() })

        return (0..<count).map { index in
            var spec = index < shorthand.count ? shorthand[index] : SVGCSSAnimationSpec(name: "")
            if let names = names { spec.name = cycle(names, at: index) }
            if let durations = durations { spec.duration = cycle(durations, at: index) }
            if let delays = delays { spec.delay = cycle(delays, at: index) }
            if let timings = timings { spec.timingFunction = cycle(timings, at: index) }
            if let iterations = iterations { spec.iterationCount = cycle(iterations, at: index) }
            if let directions = directions { spec.direction = cycle(directions, at: index) }
            if let fills = fills { spec.fillMode = cycle(fills, at: index) }
            if let plays = plays { spec.playState = cycle(plays, at: index) }
            return spec
        }
    }

    // MARK: - Specs -> runtime animations

    /// Builds the runtime animations of one element.
    /// - parameter keyframes: looks a `@keyframes` block up in the document stylesheet.
    /// - parameter base: the element's computed values for the implicit `0%`/`100%` keyframes.
    /// - parameter properties: the properties this element can animate (a group can animate only
    ///   `opacity` and `transform`, because fill/stroke/dashoffset inherit into its children).
    static func animations(specs: [SVGCSSAnimationSpec],
                           keyframes: (String) -> SVGStyleSheet.Keyframes?,
                           base: BaseValues,
                           properties: Set<Property>) -> [SVGAnimation] {
        var result: [SVGAnimation] = []
        for spec in specs {
            let name = spec.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name != "none" else { continue }
            if spec.playState == "paused" {
                SVGLog.addSLog(errorStr: "CSS animation '\(name)' is paused; skipped")
                continue
            }
            guard spec.iterationCount > 0 else { continue }
            guard spec.duration > 0 else {
                SVGLog.addSLog(errorStr: "CSS animation '\(name)' has no positive duration; skipped")
                continue
            }
            guard let block = keyframes(name) else {
                SVGLog.addSLog(errorStr: "CSS animation '\(name)' has no @keyframes block; skipped")
                continue
            }
            let declaredKeys = Set(block.frames.flatMap { $0.declarations.keys })
            let declared = Property.allCases.filter { declaredKeys.contains($0.rawValue) }
            if declared.isEmpty {
                SVGLog.addSLog(errorStr: "CSS animation '\(name)' animates no property the runtime supports; skipped")
                continue
            }
            let unsupported = declared.filter { !properties.contains($0) }
            if !unsupported.isEmpty {
                SVGLog.addSLog(errorStr: "CSS animation '\(name)': "
                    + unsupported.map(\.rawValue).joined(separator: ", ")
                    + " cannot be animated on this element; skipped")
            }
            for property in declared where properties.contains(property) {
                if let animation = animation(for: property, block: block, spec: spec, base: base) {
                    result.append(animation)
                }
            }
        }
        return result
    }

    private static func animation(for property: Property,
                                  block: SVGStyleSheet.Keyframes,
                                  spec: SVGCSSAnimationSpec,
                                  base: BaseValues) -> SVGAnimation? {
        var frames: [(offset: Double, raw: String, timing: String?)] = []
        for frame in block.frames {
            guard let raw = frame.declarations[property.rawValue] else { continue }
            let timing = frame.declarations["animation-timing-function"]?
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            frames.append((frame.offset, raw, timing))
        }
        guard !frames.isEmpty else { return nil }
        // A keyframe that does not mention the property is ignored for it (CSS Animations L1).
        frames.sort { $0.offset < $1.offset }
        var deduped: [(offset: Double, raw: String, timing: String?)] = []
        for frame in frames {
            if let last = deduped.last, abs(last.offset - frame.offset) < 1e-9 {
                deduped[deduped.count - 1] = frame
            } else {
                deduped.append(frame)
            }
        }
        frames = deduped

        var values: [Value] = []
        for frame in frames {
            guard let value = parseValue(frame.raw, property: property) else {
                SVGLog.addSLog(errorStr: "CSS animation '\(spec.name)': unsupported "
                    + "\(property.rawValue) value '\(frame.raw)'; skipped")
                return nil
            }
            values.append(value)
        }
        // The implicit 0%/100% keyframes come from the element's computed value.
        guard let baseValue = baseValue(for: property, base: base) else {
            SVGLog.addSLog(errorStr: "CSS animation '\(spec.name)': \(property.rawValue) is not "
                + "interpolable on this element; skipped")
            return nil
        }
        if frames[0].offset > 1e-9 {
            frames.insert((0, "", nil), at: 0)
            values.insert(baseValue, at: 0)
        }
        if frames[frames.count - 1].offset < 1 - 1e-9 {
            frames.append((1, "", nil))
            values.append(baseValue)
        }
        guard values.count >= 2 else { return nil }

        let keyTimes = frames.map { $0.offset }
        let timings = (0..<(values.count - 1)).map { index -> CAMediaTimingFunction in
            easingFunction(frames[index].timing ?? spec.timingFunction, animationName: spec.name)
        }
        guard let arranged = arrange(values: values, keyTimes: keyTimes, timings: timings, spec: spec),
              let cssValues = cssValues(for: property, values: arranged.values) else {
            return nil
        }
        return SVGAnimation(kind: .css(property: cssProperty(for: property)),
                            values: [],
                            keyTimes: arranged.keyTimes,
                            duration: spec.duration * arranged.durationScale,
                            repeatCount: arranged.repeatCount,
                            begin: spec.delay,
                            timingFunctions: arranged.timings,
                            autoreverses: arranged.autoreverses,
                            fillMode: caFillMode(spec.fillMode),
                            cssValues: cssValues)
    }

    // MARK: - Direction and iteration folding

    private static func arrange(values: [Value], keyTimes: [Double],
                                timings: [CAMediaTimingFunction], spec: SVGCSSAnimationSpec)
        -> (values: [Value], keyTimes: [Double], timings: [CAMediaTimingFunction],
            repeatCount: Float, durationScale: Double, autoreverses: Bool)? {
        var values = values
        var keyTimes = keyTimes
        var timings = timings
        var repeatCount: Float = spec.iterationCount.isInfinite ? .infinity : Float(spec.iterationCount)
        var durationScale = 1.0
        var autoreverses = false
        switch spec.direction {
        case "reverse":
            values.reverse()
            keyTimes = Array(keyTimes.map { 1 - $0 }.reversed())
            timings.reverse()
        case "alternate":
            if spec.iterationCount.isInfinite {
                autoreverses = true
            } else if let expanded = expandedAlternate(values: values, keyTimes: keyTimes,
                                                       timings: timings, iterations: spec.iterationCount,
                                                       direction: spec.direction,
                                                       animationName: spec.name) {
                values = expanded.values
                keyTimes = expanded.keyTimes
                timings = expanded.timings
                repeatCount = 1
                durationScale = spec.iterationCount
            } else {
                return nil
            }
        case "alternate-reverse":
            if spec.iterationCount.isInfinite {
                values.reverse()
                keyTimes = Array(keyTimes.map { 1 - $0 }.reversed())
                timings.reverse()
                autoreverses = true
            } else if let expanded = expandedAlternate(values: values, keyTimes: keyTimes,
                                                       timings: timings, iterations: spec.iterationCount,
                                                       direction: spec.direction,
                                                       animationName: spec.name) {
                values = expanded.values
                keyTimes = expanded.keyTimes
                timings = expanded.timings
                repeatCount = 1
                durationScale = spec.iterationCount
            } else {
                return nil
            }
        default:
            break
        }
        return (values, keyTimes, timings, repeatCount, durationScale, autoreverses)
    }

    /// Expands a finite `alternate`/`alternate-reverse` count into one sampled timeline: Core
    /// Animation's `autoreverses` repeats a single forward/back pair, while CSS counts every
    /// iteration, so the exact sequence is built here.
    private static func expandedAlternate<T>(values: [T], keyTimes: [Double],
                                             timings: [CAMediaTimingFunction], iterations: Double,
                                             direction: String, animationName: String)
        -> (values: [T], keyTimes: [Double], timings: [CAMediaTimingFunction])? {
        guard iterations == iterations.rounded(), iterations <= 100 else {
            SVGLog.addSLog(errorStr: "CSS animation '\(animationName)': fractional or very large "
                + "alternating iteration counts are not supported; skipped")
            return nil
        }
        let count = Int(iterations)
        var outValues: [T] = []
        var outTimes: [Double] = []
        var outTimings: [CAMediaTimingFunction] = []
        for run in 0..<count {
            let reversed = direction == "alternate" ? run % 2 == 1 : run % 2 == 0
            let runValues = reversed ? Array(values.reversed()) : values
            let runTimes = reversed ? Array(keyTimes.map { 1 - $0 }.reversed()) : keyTimes
            let runTimings = reversed ? Array(timings.reversed()) : timings
            for (index, value) in runValues.enumerated() {
                if run > 0 && index == 0 { continue }  // the boundary sample belongs to the previous run
                outValues.append(value)
                outTimes.append((Double(run) + runTimes[index]) / iterations)
            }
            outTimings.append(contentsOf: runTimings)
        }
        return (outValues, outTimes, outTimings)
    }

    private static func cssValues(for property: Property, values: [Value]) -> SVGAnimation.CSSValues? {
        switch property {
        case .strokeDashoffset, .opacity:
            var numbers: [Double] = []
            for value in values {
                guard case .number(let number) = value else { return nil }
                numbers.append(number)
            }
            return .numbers(numbers)
        case .fill, .stroke:
            var colors: [CGColor] = []
            for value in values {
                guard case .color(let color) = value else { return nil }
                colors.append(color)
            }
            return .colors(colors)
        case .transform:
            var transforms: [CATransform3D] = []
            for value in values {
                guard case .transform(let transform) = value else { return nil }
                transforms.append(transform)
            }
            return .transforms(transforms)
        }
    }

    private static func cssProperty(for property: Property) -> SVGAnimation.CSSProperty {
        switch property {
        case .strokeDashoffset: return .strokeDashoffset
        case .opacity: return .opacity
        case .fill: return .fill
        case .stroke: return .stroke
        case .transform: return .transform
        }
    }

    private static func baseValue(for property: Property, base: BaseValues) -> Value? {
        switch property {
        case .strokeDashoffset: return .number(base.dashoffset)
        case .opacity: return .number(base.opacity)
        case .fill: return base.fill.map { .color($0) }
        case .stroke: return base.stroke.map { .color($0) }
        case .transform: return .transform(base.transform)
        }
    }

    // MARK: - Property values

    private static func parseValue(_ raw: String, property: Property) -> Value? {
        switch property {
        case .strokeDashoffset:
            return SVGAnimation.parseDashoffset(raw).map { .number($0) }
        case .opacity:
            return parseOpacity(raw).map { .number($0) }
        case .fill, .stroke:
            guard let color = SVGColors.parse(string: raw) else { return nil }
            return .color(color.cgColor)
        case .transform:
            return transformMatrix(raw).map { .transform($0) }
        }
    }

    private static func parseOpacity(_ raw: String) -> Double? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let number: Double?
        if text.hasSuffix("%") {
            number = Double(text.dropLast()).map { $0 / 100 }
        } else {
            number = Double(text)
        }
        guard let number = number else { return nil }
        return min(1, max(0, number))
    }

    /// Parses a CSS transform list into a matrix.
    ///
    /// CSS and the SVG `transform` attribute share the function list semantics (the first function
    /// is the outer composition), so the units are stripped and the list is handed to the kit's
    /// attribute parser. Percentages and 3D rotations about x/y are not representable and skip the
    /// animation.
    private static func transformMatrix(_ raw: String) -> CATransform3D? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty || text.lowercased() == "none" { return CATransform3DIdentity }
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
            guard let piece = transformPiece(function: name.lowercased(), arguments: arguments) else {
                return nil
            }
            pieces.append(piece)
        }
        guard !pieces.isEmpty else { return nil }
        return try? SVGTransform.get(string: pieces.joined(separator: " "))
    }

    private static func transformPiece(function: String, arguments: String) -> String? {
        let parts = arguments.split(whereSeparator: { $0 == "," || $0.isWhitespace }).map(String.init)
        switch function {
        case "translate":
            guard let x = length(parts.first) else { return nil }
            let y = parts.count > 1 ? length(parts[1]) : 0
            guard let y = y else { return nil }
            return "translate(\(number(x)), \(number(y)))"
        case "translatex":
            guard let x = length(parts.first) else { return nil }
            return "translate(\(number(x)), 0)"
        case "translatey":
            guard let y = length(parts.first) else { return nil }
            return "translate(0, \(number(y)))"
        case "translatez":
            return "translate(0, 0)"
        case "translate3d":
            guard parts.count == 3, let x = length(parts[0]), let y = length(parts[1]) else { return nil }
            return "translate(\(number(x)), \(number(y)))"
        case "scale":
            guard let sx = parseNumber(parts.first) else { return nil }
            let sy = parts.count > 1 ? parseNumber(parts[1]) : sx
            guard let sy = sy else { return nil }
            return "scale(\(number(sx)), \(number(sy)))"
        case "scalex":
            guard let sx = parseNumber(parts.first) else { return nil }
            return "scale(\(number(sx)), 1)"
        case "scaley":
            guard let sy = parseNumber(parts.first) else { return nil }
            return "scale(1, \(number(sy)))"
        case "scalez":
            return "scale(1, 1)"
        case "scale3d":
            guard parts.count == 3, let sx = parseNumber(parts[0]), let sy = parseNumber(parts[1]) else { return nil }
            return "scale(\(number(sx)), \(number(sy)))"
        case "rotate", "rotatez":
            guard let angle = angle(parts.first) else { return nil }
            return "rotate(\(number(angle)))"
        case "rotate3d":
            guard parts.count == 4, let x = parseNumber(parts[0]), let y = parseNumber(parts[1]),
                  let z = parseNumber(parts[2]), let angle = angle(parts[3]),
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
            var numbers: [Double] = []
            for part in parts {
                guard let value = Double(part) else { return nil }
                numbers.append(value)
            }
            return "matrix(" + numbers.map { number($0) }.joined(separator: ", ") + ")"
        default:
            return nil
        }
    }

    /// A plain CSS number (scale factors, matrix entries).
    private static func parseNumber(_ part: String?) -> Double? {
        guard let part = part else { return nil }
        return Double(part)
    }

    /// A CSS length in user units: `px` and unitless values only (percentages are relative to
    /// something the layer transform does not know).
    private static func length(_ part: String?) -> Double? {
        guard var value = part else { return nil }
        if value.hasSuffix("px") { value = String(value.dropLast(2)) }
        return Double(value)
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

    private static func easingFunction(_ text: String, animationName: String) -> CAMediaTimingFunction {
        switch text {
        case "linear": return CAMediaTimingFunction(name: .linear)
        case "ease": return CAMediaTimingFunction(name: .easeInEaseOut)
        case "ease-in": return CAMediaTimingFunction(name: .easeIn)
        case "ease-out": return CAMediaTimingFunction(name: .easeOut)
        case "ease-in-out": return CAMediaTimingFunction(name: .easeInEaseOut)
        default:
            if text.hasPrefix("cubic-bezier("), text.hasSuffix(")") {
                let body = text.dropFirst("cubic-bezier(".count).dropLast()
                let numbers = body.split(separator: ",").compactMap {
                    Float($0.trimmingCharacters(in: .whitespaces))
                }
                if numbers.count == 4 {
                    return CAMediaTimingFunction(controlPoints: numbers[0], numbers[1],
                                                 numbers[2], numbers[3])
                }
            }
            SVGLog.addSLog(errorStr: "CSS animation '\(animationName)': timing function '\(text)' is not supported; linear is used")
            return CAMediaTimingFunction(name: .linear)
        }
    }

    private static func caFillMode(_ value: String) -> CAMediaTimingFillMode? {
        switch value {
        case "forwards": return .forwards
        case "backwards": return .backwards
        case "both": return .both
        default: return nil
        }
    }

    // MARK: - CSS value parsing helpers

    private static func parseTime(_ token: String) -> TimeInterval? {
        let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasSuffix("ms"), let milliseconds = Double(value.dropLast(2)) {
            return milliseconds / 1000
        }
        if value.hasSuffix("s"), let seconds = Double(value.dropLast(1)) {
            return seconds
        }
        return nil
    }

    private static func parseIterationCount(_ token: String) -> Double {
        let value = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value == "infinite" { return .infinity }
        return Double(value) ?? 1
    }

    private static func parseShorthand(_ item: String) -> SVGCSSAnimationSpec {
        var spec = SVGCSSAnimationSpec(name: "")
        let tokens = splitTokens(item)
        var seenTime = false
        for token in tokens {
            let lower = token.lowercased()
            if lower.hasSuffix("s"), let time = parseTime(lower) {
                if !seenTime {
                    spec.duration = time
                    seenTime = true
                } else {
                    spec.delay = time
                }
            } else if isTimingFunction(lower) {
                spec.timingFunction = lower
            } else if lower == "infinite" {
                spec.iterationCount = .infinity
            } else if let count = Double(lower) {
                spec.iterationCount = count
            } else if ["normal", "reverse", "alternate", "alternate-reverse"].contains(lower) {
                spec.direction = lower
            } else if ["forwards", "backwards", "both"].contains(lower) {
                spec.fillMode = lower
            } else if ["running", "paused"].contains(lower) {
                spec.playState = lower
            } else if lower == "none" {
                if tokens.count == 1 {
                    spec.name = "none"
                } else {
                    spec.fillMode = "none"
                }
            } else if spec.name.isEmpty {
                spec.name = token
            }
        }
        return spec
    }

    private static func isTimingFunction(_ value: String) -> Bool {
        return ["linear", "ease", "ease-in", "ease-out", "ease-in-out"].contains(value)
            || value.hasPrefix("cubic-bezier(")
            || value.hasPrefix("steps(")
            || value.hasPrefix("linear(")
    }

    /// Splits a comma-separated CSS list at the top level (function arguments stay whole).
    private static func splitList(_ value: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        var quote: Character?
        for character in value {
            if let q = quote {
                current.append(character)
                if character == q { quote = nil }
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                current.append(character)
            } else if character == "(" {
                depth += 1
                current.append(character)
            } else if character == ")" {
                depth = max(0, depth - 1)
                current.append(character)
            } else if character == ",", depth == 0 {
                parts.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        parts.append(current)
        return parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Splits the tokens of one `animation` shorthand item at the top level.
    private static func splitTokens(_ value: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var depth = 0
        for character in value {
            if character == "(" {
                depth += 1
                current.append(character)
            } else if character == ")" {
                depth = max(0, depth - 1)
                current.append(character)
            } else if character.isWhitespace, depth == 0 {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    private static func nonEmpty<T>(_ values: [T]?) -> [T]? {
        guard let values = values, !values.isEmpty else { return nil }
        return values
    }

    private static func cycle<T>(_ values: [T], at index: Int) -> T {
        return values[index % values.count]
    }
}
