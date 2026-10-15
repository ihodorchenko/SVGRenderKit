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

    /// Returns the MD5 digest of raw bytes (e.g. an SVG's `Data`), as a hexadecimal string.
    open class func md5(_ data: Data) -> String {
        return MD5([UInt8](data))
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

    /// Returns the vertices of a path (move/line/curve endpoints, including the
    /// closing point), in drawing order. Control points are omitted.
    open class func pathVertices(path: UIBezierPath) -> [CGPoint] {
        var vertices: [CGPoint] = []
        var subpathStart: CGPoint?
        path.cgPath.applyWithBlock { element in
            let pts = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint:
                vertices.append(pts[0])
                subpathStart = pts[0]
            case .addLineToPoint:
                vertices.append(pts[0])
            case .addQuadCurveToPoint:
                vertices.append(pts[1])
            case .addCurveToPoint:
                vertices.append(pts[2])
            case .closeSubpath:
                // Close on the *current* subpath's start, not the path's very first
                // vertex (a second subpath would otherwise close to the wrong point) (B107).
                if let start = subpathStart {
                    vertices.append(start)
                }
            default:
                break
            }
        }
        return vertices
    }

    /// The direction bisecting `incoming` and `outgoing` (both non-normalised). Falls
    /// back to `outgoing` when they cancel (a 180° turn). Used for `marker-mid` (B107).
    open class func bisector(_ incoming: CGPoint, _ outgoing: CGPoint) -> CGPoint {
        let a = normalized(incoming)
        let b = normalized(outgoing)
        let sum = CGPoint(x: a.x + b.x, y: a.y + b.y)
        if sum.x == 0, sum.y == 0 { return outgoing }
        return sum
    }

    private static func normalized(_ v: CGPoint) -> CGPoint {
        let length = (v.x * v.x + v.y * v.y).squareRoot()
        return length > 0 ? CGPoint(x: v.x / length, y: v.y / length) : .zero
    }
}
