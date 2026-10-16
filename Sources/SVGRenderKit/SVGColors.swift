import UIKit

internal extension String {
    func removeSpaces() -> String {
        return String(self.filter { !" \n\t\r".contains($0) })
    }
}

/// Converts SVG color strings (named, hex, `rgb`, `rgba`, and `argb`) into `UIColor` values.
public class SVGColors {

    /// Adds name-to-color-string overrides that take precedence when resolving colors.
    /// - parameter colors: A dictionary mapping color names to replacement color strings.
    public static func addOverrideColors(colors: [String: String]) {
        SVGConfiguration.shared.addColorOverrides(colors)
    }

    /// Misspelled former name of `addOverrideColors(colors:)`.
    @available(*, deprecated, renamed: "addOverrideColors(colors:)")
    public static func addOvverideColors(colors: [String: String]) {
        addOverrideColors(colors: colors)
    }

    /// Replaces all name-to-color-string overrides with the given dictionary.
    public static func setOverrideColors(colors: [String: String]) {
        SVGConfiguration.shared.setColorOverrides(colors)
    }

    /// Misspelled former name of `setOverrideColors(colors:)`.
    @available(*, deprecated, renamed: "setOverrideColors(colors:)")
    public static func setOvverideColors(colors: [String: String]) {
        setOverrideColors(colors: colors)
    }

    /// Adds name-to-`UIColor` overrides that take precedence when resolving colors.
    /// - parameter colors: A dictionary mapping color names to `UIColor` values.
    public static func addOverrideUIColors(colors: [String: UIColor]) {
        SVGConfiguration.shared.addUIColorOverrides(colors)
    }

    /// Misspelled former name of `addOverrideUIColors(colors:)`.
    @available(*, deprecated, renamed: "addOverrideUIColors(colors:)")
    public static func addOvverideUIColors(colors: [String: UIColor]) {
        addOverrideUIColors(colors: colors)
    }

    /// Replaces all name-to-`UIColor` overrides with the given dictionary.
    public static func setOverrideUIColors(colors: [String: UIColor]) {
        SVGConfiguration.shared.setUIColorOverrides(colors)
    }

    /// Misspelled former name of `setOverrideUIColors(colors:)`.
    @available(*, deprecated, renamed: "setOverrideUIColors(colors:)")
    public static func setOvverideUIColors(colors: [String: UIColor]) {
        setOverrideUIColors(colors: colors)
    }

    static private func getOverrideColor(byString: String) -> String? {
        return SVGConfiguration.shared.colorOverride(byString: byString)
    }

    static private func getOverrideUIColor(byString: String) -> UIColor? {
        return SVGConfiguration.shared.uiColorOverride(byString: byString)
    }

    /// Resolves a color string to a `UIColor`, applying any registered overrides.
    /// - parameter string: The color string to resolve (named, hex, `rgb`, `rgba`, or `argb`).
    /// - parameter alpha: An optional alpha value that overrides any alpha encoded in the string.
    /// - returns: The resolved color, or `UIColor.clear` if the string cannot be parsed.
    public class func getColor(string: String, alpha: CGFloat? = nil) -> UIColor {
        return parse(string: string, alpha: alpha) ?? UIColor.clear
    }

    /// Like `getColor(string:alpha:)`, but `nil` when the string is not a valid colour, so a
    /// caller can ignore the declaration instead of painting it transparent (B129).
    static func parse(string: String, alpha: CGFloat? = nil) -> UIColor? {
        var string: String = string
        if let color = getOverrideUIColor(byString: string) {
            return color
        }
        if let newString = getOverrideColor(byString: string) {
            string = newString
        }
        // CSS color keywords and functions are case-insensitive and tolerate surrounding whitespace.
        string = string.trimmed.lowercased()
        var color: UIColor?
        if string.hasPrefix("#") {
            color = getColor(hexString: string, alpha: alpha)
        } else if string.hasPrefix("hsla") {
            color = getColor(hslaString: string, alpha: alpha)
        } else if string.hasPrefix("hsl") {
            color = getColor(hslString: string, alpha: alpha)
        } else if string.hasPrefix("rgba") {
            color = getColor(rgbaString: string, alpha: alpha)
        } else if string.hasPrefix("argb") {
            color = getColor(argbString: string, alpha: alpha)
        } else if string.hasPrefix("rgb") {
            color = getColor(rgbString: string, alpha: alpha)
        } else if let colorHex = HTMLColors.colors[string] {
            color = getColor(hexString: colorHex, alpha: alpha)
        } else {
            if !string.isEmpty {
                SVGLog.addSLog(errorStr: "unknown color '\(string)'")
            }
            color = nil
        }
        return color
    }

    /// Parses an `rgb(r, g, b)` string into a `UIColor`.
    /// - parameter rgbString: An `rgb(r, g, b)` string to parse.
    /// - parameter alpha: An optional alpha value that overrides the default of `1.0`.
    /// - returns: The parsed color, or `nil` if the string is malformed.
    public class func getColor(rgbString: String, alpha: CGFloat? = nil) -> UIColor? {
        guard let body = functionBody(of: rgbString, name: "rgb") else { return nil }
        let parts = components(body)
        // CSS Color 4: `rgb(r g b)`, `rgb(r g b / a)` and the legacy `rgb(r, g, b, a)`.
        guard parts.count == 3 || parts.count == 4,
              let r = channel(parts[0]), let g = channel(parts[1]), let b = channel(parts[2]) else { return nil }
        var a: CGFloat = 1
        if parts.count == 4 {
            guard let parsed = alphaValue(parts[3]) else { return nil }
            a = parsed
        }
        return UIColor(red: r, green: g, blue: b, alpha: alpha.map(clamp01) ?? a)
    }

    /// Parses an `rgba(r, g, b, a)` string into a `UIColor`.
    /// - parameter _alpha: An optional alpha value that overrides the alpha encoded in the string.
    /// - returns: The parsed color, or `nil` if the string is malformed.
    public class func getColor(rgbaString: String, alpha _alpha: CGFloat? = nil) -> UIColor? {
        guard let body = functionBody(of: rgbaString, name: "rgba") else { return nil }
        let parts = components(body)
        guard parts.count == 3 || parts.count == 4,
              let r = channel(parts[0]), let g = channel(parts[1]), let b = channel(parts[2]) else { return nil }
        var a: CGFloat = 1
        if parts.count == 4 {
            guard let parsed = alphaValue(parts[3]) else { return nil }
            a = parsed
        }
        return UIColor(red: r, green: g, blue: b, alpha: _alpha.map(clamp01) ?? a)
    }

    /// Parses an `argb(a, r, g, b)` string into a `UIColor`.
    /// - parameter _alpha: An optional alpha value that overrides the alpha encoded in the string.
    /// - returns: The parsed color, or `nil` if the string is malformed.
    public class func getColor(argbString: String, alpha _alpha: CGFloat? = nil) -> UIColor? {
        guard let body = functionBody(of: argbString, name: "argb") else { return nil }
        let parts = components(body)
        guard parts.count == 4,
              let a = alphaValue(parts[0]),
              let r = channel(parts[1]), let g = channel(parts[2]), let b = channel(parts[3]) else { return nil }
        return UIColor(red: r, green: g, blue: b, alpha: _alpha.map(clamp01) ?? a)
    }

    /// The text inside `name( … )`, or `nil` when `string` is not that function.
    /// Whitespace between the name and the `(` is tolerated (`rgb (0, 0, 0)`).
    private static func functionBody(of string: String, name: String) -> String? {
        let trimmed = string.trimmed
        guard trimmed.count > name.count,
              String(trimmed.prefix(name.count)).lowercased() == name else { return nil }
        let rest = trimmed.dropFirst(name.count).drop(while: { $0 == " " || $0 == "\t" })
        guard rest.count > 1, rest.first == "(", rest.last == ")" else { return nil }
        return String(rest.dropFirst().dropLast())
    }

    /// The numeric arguments of a color function, split on commas and/or whitespace.
    private static func components(_ body: String) -> [Substring] {
        body.replacingOccurrences(of: ",", with: " ").replacingOccurrences(of: "/", with: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" })
    }

    /// A color channel: `0…255`, or a percentage (CSS Color 4), normalised to `0…1`.
    private static func channel(_ text: Substring) -> CGFloat? {
        if text.hasSuffix("%") {
            guard let value = Double(text.dropLast()) else { return nil }
            return clamp01(value / 100)
        }
        guard let value = Double(text) else { return nil }
        return clamp01(value / 255)
    }

    /// An alpha argument: `0…1`, or a percentage, clamped to `0…1`.
    private static func alphaValue(_ text: Substring) -> CGFloat? {
        if text.hasSuffix("%") {
            guard let value = Double(text.dropLast()) else { return nil }
            return clamp01(value / 100)
        }
        guard let value = Double(text) else { return nil }
        return CGFloat(min(max(value, 0), 1))
    }

    /// Parses an `hsl(h, s%, l%)` string into a `UIColor`.
    /// - parameter hslString: An `hsl(h, s%, l%)` string to parse.
    /// - parameter alpha: An optional alpha value that overrides the default of `1.0`.
    /// - returns: The parsed color, or `nil` if the string is malformed.
    public class func getColor(hslString: String, alpha: CGFloat? = nil) -> UIColor? {
        return hsl(hslString, name: "hsl", alpha: alpha)
    }

    /// Parses an `hsla(h, s%, l%, a)` string into a `UIColor`.
    /// - parameter _alpha: An optional alpha value that overrides the alpha encoded in the string.
    /// - returns: The parsed color, or `nil` if the string is malformed.
    public class func getColor(hslaString: String, alpha _alpha: CGFloat? = nil) -> UIColor? {
        return hsl(hslaString, name: "hsla", alpha: _alpha)
    }

    /// `hsl(h, s%, l%)`, `hsl(h s% l% / a)` and the `hsla` spelling of both (CSS Color 4).
    private static func hsl(_ string: String, name: String, alpha override: CGFloat?) -> UIColor? {
        guard let body = functionBody(of: string, name: name) else { return nil }
        let parts = components(body)
        guard parts.count == 3 || parts.count == 4,
              let h = parseHue(parts[0]), let s = parsePercent(parts[1]), let l = parsePercent(parts[2]) else { return nil }
        var a: CGFloat = 1
        if parts.count == 4 {
            guard let parsed = alphaValue(parts[3]) else { return nil }
            a = parsed
        }
        return color(h: h, s: s, l: l, alpha: (override ?? a).clamped01)
    }

    private static func clamp01(_ value: Double) -> CGFloat {
        guard value.isFinite else { return 0 }
        return CGFloat(min(max(value, 0), 1))
    }

    private static func clamp01(_ value: CGFloat) -> CGFloat {
        return value.clamped01
    }

    private static func parseHue(_ text: Substring) -> Double? {
        var str = String(text).trimmed
        if str.hasSuffix("deg") { str.removeLast(3) }
        return Double(str)
    }

    private static func parsePercent(_ text: Substring) -> Double? {
        var str = String(text).trimmed
        if str.hasSuffix("%") { str.removeLast() }
        guard let value = Double(str) else { return nil }
        return value / 100.0
    }

    private static func color(h: Double, s: Double, l: Double, alpha: CGFloat) -> UIColor {
        // Hue wraps modulo 360°; saturation and lightness are clamped to [0, 1].
        var hue = h.truncatingRemainder(dividingBy: 360) / 360.0
        if hue < 0 { hue += 1 }
        let (r, g, b) = hslToRGB(h: CGFloat(hue), s: clamp01(s), l: clamp01(l))
        return UIColor(red: r, green: g, blue: b, alpha: alpha.clamped01)
    }

    private static func hslToRGB(h: CGFloat, s: CGFloat, l: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
        if s == 0 {
            return (l, l, l)
        }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        let r = hueToRGB(p, q, h + 1.0 / 3.0)
        let g = hueToRGB(p, q, h)
        let b = hueToRGB(p, q, h - 1.0 / 3.0)
        return (r, g, b)
    }

    private static func hueToRGB(_ p: CGFloat, _ q: CGFloat, _ t: CGFloat) -> CGFloat {
        var t = t
        if t < 0 { t += 1 }
        if t > 1 { t -= 1 }
        if t < 1.0 / 6.0 { return p + (q - p) * 6.0 * t }
        if t < 1.0 / 2.0 { return q }
        if t < 2.0 / 3.0 { return p + (q - p) * (2.0 / 3.0 - t) * 6.0 }
        return p
    }

    /// Parses a hexadecimal color string (3, 4, 6, or 8 digits, with or without a leading `#`) into a `UIColor`.
    /// - parameter hexString: A hexadecimal color string to parse.
    /// - parameter alpha: An optional alpha value that overrides any alpha encoded in the string.
    /// - returns: The parsed color, or `nil` if the string is malformed.
    public class func getColor(hexString: String, alpha: CGFloat? = nil) -> UIColor? {
        var red:   CGFloat = 0.0
        var green: CGFloat = 0.0
        var blue:  CGFloat = 0.0
        var alphaHex: CGFloat = 1.0
        var hex:   String = hexString

        if hex.hasPrefix("#") {
            let index = hex.index(hex.startIndex, offsetBy: 1)
            hex = String(hex[index...])
        }

        let scanner = Scanner(string: hex)
        var hexValue: CUnsignedLongLong = 0
        if scanner.scanHexInt64(&hexValue) {
            switch (hex.count) {
            case 3:
                red   = CGFloat((hexValue & 0xF00) >> 8)       / 15.0
                green = CGFloat((hexValue & 0x0F0) >> 4)       / 15.0
                blue  = CGFloat(hexValue & 0x00F)              / 15.0
            case 4:
                red   = CGFloat((hexValue & 0xF000) >> 12)     / 15.0
                green = CGFloat((hexValue & 0x0F00) >> 8)      / 15.0
                blue  = CGFloat((hexValue & 0x00F0) >> 4)      / 15.0
                alphaHex = CGFloat(hexValue & 0x000F)             / 15.0
            case 6:
                red   = CGFloat((hexValue & 0xFF0000) >> 16)   / 255.0
                green = CGFloat((hexValue & 0x00FF00) >> 8)    / 255.0
                blue  = CGFloat(hexValue & 0x0000FF)           / 255.0
            case 8:
                red   = CGFloat((hexValue & 0xFF000000) >> 24) / 255.0
                green = CGFloat((hexValue & 0x00FF0000) >> 16) / 255.0
                blue  = CGFloat((hexValue & 0x0000FF00) >> 8)  / 255.0
                alphaHex = CGFloat(hexValue & 0x000000FF)       / 255.0
            default:
                SVGLog.addSLog(errorStr: "Invalid RGB string, number of characters after '#' should be either 3, 4, 6 or 8")
                return nil
            }
        } else {
            SVGLog.addSLog(errorStr: "Scan hex error")
            return nil
        }
        if let alpha = alpha {
            alphaHex = alpha
        }
        return UIColor(red:red, green:green, blue:blue, alpha:alphaHex)
    }
}

private extension CGFloat {
    var clamped01: CGFloat { isFinite ? Swift.min(Swift.max(self, 0), 1) : 0 }
}
