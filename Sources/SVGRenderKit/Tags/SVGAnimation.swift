import UIKit
import QuartzCore

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

    /// Adds the animation to the appropriate layer.
    func apply(to layer: CALayer, pathLayer: CAShapeLayer?) {
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
        if values.count == 2 {
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
        animation.beginTime = begin
        targetLayer.add(animation, forKey: keyPath)
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

    private static func transform(from string: String, type: String) -> CATransform3D? {
        let values = string.split(separator: " ").compactMap { Double($0) }
        switch type {
        case "rotate":
            guard let angle = values.first else { return nil }
            return CATransform3DMakeRotation(CGFloat(angle * .pi / 180), 0, 0, 1)
        case "translate":
            let tx = values.count > 0 ? CGFloat(values[0]) : 0
            let ty = values.count > 1 ? CGFloat(values[1]) : 0
            return CATransform3DMakeTranslation(tx, ty, 0)
        case "scale":
            let sx = values.count > 0 ? CGFloat(values[0]) : 1
            let sy = values.count > 1 ? CGFloat(values[1]) : sx
            return CATransform3DMakeScale(sx, sy, 1)
        default:
            return nil
        }
    }
}
