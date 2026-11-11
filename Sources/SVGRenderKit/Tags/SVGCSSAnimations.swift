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
                           properties: Set<Property>,
                           transformContextProvider: (() -> SVGTransformStyle.Context)? = nil) -> [SVGAnimation] {
        var result: [SVGAnimation] = []
        for spec in specs {
            let name = spec.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name != "none" else { continue }
            if spec.playState == "paused", spec.delay > 0,
               spec.fillMode != "backwards", spec.fillMode != "both" {
                // A paused animation before its active phase has no effect without a backwards fill.
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
                if let animation = animation(for: property, block: block, spec: spec, base: base,
                                             transformContextProvider: transformContextProvider) {
                    result.append(animation)
                }
            }
        }
        return result
    }

    private static func animation(for property: Property,
                                  block: SVGStyleSheet.Keyframes,
                                  spec: SVGCSSAnimationSpec,
                                  base: BaseValues,
                                  transformContextProvider: (() -> SVGTransformStyle.Context)?) -> SVGAnimation? {
        var frames: [(offset: Double, raw: String, timing: String?, origin: String?, box: String?)] = []
        for frame in block.frames {
            guard let raw = frame.declarations[property.rawValue] else { continue }
            let timing = frame.declarations["animation-timing-function"]?
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            frames.append((frame.offset, raw, timing,
                           frame.declarations["transform-origin"],
                           frame.declarations["transform-box"]))
        }
        guard !frames.isEmpty else { return nil }
        // A keyframe that does not mention the property is ignored for it (CSS Animations L1).
        frames.sort { $0.offset < $1.offset }
        var deduped: [(offset: Double, raw: String, timing: String?, origin: String?, box: String?)] = []
        for frame in frames {
            if let last = deduped.last, abs(last.offset - frame.offset) < 1e-9 {
                deduped[deduped.count - 1] = frame
            } else {
                deduped.append(frame)
            }
        }
        frames = deduped

        // Some designers declare `transform-origin`/`transform-box` inside the keyframes only
        // (usually in the 0% frame). Without a static declaration the whole rotation/scale would
        // otherwise pivot around the SVG initial 0 0; use the first keyframe value as the pivot
        // for every sampled matrix. (CSS would animate the origin itself; a constant pivot is the
        // closer, documented approximation.)
        var effectiveContextProvider = transformContextProvider
        if property == .transform, let provider = transformContextProvider {
            let frameOrigin = block.frames.compactMap { $0.declarations["transform-origin"] }.first
            let frameBox = block.frames.compactMap { $0.declarations["transform-box"] }.first
            if frameOrigin != nil || frameBox != nil {
                effectiveContextProvider = {
                    let base = provider()
                    let staticOrigin = (base.origin?.isEmpty == false) ? base.origin : nil
                    return SVGTransformStyle.Context(
                        viewBox: base.viewBox,
                        bbox: base.bbox,
                        origin: staticOrigin ?? frameOrigin,
                        box: base.box ?? frameBox)
                }
            }
        }

        var values: [Value] = []
        for frame in frames {
            guard let value = parseValue(frame.raw, property: property,
                                         transformContextProvider: effectiveContextProvider) else {
                SVGLog.addSLog(errorStr: "CSS animation '\(spec.name)': unsupported "
                    + "\(property.rawValue) value '\(frame.raw)'; skipped")
                return nil
            }
            values.append(value)
        }
        // The implicit 0%/100% keyframes come from the element's computed value. A property
        // without a usable base (a `stroke` whose computed value is `none`, a gradient `fill`)
        // is still animatable when the keyframes define both endpoints themselves.
        let needsImplicitStart = frames[0].offset > 1e-9
        let needsImplicitEnd = frames[frames.count - 1].offset < 1 - 1e-9
        if needsImplicitStart || needsImplicitEnd {
            guard let baseValue = baseValue(for: property, base: base) else {
                SVGLog.addSLog(errorStr: "CSS animation '\(spec.name)': \(property.rawValue) is "
                    + "not interpolable on this element; skipped")
                return nil
            }
            if needsImplicitStart {
                frames.insert((0, "", nil, nil, nil), at: 0)
                values.insert(baseValue, at: 0)
            }
            if needsImplicitEnd {
                frames.append((1, "", nil, nil, nil))
                values.append(baseValue)
            }
        }
        guard values.count >= 2 else { return nil }

        var keyTimes = frames.map { $0.offset }
        var easings = (0..<(values.count - 1)).map { index in
            easing(frames[index].timing ?? spec.timingFunction, animationName: spec.name)
        }
        // A transform list is converted to matrices for Core Animation; a 0°→360° rotation would
        // then be identity at both ends and never move. Sample those segments component-wise,
        // exactly as CSS interpolates the transform functions.
        if property == .transform, let context = transformContextProvider?() {
            let raws = frames.map { $0.raw }
            let easingTexts = frames.map { $0.timing ?? spec.timingFunction }
            func originPoint(_ text: String?) -> CGPoint? {
                guard let text = text, !text.isEmpty else { return nil }
                return SVGTransformStyle.transformOrigin(text, context: context)
            }
            let staticOrigin = originPoint(context.origin)
            let startOrigin = originPoint(frames.first { abs($0.offset) < 1e-9 }?.origin) ?? staticOrigin
            let endOrigin = originPoint(frames.first { abs($0.offset - 1) < 1e-9 }?.origin) ?? staticOrigin
            // CSS animates `transform-origin` itself: a declaration at 0% animates towards the
            // underlying value at 100% over the whole iteration, wherever the transform keyframes
            // are. Only the transform functions follow the per-keyframe segments.
            let originEasing = frames.first { abs($0.offset) < 1e-9 }?.timing
                ?? spec.timingFunction
            // An implicit endpoint is the element's computed transform (`none` in practice);
            // when that base is identity it can be synthesized as an identity function list and
            // sampled exactly like an explicit keyframe.
            var baseIsIdentity = false
            if case .transform(let baseMatrix)? = baseValue(for: .transform, base: base) {
                baseIsIdentity = CATransform3DIsIdentity(baseMatrix)
            }
            if let sampled = sampledTransform(values: values, raws: raws, keyTimes: keyTimes,
                                              easings: easings, easingTexts: easingTexts,
                                              originStart: startOrigin, originEnd: endOrigin,
                                              originEasingText: originEasing,
                                              baseIsIdentity: baseIsIdentity, context: context) {
                values = sampled.values
                keyTimes = sampled.keyTimes
                easings = sampled.easings
            }
        }
        // `steps()`, `linear()` and an overshooting `cubic-bezier()` are not expressible as a
        // Core Animation timing function: sample them into extra keyframes instead.
        if easings.contains(where: { !$0.isRepresentable }) {
            let expanded = expand(values: values, keyTimes: keyTimes, easings: easings)
            values = expanded.values
            keyTimes = expanded.keyTimes
            easings = expanded.easings
        }
        let timings = easings.map { $0.timingFunction }
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
                            cssValues: cssValues,
                            paused: spec.playState == "paused")
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

    private static func parseValue(_ raw: String, property: Property,
                                   transformContextProvider: (() -> SVGTransformStyle.Context)?) -> Value? {
        switch property {
        case .strokeDashoffset:
            return SVGAnimation.parseDashoffset(raw).map { .number($0) }
        case .opacity:
            return parseOpacity(raw).map { .number($0) }
        case .fill, .stroke:
            guard let color = SVGColors.parse(string: raw) else { return nil }
            return .color(color.cgColor)
        case .transform:
            guard let context = transformContextProvider?(),
                  let matrix = SVGTransformStyle.matrix(raw, context: context) else { return nil }
            return .transform(matrix)
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

    // MARK: - Component-wise transform sampling

    /// Samples the transform segments Core Animation would get wrong: a large rotation (its
    /// matrix decomposition loses the winding) or an animated `transform-origin` (CSS moves the
    /// pivot over the whole iteration, so the element also translates). Transform functions are
    /// interpolated per keyframe segment; the origin follows the animation-wide 0%→100% track.
    private static func sampledTransform(values: [Value], raws: [String], keyTimes: [Double],
                                         easings: [Easing], easingTexts: [String],
                                         originStart: CGPoint?, originEnd: CGPoint?,
                                         originEasingText: String, baseIsIdentity: Bool,
                                         context: SVGTransformStyle.Context)
        -> (values: [Value], keyTimes: [Double], easings: [Easing])? {
        guard values.count >= 2, values.count == raws.count, values.count == keyTimes.count,
              values.count == easings.count + 1, easingTexts.count == values.count else { return nil }
        var components: [[SVGTransformStyle.Component]?] = []
        for raw in raws {
            components.append(raw.isEmpty ? nil : SVGTransformStyle.components(raw, context: context))
        }
        if baseIsIdentity {
            for index in components.indices where components[index] == nil {
                let neighbor = index > 0 ? components[index - 1] : components[index + 1]
                if let neighbor = neighbor {
                    components[index] = SVGTransformStyle.identityComponents(matching: neighbor)
                }
            }
        }
        let baseContext = SVGTransformStyle.Context(viewBox: context.viewBox, bbox: context.bbox)
        let originAnimated = originStart != originEnd
        let steps = 24
        var outValues: [Value] = [values[0]]
        var outTimes: [Double] = [keyTimes[0]]
        var outEasings: [Easing] = []
        var sampledAnything = false
        for index in 0..<(values.count - 1) {
            let fromComponents = components[index]
            let toComponents = components[index + 1]
            var needsSampling = originAnimated
            if let fromComponents = fromComponents, let toComponents = toComponents,
               let delta = SVGTransformStyle.rotationDelta(fromComponents, toComponents), delta >= 180 {
                needsSampling = true
            }
            guard needsSampling, let fromComponents = fromComponents, let toComponents = toComponents else {
                outValues.append(values[index + 1])
                outTimes.append(keyTimes[index + 1])
                outEasings.append(easings[index])
                continue
            }
            sampledAnything = true
            let t0 = keyTimes[index]
            let t1 = keyTimes[index + 1]
            for step in 1...steps {
                let progress = Double(step) / Double(steps)
                let eased = easedFraction(easingTexts[index], progress)
                guard let raw = SVGTransformStyle.interpolatedTransform(fromComponents, toComponents,
                                                                        progress: CGFloat(eased)),
                      let base = SVGTransformStyle.matrix(raw, context: baseContext) else { return nil }
                let matrix: CATransform3D
                if originStart != nil || originEnd != nil {
                    let global = t0 + (t1 - t0) * progress
                    let originProgress = easedFraction(originEasingText, global)
                    let from = originStart ?? .zero
                    let to = originEnd ?? .zero
                    let origin = CGPoint(x: from.x + (to.x - from.x) * CGFloat(originProgress),
                                         y: from.y + (to.y - from.y) * CGFloat(originProgress))
                    matrix = SVGTransformStyle.composed(around: base, origin: origin)
                } else {
                    matrix = base
                }
                outValues.append(.transform(matrix))
                outTimes.append(t0 + (t1 - t0) * progress)
                outEasings.append(.timing(CAMediaTimingFunction(name: .linear)))
            }
        }
        guard sampledAnything else { return nil }
        return (outValues, outTimes, outEasings)
    }

    /// The eased progress of a CSS timing function, used when a transform segment is sampled.
    private static func easedFraction(_ text: String, _ progress: Double) -> Double {
        let p = min(1, max(0, progress))
        switch text {
        case "linear": return p
        case "ease": return cubicBezierY(p, 0.25, 0.1, 0.25, 1)
        case "ease-in": return cubicBezierY(p, 0.42, 0, 1, 1)
        case "ease-out": return cubicBezierY(p, 0, 0, 0.58, 1)
        case "ease-in-out": return cubicBezierY(p, 0.42, 0, 0.58, 1)
        default: break
        }
        if text.hasPrefix("cubic-bezier("), text.hasSuffix(")") {
            let body = text.dropFirst("cubic-bezier(".count).dropLast()
            let numbers = body.split(separator: ",").compactMap {
                Double($0.trimmingCharacters(in: .whitespaces))
            }
            if numbers.count == 4 {
                return cubicBezierY(p, numbers[0], numbers[1], numbers[2], numbers[3])
            }
        }
        if text.hasPrefix("steps("), text.hasSuffix(")") {
            let body = text.dropFirst("steps(".count).dropLast()
            let parts = body.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
            if let count = parts.first.flatMap({ Int($0) }), count > 0 {
                if p >= 1 { return 1 }
                let position = parts.count > 1 ? parts[1] : "jump-end"
                let value = Double(count) * p
                switch position {
                case "start", "jump-start":
                    return min(1, (floor(value) + 1) / Double(count))
                case "jump-none":
                    return min(1, floor(value) / Double(max(1, count - 1)))
                case "jump-both":
                    return min(1, (floor(value) + 1) / Double(count + 1))
                default:
                    return floor(value) / Double(count)
                }
            }
        }
        if text.hasPrefix("linear("), text.hasSuffix(")") {
            let body = String(text.dropFirst("linear(".count).dropLast())
            if let samples = linearEasingSamples(body), let first = samples.first, let last = samples.last {
                if p <= first.time { return first.fraction }
                if p >= last.time { return last.fraction }
                for index in 1..<samples.count where p <= samples[index].time {
                    let a = samples[index - 1]
                    let b = samples[index]
                    let span = b.time - a.time
                    guard span > 0 else { return b.fraction }
                    return a.fraction + (b.fraction - a.fraction) * (p - a.time) / span
                }
            }
        }
        return p
    }

    // MARK: - Easing (Core Animation timing functions and CSS-only curves)

    private enum StepPosition {
        case jumpStart
        case jumpEnd
        case jumpNone
        case jumpBoth
    }

    /// One segment's easing: either a Core Animation timing function or a curve sampled into
    /// keyframes because Core Animation cannot express it.
    private enum Easing {
        /// Breakpoints as `(local time 0…1, eased fraction)`.
        case sampled([(time: Double, fraction: Double)])
        case steps(count: Int, position: StepPosition)
        case timing(CAMediaTimingFunction)

        var isRepresentable: Bool {
            if case .timing = self { return true }
            return false
        }

        var timingFunction: CAMediaTimingFunction {
            if case .timing(let function) = self { return function }
            return CAMediaTimingFunction(name: .linear)
        }
    }

    private static func easing(_ text: String, animationName: String) -> Easing {
        switch text {
        case "linear": return .timing(CAMediaTimingFunction(name: .linear))
        case "ease": return .timing(CAMediaTimingFunction(name: .easeInEaseOut))
        case "ease-in": return .timing(CAMediaTimingFunction(name: .easeIn))
        case "ease-out": return .timing(CAMediaTimingFunction(name: .easeOut))
        case "ease-in-out": return .timing(CAMediaTimingFunction(name: .easeInEaseOut))
        default: break
        }
        if text.hasPrefix("cubic-bezier(") {
            let body = text.dropFirst("cubic-bezier(".count).dropLast()
            let numbers = body.split(separator: ",").compactMap {
                Double($0.trimmingCharacters(in: .whitespaces))
            }
            if numbers.count == 4, numbers[0] >= 0, numbers[0] <= 1, numbers[2] >= 0, numbers[2] <= 1 {
                if numbers[1] >= 0, numbers[1] <= 1, numbers[3] >= 0, numbers[3] <= 1 {
                    return .timing(CAMediaTimingFunction(controlPoints: Float(numbers[0]),
                                                         Float(numbers[1]),
                                                         Float(numbers[2]),
                                                         Float(numbers[3])))
                }
                // An overshoot (y outside 0…1): sample the curve into keyframes.
                return .sampled(cubicBezierSamples(numbers[0], numbers[1], numbers[2], numbers[3]))
            }
        }
        if text.hasPrefix("steps("), text.hasSuffix(")") {
            let body = text.dropFirst("steps(".count).dropLast()
            let parts = body.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
            if let count = parts.first.flatMap({ Int($0) }), count > 0 {
                var position = StepPosition.jumpEnd
                if parts.count > 1 {
                    switch parts[1] {
                    case "start", "jump-start": position = .jumpStart
                    case "end", "jump-end": position = .jumpEnd
                    case "jump-none": position = .jumpNone
                    case "jump-both": position = .jumpBoth
                    default:
                        SVGLog.addSLog(errorStr: "CSS animation '\(animationName)': unknown steps() position '\(parts[1])'; jump-end is used")
                    }
                }
                if position == .jumpNone, count < 2 {
                    SVGLog.addSLog(errorStr: "CSS animation '\(animationName)': steps(1, jump-none) is invalid; linear is used")
                    return .timing(CAMediaTimingFunction(name: .linear))
                }
                return .steps(count: count, position: position)
            }
        }
        if text.hasPrefix("linear("), text.hasSuffix(")") {
            let body = text.dropFirst("linear(".count).dropLast()
            if let samples = linearEasingSamples(String(body)) {
                return .sampled(samples)
            }
        }
        SVGLog.addSLog(errorStr: "CSS animation '\(animationName)': timing function '\(text)' is not supported; linear is used")
        return .timing(CAMediaTimingFunction(name: .linear))
    }

    /// Evaluates the cubic-bezier timing curve at `x` (a binary search for the Bézier parameter,
    /// then the y value there).
    private static func cubicBezierY(_ x: Double, _ x1: Double, _ y1: Double,
                                     _ x2: Double, _ y2: Double) -> Double {
        func bezier(_ t: Double, _ p1: Double, _ p2: Double) -> Double {
            let mt = 1 - t
            return 3 * mt * mt * t * p1 + 3 * mt * t * t * p2 + t * t * t
        }
        var low = 0.0
        var high = 1.0
        for _ in 0..<40 {
            let mid = (low + high) / 2
            if bezier(mid, x1, x2) < x { low = mid } else { high = mid }
        }
        return bezier((low + high) / 2, y1, y2)
    }

    private static func cubicBezierSamples(_ x1: Double, _ y1: Double,
                                           _ x2: Double, _ y2: Double) -> [(time: Double, fraction: Double)] {
        let steps = 24
        return (0...steps).map { index in
            let time = Double(index) / Double(steps)
            return (time, cubicBezierY(time, x1, y1, x2, y2))
        }
    }

    /// Parses the CSS `linear()` easing into its breakpoints; `nil` when the syntax is invalid.
    private static func linearEasingSamples(_ body: String) -> [(time: Double, fraction: Double)]? {
        let entries = body.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !entries.isEmpty else { return nil }
        var values: [Double] = []
        var inputs: [Double?] = []
        for entry in entries {
            let tokens = entry.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard let value = tokens.first.flatMap({ Double($0) }) else { return nil }
            values.append(value)
            if tokens.count > 1, tokens[1].hasSuffix("%"), let percent = Double(tokens[1].dropLast()) {
                inputs.append(percent / 100)
            } else {
                inputs.append(nil)
            }
        }
        guard values.count >= 2 else { return nil }
        if inputs.contains(where: { $0 == nil }) {
            // Missing input percentages are distributed evenly between the annotated anchors,
            // with the ends pinned to 0 and 1 (the CSS `linear()` rule).
            if inputs[0] == nil { inputs[0] = 0 }
            if inputs[inputs.count - 1] == nil { inputs[inputs.count - 1] = 1 }
            var index = 0
            while index < inputs.count {
                guard inputs[index] == nil else {
                    index += 1
                    continue
                }
                var end = index
                while end < inputs.count, inputs[end] == nil { end += 1 }
                guard end < inputs.count, let startTime = inputs[index - 1],
                      let endTime = inputs[end] else { return nil }
                let gaps = end - index + 1
                for offset in 0..<gaps {
                    inputs[index + offset] = startTime
                        + (endTime - startTime) * Double(offset + 1) / Double(gaps)
                }
                index = end
            }
            for index in 1..<inputs.count {
                guard let previous = inputs[index - 1], let current = inputs[index],
                      previous <= current else { return nil }
            }
        }
        var samples: [(time: Double, fraction: Double)] = []
        for index in 0..<values.count {
            let time = min(1, max(0, inputs[index] ?? 0))
            samples.append((time, values[index]))
        }
        // CSS requires the first input at 0 and the last at 1; clamp the ends so the segment
        // still spans the whole keyframe interval.
        if samples[0].time > 0 { samples.insert((0, values[0]), at: 0) }
        if samples[samples.count - 1].time < 1 { samples.append((1, values[values.count - 1])) }
        return samples
    }

    /// Breakpoints for a `steps()` easing. A tiny gap before every jump keeps the jump sharp
    /// when Core Animation interpolates the sampled keyframes linearly.
    private static func stepSamples(count: Int, position: StepPosition) -> [(time: Double, fraction: Double)] {
        let n = Double(count)
        let epsilon = min(1e-4, 0.25 / n)
        var samples: [(time: Double, fraction: Double)] = []
        for step in 0..<count {
            let start = Double(step) / n
            let end = min(1 - epsilon, (Double(step) + 1) / n - epsilon)
            let value: Double
            switch position {
            case .jumpEnd: value = Double(step) / n
            case .jumpStart: value = (Double(step) + 1) / n
            case .jumpNone: value = Double(step) / Double(count - 1)
            case .jumpBoth: value = (Double(step) + 1) / Double(count + 1)
            }
            samples.append((max(epsilon, start), value))
            samples.append((max(max(epsilon, start), end), value))
        }
        samples.append((1, 1))
        return samples
    }

    /// Expands the segments whose easing is not a Core Animation timing function into sampled
    /// keyframes; every other segment stays a single timing function.
    private static func expand(values: [Value], keyTimes: [Double], easings: [Easing])
        -> (values: [Value], keyTimes: [Double], easings: [Easing]) {
        var outValues = [values[0]]
        var outTimes = [keyTimes[0]]
        var outEasings: [Easing] = []
        for index in 0..<easings.count {
            let from = values[index]
            let to = values[index + 1]
            let t0 = keyTimes[index]
            let t1 = keyTimes[index + 1]
            switch easings[index] {
            case .timing(let function):
                outValues.append(to)
                outTimes.append(t1)
                outEasings.append(.timing(function))
            case .steps(let count, let position):
                appendSamples(stepSamples(count: count, position: position),
                              from: from, to: to, t0: t0, t1: t1,
                              values: &outValues, times: &outTimes, easings: &outEasings)
            case .sampled(let samples):
                appendSamples(samples, from: from, to: to, t0: t0, t1: t1,
                              values: &outValues, times: &outTimes, easings: &outEasings)
            }
        }
        return (outValues, outTimes, outEasings)
    }

    private static func appendSamples(_ samples: [(time: Double, fraction: Double)],
                                      from: Value, to: Value, t0: Double, t1: Double,
                                      values: inout [Value], times: inout [Double],
                                      easings: inout [Easing]) {
        for sample in samples where sample.time > 0 {
            let time = t0 + (t1 - t0) * min(1, max(0, sample.time))
            let value = interpolate(from, to, sample.fraction)
            if let last = times.last, time <= last + 1e-9 {
                values[values.count - 1] = value
                continue
            }
            values.append(value)
            times.append(time)
            easings.append(.timing(CAMediaTimingFunction(name: .linear)))
        }
        // The linear approximation must still reach the segment's end value.
        if let last = times.last, last < t1 - 1e-9 {
            values.append(to)
            times.append(t1)
            easings.append(.timing(CAMediaTimingFunction(name: .linear)))
        }
    }

    /// Interpolates between two keyframe values for the sampled easings.
    private static func interpolate(_ from: Value, _ to: Value, _ fraction: Double) -> Value {
        // An overshooting cubic-bezier is sampled with fractions outside 0…1 on purpose.
        let t = fraction
        switch (from, to) {
        case (.number(let a), .number(let b)):
            return .number(a + (b - a) * t)
        case (.color(let a), .color(let b)):
            return .color(interpolateColor(a, b, t))
        case (.transform(let a), .transform(let b)):
            return .transform(interpolateMatrix(a, b, t))
        default:
            return t < 0.5 ? from : to
        }
    }

    private static func interpolateColor(_ from: CGColor, _ to: CGColor, _ t: Double) -> CGColor {
        let a = UIColor(cgColor: from)
        let b = UIColor(cgColor: to)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = CGFloat(t)
        func channel(_ a: CGFloat, _ b: CGFloat) -> CGFloat { min(1, max(0, a + (b - a) * t)) }
        return UIColor(red: channel(r1, r2), green: channel(g1, g2),
                       blue: channel(b1, b2), alpha: channel(a1, a2)).cgColor
    }

    private static func interpolateMatrix(_ from: CATransform3D, _ to: CATransform3D,
                                          _ t: Double) -> CATransform3D {
        let t = CGFloat(t)
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { return a + (b - a) * t }
        return CATransform3D(m11: mix(from.m11, to.m11), m12: mix(from.m12, to.m12),
                             m13: mix(from.m13, to.m13), m14: mix(from.m14, to.m14),
                             m21: mix(from.m21, to.m21), m22: mix(from.m22, to.m22),
                             m23: mix(from.m23, to.m23), m24: mix(from.m24, to.m24),
                             m31: mix(from.m31, to.m31), m32: mix(from.m32, to.m32),
                             m33: mix(from.m33, to.m33), m34: mix(from.m34, to.m34),
                             m41: mix(from.m41, to.m41), m42: mix(from.m42, to.m42),
                             m43: mix(from.m43, to.m43), m44: mix(from.m44, to.m44))
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
