import UIKit

/// Utility functions for string processing and hashing used throughout the library.
open class SVGUtils {

    /// Trims white space and new line characters, returns a new string.
    open class func trimmed(string: String) -> String {
        return string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Splits a string by a substring separator, omitting empty components.
    open class func split(string: String, separator: String) -> [String] {
        return string.components(separatedBy: separator).filter {
            !trimmed(string: $0).isEmpty
        }
    }

    /// Splits a string by the characters in a character set, omitting empty components.
    open class func split(string: String, separatorSet: CharacterSet) -> [String] {
        return string.components(separatedBy: separatorSet).filter {
            !trimmed(string: $0).isEmpty
        }
    }

    /// Computes the MD5 hash of the given string.
    /// - returns: The MD5 digest as a hexadecimal string.
    open class func md5(_ string: String) -> String {
        return MD5(string)
    }

    /// Returns the end point and the tangent direction of the last segment of a path.
    open class func pathEndInfo(path: UIBezierPath) -> (point: CGPoint, tangent: CGPoint) {
        var last = CGPoint.zero
        var prev = CGPoint.zero
        var first = CGPoint.zero
        path.cgPath.applyWithBlock { element in
            let pts = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint:
                prev = pts[0]
                last = pts[0]
                first = pts[0]
            case .addLineToPoint:
                prev = last
                last = pts[0]
            case .addQuadCurveToPoint:
                // Tangent at the end of a quadratic is end - control.
                prev = pts[0]
                last = pts[1]
            case .addCurveToPoint:
                // Tangent at the end of a cubic is end - controlPoint2.
                prev = pts[1]
                last = pts[2]
            case .closeSubpath:
                prev = last
                last = first
            default:
                break
            }
        }
        return (last, CGPoint(x: last.x - prev.x, y: last.y - prev.y))
    }
}
