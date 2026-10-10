import UIKit
import QuartzCore

/// A parsed SMIL animation element (`animate` or `animateTransform`), minimal subset.
struct SVGAnimation {
    enum Kind {
        case opacity
        case fill
        case stroke
        case transform(type: String)
    }

    var kind: Kind
    var from: String
    var to: String
    var duration: TimeInterval

    /// Parses `<animate>` and `<animateTransform>` children into animations.
    static func parse(children: [XMLElement]) -> [SVGAnimation] {
        var result: [SVGAnimation] = []
        for child in children {
            let name = child.name
            let attrs = child.attributesDict()
            guard name == "animate" || name == "animateTransform",
                  let attributeName = attrs["attributeName"],
                  let from = attrs["from"],
                  let to = attrs["to"],
                  let durStr = attrs["dur"],
                  let duration = parseDuration(durStr) else {
                continue
            }

            let kind: Kind
            if name == "animateTransform" {
                kind = .transform(type: attrs["type"] ?? "translate")
            } else {
                switch attributeName {
                case "opacity":
                    kind = .opacity
                case "fill":
                    kind = .fill
                case "stroke":
                    kind = .stroke
                default:
                    continue
                }
            }
            result.append(SVGAnimation(kind: kind, from: from, to: to, duration: duration))
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
        switch kind {
        case .opacity:
            guard let from = Float(from), let to = Float(to) else { return }
            let anim = CABasicAnimation(keyPath: "opacity")
            anim.fromValue = from
            anim.toValue = to
            anim.duration = duration
            layer.add(anim, forKey: "opacity")

        case .fill:
            let anim = CABasicAnimation(keyPath: "fillColor")
            anim.fromValue = SVGColors.getColor(string: from).cgColor
            anim.toValue = SVGColors.getColor(string: to).cgColor
            anim.duration = duration
            pathLayer?.add(anim, forKey: "fillColor")

        case .stroke:
            let anim = CABasicAnimation(keyPath: "strokeColor")
            anim.fromValue = SVGColors.getColor(string: from).cgColor
            anim.toValue = SVGColors.getColor(string: to).cgColor
            anim.duration = duration
            pathLayer?.add(anim, forKey: "strokeColor")

        case .transform(let type):
            guard let from = Self.transform(from: from, type: type),
                  let to = Self.transform(from: to, type: type) else { return }
            let anim = CABasicAnimation(keyPath: "transform")
            anim.fromValue = NSValue(caTransform3D: from)
            anim.toValue = NSValue(caTransform3D: to)
            anim.duration = duration
            layer.add(anim, forKey: "transform")
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
