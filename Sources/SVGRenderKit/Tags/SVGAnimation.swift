import UIKit
import QuartzCore

/// One animation whose attach was deferred together with the layers it targets, so a host can add
/// it to a layer tree that is already installed (see `SVGOptions.defersAnimationAttach`).
struct SVGDeferredAnimation {
    let animation: SVGAnimation
    let layer: CALayer
    let pathLayer: CAShapeLayer?
}

/// A parsed SMIL animation element (`animate`, `animateTransform`, or `set`).
struct SVGAnimation {
    enum Kind {
        case opacity
        case fill
        case stroke
        case transform(type: String)
    }

    var kind: Kind
    var values: [String]
    var keyTimes: [Double]?
    var duration: TimeInterval
    var repeatCount: Float
    var begin: TimeInterval

    /// Parses `<animate>`, `<animateTransform>`, and `<set>` children into animations.
    static func parse(children: [XMLElement]) -> [SVGAnimation] {
        var result: [SVGAnimation] = []
        for child in children {
            let name = child.name
            guard name == "animate" || name == "animateTransform" || name == "set" else { continue }
            let attrs = child.attributesDict()
            guard let attributeName = attrs["attributeName"] else { continue }

            let kind: Kind
            if name == "animateTransform" {
                kind = .transform(type: attrs["type"] ?? "translate")
            } else {
                switch attributeName {
                case "opacity": kind = .opacity
                case "fill": kind = .fill
                case "stroke": kind = .stroke
                default: continue
                }
            }

            var values: [String] = []
            if let valuesStr = attrs["values"] {
                values = valuesStr.components(separatedBy: ";")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            } else if let from = attrs["from"], let to = attrs["to"] {
                values = [from, to]
            } else if name == "set", let to = attrs["to"] {
                values = [to]
            }
            guard !values.isEmpty else { continue }

            let duration = attrs["dur"].flatMap(parseDuration) ?? 0
            let keyTimes: [Double]? = attrs["keyTimes"].map {
                $0.components(separatedBy: ";")
                    .compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            }
            var repeatCount: Float = 1
            if let rc = attrs["repeatCount"] {
                let trimmed = rc.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed == "indefinite" {
                    repeatCount = .infinity
                } else if let f = Float(trimmed) {
                    repeatCount = f
                }
            }
            let begin = attrs["begin"].flatMap(parseDuration) ?? 0

            result.append(SVGAnimation(kind: kind, values: values, keyTimes: keyTimes,
                                       duration: duration, repeatCount: repeatCount, begin: begin))
        }
        return result
    }

    /// Parses an SMIL clock value (`1s`, `500ms`, or a bare number of seconds).
    static func parseDuration(_ string: String) -> TimeInterval? {
        let s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasSuffix("ms"), let value = Double(s.dropLast(2)) {
            return value / 1000
        }
        if s.hasSuffix("s"), let value = Double(s.dropLast(1)) {
            return value
        }
        if let value = Double(s) {
            return value
        }
        return nil
    }

    /// Adds the animation to the appropriate layer. `epoch` is the host time the document's
    /// timeline started at (`begin` is relative to it); `nil` means "now".
    func apply(to layer: CALayer, pathLayer: CAShapeLayer?, epoch: CFTimeInterval? = nil) {
        let targetLayer: CALayer
        let keyPath: String
        switch kind {
        case .opacity: targetLayer = layer; keyPath = "opacity"
        case .fill: targetLayer = pathLayer ?? layer; keyPath = "fillColor"
        case .stroke: targetLayer = pathLayer ?? layer; keyPath = "strokeColor"
        case .transform: targetLayer = layer; keyPath = "transform"
        }

        // `<set>` (single value, no duration) applies the value immediately.
        if duration <= 0, let value = values.first {
            applySet(to: layer, pathLayer: pathLayer, value: value)
            return
        }

        let animation: CAAnimation
        if case .transform(let type) = kind, Self.interpolatesAngle(type),
           let sampled = Self.sampledTransformKeyframes(type: type, values: values, keyTimes: keyTimes) {
            // Core Animation interpolates a transform by decomposing the two matrices, so a
            // large angular step cuts the corner: the pivot drifts off its circle, ≥180° is
            // ambiguous and a whole turn maps to the same matrix at both ends. Sampling the
            // sweep in small steps keeps the trajectory on the circle (B103, B131).
            let keyframe = CAKeyframeAnimation(keyPath: keyPath)
            keyframe.values = sampled.matrices.map { NSValue(caTransform3D: $0) }
            keyframe.keyTimes = sampled.times.map { NSNumber(value: $0) }
            animation = keyframe
        } else if values.count == 2 {
            let basic = CABasicAnimation(keyPath: keyPath)
            basic.fromValue = anyValue(from: values[0])
            basic.toValue = anyValue(from: values[1])
            animation = basic
        } else {
            let keyframe = CAKeyframeAnimation(keyPath: keyPath)
            keyframe.values = values.map { anyValue(from: $0) }
            if let keyTimes = keyTimes, keyTimes.count == values.count {
                keyframe.keyTimes = keyTimes.map { NSNumber(value: $0) }
            }
            animation = keyframe
        }
        animation.duration = duration
        animation.repeatCount = repeatCount
        animation.beginTime = (epoch ?? CACurrentMediaTime()) + begin
        targetLayer.add(animation, forKey: keyPath)
    }

    /// The largest angular step, in degrees, between two sampled keyframes.
    static let maxAngleStep: CGFloat = 15

    /// Cap on the samples of one `values` segment (30 full turns at `maxAngleStep`): a document
    /// can ask for `values="0;1e9"`, which would otherwise build millions of keyframes.
    static let maxSamplesPerSegment = 720

    private static func sampleCount(from: CGFloat, to: CGFloat) -> Int {
        let raw = (abs(to - from) / maxAngleStep).rounded(.up)
        guard raw.isFinite else { return maxSamplesPerSegment }
        return max(1, Int(min(raw, CGFloat(maxSamplesPerSegment))))
    }

    private static func interpolatesAngle(_ type: String) -> Bool {
        type == "rotate" || type == "skewX" || type == "skewY"
    }

    /// Splits an angular animation (`rotate`, `skewX`, `skewY`) into keyframes at most
    /// `maxAngleStep` degrees apart. Every value contributes its own angle and centre, which
    /// are interpolated component-wise as SMIL prescribes, honouring `keyTimes`.
    static func sampledTransformKeyframes(type: String, values: [String], keyTimes: [Double]?)
        -> (times: [Double], matrices: [CATransform3D])? {
        let parsed = values.map { parseNumbers($0) }
        guard parsed.count >= 2, parsed.allSatisfy({ !$0.isEmpty }) else { return nil }

        var segmentTimes = (0..<parsed.count).map { Double($0) / Double(parsed.count - 1) }
        if let keyTimes = keyTimes, keyTimes.count == parsed.count, keyTimes.first == 0, keyTimes.last == 1,
           zip(keyTimes, keyTimes.dropFirst()).allSatisfy({ $0 <= $1 }) {
            segmentTimes = keyTimes
        }

        func padded(_ numbers: [CGFloat]) -> [CGFloat] {
            numbers + [CGFloat](repeating: 0, count: max(0, 3 - numbers.count))
        }
        func matrix(_ n: [CGFloat]) -> CATransform3D {
            type == "rotate" ? rotateTransform(angle: n[0], center: CGPoint(x: n[1], y: n[2]))
                : skewTransform(type: type, angle: n[0])
        }

        var times = [segmentTimes[0]]
        var matrices = [matrix(padded(parsed[0]))]
        for i in 0..<(parsed.count - 1) {
            let from = padded(parsed[i]), to = padded(parsed[i + 1])
            let steps = sampleCount(from: from[0], to: to[0])
            for step in 1...steps {
                let f = CGFloat(step) / CGFloat(steps)
                let n = zip(from, to).map { $0 + ($1 - $0) * f }
                times.append(segmentTimes[i] + (segmentTimes[i + 1] - segmentTimes[i]) * Double(f))
                matrices.append(matrix(n))
            }
        }
        return (times, matrices)
    }

    private static func skewTransform(type: String, angle: CGFloat) -> CATransform3D {
        var transform = CATransform3DIdentity
        let shear = tan(angle * .pi / 180)
        if type == "skewX" { transform.m21 = shear } else { transform.m12 = shear }
        return transform
    }

    private func applySet(to layer: CALayer, pathLayer: CAShapeLayer?, value: String) {
        switch kind {
        case .opacity:
            if let f = Float(value) { layer.opacity = f }
        case .fill:
            pathLayer?.fillColor = SVGColors.getColor(string: value).cgColor
        case .stroke:
            pathLayer?.strokeColor = SVGColors.getColor(string: value).cgColor
        case .transform(let type):
            if let t = Self.transform(from: value, type: type) { layer.transform = t }
        }
    }

    private func anyValue(from string: String) -> Any {
        switch kind {
        case .opacity:
            return Float(string) ?? 0
        case .fill, .stroke:
            return SVGColors.getColor(string: string).cgColor
        case .transform(let type):
            return NSValue(caTransform3D: Self.transform(from: string, type: type) ?? CATransform3DIdentity)
        }
    }

    /// Numbers in an SMIL value list, separated by whitespace and/or commas (`0 12 12`
    /// and `0,12,12` are both valid) (B103).
    private static func parseNumbers(_ string: String) -> [CGFloat] {
        string
            .components(separatedBy: CharacterSet(charactersIn: ", \t\n\r"))
            .compactMap { Double($0) }
            .filter { $0.isFinite }
            .map { CGFloat($0) }
    }

    /// The matrix for a `rotate` of `angle` degrees about `center` (its own space).
    private static func rotateTransform(angle: CGFloat, center: CGPoint) -> CATransform3D {
        // The `CATransform3D*` helpers post-multiply, so the last call is applied to the
        // point first — building translate(center) · rotate · translate(-center).
        var transform = CATransform3DIdentity
        let hasCenter = center.x != 0 || center.y != 0
        if hasCenter {
            transform = CATransform3DTranslate(transform, center.x, center.y, 0)
        }
        transform = CATransform3DRotate(transform, angle * .pi / 180, 0, 0, 1)
        if hasCenter {
            transform = CATransform3DTranslate(transform, -center.x, -center.y, 0)
        }
        return transform
    }

    private static func transform(from string: String, type: String) -> CATransform3D? {
        let values = parseNumbers(string)
        switch type {
        case "rotate":
            guard let angle = values.first else { return nil }
            return rotateTransform(angle: angle, center: CGPoint(x: values.count > 1 ? values[1] : 0,
                                                                y: values.count > 2 ? values[2] : 0))
        case "translate":
            let tx = values.count > 0 ? values[0] : 0
            let ty = values.count > 1 ? values[1] : 0
            return CATransform3DMakeTranslation(tx, ty, 0)
        case "skewX", "skewY":
            guard let angle = values.first else { return nil }
            return skewTransform(type: type, angle: angle)
        case "scale":
            let sx = values.count > 0 ? values[0] : 1
            let sy = values.count > 1 ? values[1] : sx
            return CATransform3DMakeScale(sx, sy, 1)
        default:
            return nil
        }
    }
}
