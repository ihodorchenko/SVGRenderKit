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
/// `SVGAnimation` objects for the properties the layer renderer can animate today.
///
/// Only `stroke-dashoffset` is played so far (`CAShapeLayer.lineDashPhase`); a keyframe block that
/// animates anything else is logged and skipped. The rest of the property set is the plan in
/// `docs/css-animations-plan.md` (M2), and the build-time `Scripts/css-to-smil.py` covers SMIL.
enum SVGCSSAnimations {

    /// The CSS-animated properties the runtime can play today.
    static let supportedProperties: Set<String> = ["stroke-dashoffset"]

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

    /// Builds the runtime animations of one element. `keyframes` looks a `@keyframes` block up in
    /// the document, `baseDashoffset` is the element's resolved `stroke-dashoffset` (the implicit
    /// `0%`/`100%` keyframe value).
    static func animations(specs: [SVGCSSAnimationSpec],
                           keyframes: (String) -> SVGStyleSheet.Keyframes?,
                           baseDashoffset: CGFloat) -> [SVGAnimation] {
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
            if let animation = dashoffsetAnimation(block: block, spec: spec,
                                                   baseDashoffset: Double(baseDashoffset)) {
                result.append(animation)
            }
        }
        return result
    }

    /// The `stroke-dashoffset` animation of one `@keyframes` block, or `nil` when the block does
    /// not animate it (the runtime subset logs and skips it).
    private static func dashoffsetAnimation(block: SVGStyleSheet.Keyframes,
                                            spec: SVGCSSAnimationSpec,
                                            baseDashoffset: Double) -> SVGAnimation? {
        var frames: [(offset: Double, value: Double, timing: String?)] = []
        for frame in block.frames {
            guard let raw = frame.declarations["stroke-dashoffset"] else { continue }
            guard let value = SVGAnimation.parseDashoffset(raw) else {
                SVGLog.addSLog(errorStr: "CSS animation '\(spec.name)': unsupported stroke-dashoffset '\(raw)'; skipped")
                return nil
            }
            frames.append((frame.offset, value,
                           frame.declarations["animation-timing-function"]?.trimmingCharacters(in: .whitespaces).lowercased()))
        }
        guard !frames.isEmpty else {
            SVGLog.addSLog(errorStr: "CSS animation '\(spec.name)' animates no property the runtime CSS subset supports; skipped")
            return nil
        }
        // A keyframe that does not mention the property is ignored for it; only the missing
        // endpoints come from the element's base value (CSS Animations L1 §keyframes).
        frames.sort { $0.offset < $1.offset }
        var deduped: [(offset: Double, value: Double, timing: String?)] = []
        for frame in frames {
            if let last = deduped.last, abs(last.offset - frame.offset) < 1e-9 {
                deduped[deduped.count - 1] = frame
            } else {
                deduped.append(frame)
            }
        }
        frames = deduped
        if frames[0].offset > 1e-9 { frames.insert((0, baseDashoffset, nil), at: 0) }
        if frames[frames.count - 1].offset < 1 - 1e-9 { frames.append((1, baseDashoffset, nil)) }
        guard frames.count >= 2 else { return nil }

        var values = frames.map { formatNumber($0.value) }
        var keyTimes = frames.map { $0.offset }
        var timings = (0..<(frames.count - 1)).map { index -> CAMediaTimingFunction in
            easingFunction(frames[index].timing ?? spec.timingFunction, animationName: spec.name)
        }
        let duration = spec.duration
        var repeatCount: Float = spec.iterationCount.isInfinite ? .infinity : Float(spec.iterationCount)
        var autoreverses = false
        var durationScale = 1.0

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
                                                       direction: spec.direction, spec: spec) {
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
                                                       direction: spec.direction, spec: spec) {
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

        return SVGAnimation(kind: .strokeDashoffset,
                            values: values,
                            keyTimes: keyTimes,
                            duration: duration * durationScale,
                            repeatCount: repeatCount,
                            begin: spec.delay,
                            timingFunctions: timings,
                            autoreverses: autoreverses,
                            fillMode: caFillMode(spec.fillMode))
    }

    /// Expands a finite `alternate`/`alternate-reverse` count into one sampled timeline: Core
    /// Animation's `autoreverses` repeats a single forward/back pair, while CSS counts every
    /// iteration, so the exact sequence is built here.
    private static func expandedAlternate(values: [String], keyTimes: [Double],
                                          timings: [CAMediaTimingFunction],
                                          iterations: Double, direction: String,
                                          spec: SVGCSSAnimationSpec)
        -> (values: [String], keyTimes: [Double], timings: [CAMediaTimingFunction])? {
        guard iterations == iterations.rounded(), iterations <= 100 else {
            SVGLog.addSLog(errorStr: "CSS animation '\(spec.name)': fractional or very large alternating iteration counts are not supported; skipped")
            return nil
        }
        let count = Int(iterations)
        var outValues: [String] = []
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

    // MARK: - CSS values

    /// A CSS time value (`2s`, `300ms`); bare numbers are iteration counts, not times.
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

    private static func formatNumber(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int(value))
        }
        return String(value)
    }

    // MARK: - List helpers

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
