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
    public static func addOvverideColors(colors: [String: String]) {
        SVGConfiguration.shared.addColorOverrides(colors)
    }

    /// Replaces all name-to-color-string overrides with the given dictionary.
    public static func setOvverideColors(colors: [String: String]) {
        SVGConfiguration.shared.setColorOverrides(colors)
    }

    /// Adds name-to-`UIColor` overrides that take precedence when resolving colors.
    /// - parameter colors: A dictionary mapping color names to `UIColor` values.
    public static func addOvverideUIColors(colors: [String: UIColor]) {
        SVGConfiguration.shared.addUIColorOverrides(colors)
    }

    /// Replaces all name-to-`UIColor` overrides with the given dictionary.
    public static func setOvverideUIColors(colors: [String: UIColor]) {
        SVGConfiguration.shared.setUIColorOverrides(colors)
    }

    static private func getOvverideColor(byString: String) -> String? {
        return SVGConfiguration.shared.colorOverride(byString: byString)
    }

    static private func getOvverideUIColor(byString: String) -> UIColor? {
        return SVGConfiguration.shared.uiColorOverride(byString: byString)
    }

    /// Resolves a color string to a `UIColor`, applying any registered overrides.
    /// - parameter alpha: An optional alpha value that overrides any alpha encoded in the string.
    /// - returns: The resolved color, or `UIColor.clear` if the string cannot be parsed.
    public class func getColor(string: String, alpha: CGFloat? = nil) -> UIColor {
        var string: String = string
        if let color = getOvverideUIColor(byString: string) {
            return color
        }
        if let newString = getOvverideColor(byString: string) {
            string = newString
        }
        var color: UIColor?
        if string.hasPrefix("#") {
            color = getColor(hexString: string, alpha: alpha)
        } else if string.hasPrefix("rgba") {
            color = getColor(rgbaString: string, alpha: alpha)
        } else if string.hasPrefix("argb") {
            color = getColor(argbString: string, alpha: alpha)
        } else if string.hasPrefix("rgb") {
            color = getColor(rgbString: string, alpha: alpha)
        } else if let colorHex = HTMLColors.colors[string] {
            color = getColor(hexString: colorHex, alpha: alpha)
        } else {
            color = nil
        }
        if let color = color {
            return color
        } else {
            return UIColor.clear
        }
    }

    /// Parses an `rgb(r, g, b)` string into a `UIColor`.
    /// - parameter alpha: An optional alpha value that overrides the default of `1.0`.
    /// - returns: The parsed color, or `nil` if the string is malformed.
    public class func getColor(rgbString: String, alpha: CGFloat? = nil) -> UIColor? {


        var _rgbString = rgbString.removeSpaces()
        _rgbString.removeFirst("rgb(".count)
        _rgbString.removeLast()
        let arr = _rgbString.split(separator: ",")
        if arr.count == 3 {
            if let _red = Double(arr[0]), let _green = Double(arr[1]), let _blue = Double(arr[2]) {
                return UIColor(red: CGFloat(_red/255.0), green: CGFloat(_green/255.0), blue: CGFloat(_blue/255.0), alpha: alpha ?? 1)
            }
        }
        return nil

    }

    /// Parses an `rgba(r, g, b, a)` string into a `UIColor`.
    /// - parameter _alpha: An optional alpha value that overrides the alpha encoded in the string.
    /// - returns: The parsed color, or `nil` if the string is malformed.
    public class func getColor(rgbaString: String, alpha _alpha: CGFloat? = nil) -> UIColor? {


        var _rgbString = rgbaString.removeSpaces()
        _rgbString.removeFirst("rgba(".count)
        _rgbString.removeLast()
        let arr = _rgbString.split(separator: ",")
        if arr.count == 4 {
            if let red = Double(arr[0]), let green = Double(arr[1]), let blue = Double(arr[2]), let alpha = Double(arr[3]) {
                return UIColor(red: CGFloat(red/255.0), green: CGFloat(green/255.0), blue: CGFloat(blue/255.0), alpha: _alpha ?? CGFloat(alpha))
            }
        }
        return nil


    }

    /// Parses an `argb(a, r, g, b)` string into a `UIColor`.
    /// - parameter _alpha: An optional alpha value that overrides the alpha encoded in the string.
    /// - returns: The parsed color, or `nil` if the string is malformed.
    public class func getColor(argbString: String, alpha _alpha: CGFloat? = nil) -> UIColor? {
        var _rgbString = argbString.removeSpaces()
        _rgbString.removeFirst("argb(".count)
        _rgbString.removeLast()
        let arr = _rgbString.split(separator: ",")
        if arr.count == 4 {
            if let alpha = Double(arr[0]), let red = Double(arr[1]), let green = Double(arr[2]), let blue = Double(arr[3]) {
                return UIColor(red: CGFloat(red/255.0), green: CGFloat(green/255.0), blue: CGFloat(blue/255.0), alpha: _alpha ?? CGFloat(alpha))
            }
        }
        return nil

    }

    /// Parses a hexadecimal color string (3, 4, 6, or 8 digits, with or without a leading `#`) into a `UIColor`.
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
                alphaHex = CGFloat((hexValue & 0xFF000000) >> 24) / 255.0
                red   = CGFloat((hexValue & 0x00FF0000) >> 16) / 255.0
                green = CGFloat((hexValue & 0x0000FF00) >> 8)  / 255.0
                blue  = CGFloat(hexValue & 0x000000FF)         / 255.0
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
