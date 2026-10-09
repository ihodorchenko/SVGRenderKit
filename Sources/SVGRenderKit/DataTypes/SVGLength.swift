import UIKit

/// A length value expressed in pixels or as a percentage.
public enum SVGLength {
    /// A length in pixels.
    case px(value: CGFloat)
    ///0...1
    case percent(value: CGFloat)

    internal static func get(string: String) throws -> SVGLength {
        var string = string.trimmed
        if string.hasSuffix("px") {
            string.removeLast(2)
            string = string.trimmed
            if let f = Float(string) {
                return SVGLength.px(value: CGFloat(f))
            } else {
                throw SVGError.parseError(text: "can't parse string to float: \(string)")
            }
        } else if string.hasSuffix("%") {
            string.removeLast(1)
            string = string.trimmed
            if let f = Float(string) {
                return SVGLength.percent(value: CGFloat(f/100.0))
            } else {
                throw SVGError.parseError(text: "can't parse string to float: \(string)")
            }
        } else {
            if let f = Float(string) {
                return SVGLength.px(value: CGFloat(f))
            } else {
                throw SVGError.parseError(text: "length format not supported: \(string)")
            }
        }
    }
}
