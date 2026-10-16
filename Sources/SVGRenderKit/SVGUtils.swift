import UIKit

/// Utility functions for string processing and hashing used throughout the library.
public class SVGUtils {

    /// Trims white space and new line characters, returns a new string.
    public class func trimmed(string: String) -> String {
        return string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Splits a string by a substring separator, omitting empty components.
    public class func split(string: String, separator: String) -> [String] {
        return string.components(separatedBy: separator).filter {
            !trimmed(string: $0).isEmpty
        }
    }

    /// Splits a string by the characters in a character set, omitting empty components.
    public class func split(string: String, separatorSet: CharacterSet) -> [String] {
        return string.components(separatedBy: separatorSet).filter {
            !trimmed(string: $0).isEmpty
        }
    }

    /// Computes the MD5 hash of the given string.
    /// - returns: The MD5 digest as a hexadecimal string.
    public class func md5(_ string: String) -> String {
        return md5Hex(string)
    }

    /// Returns the MD5 digest of raw bytes (e.g. an SVG's `Data`), as a hexadecimal string.
    public class func md5(_ data: Data) -> String {
        return md5Hex([UInt8](data))
    }

    /// Returns the end point and the tangent direction of the last segment of a path.
    public class func pathEndInfo(path: UIBezierPath) -> (point: CGPoint, tangent: CGPoint) {
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
    public class func pathVertices(path: UIBezierPath) -> [CGPoint] {
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

    /// A path vertex with the directions of the segments meeting there. `incoming` is the
    /// direction the previous segment arrives with, `outgoing` the one the next leaves with — for
    /// a curve its end tangent (from the control point), not the chord. `nil` where no segment
    /// arrives or leaves (the start of a subpath, its last vertex).
    struct MarkerVertex {
        var point: CGPoint
        var incoming: CGPoint?
        var outgoing: CGPoint?
    }

    /// The vertices of a path with their tangents, in drawing order; every subpath contributes its
    /// own start and end, so a joint between two subpaths is two vertices (B133 в).
    class func markerVertices(path: UIBezierPath) -> [MarkerVertex] {
        var vertices: [MarkerVertex] = []
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero

        // Direction from `from` towards the first of the points that differs from it.
        func direction(from: CGPoint, towards candidates: [CGPoint]) -> CGPoint {
            for c in candidates where c != from { return CGPoint(x: c.x - from.x, y: c.y - from.y) }
            return .zero
        }
        // Direction arriving at `to` from the first of the points that differs from it.
        func direction(to: CGPoint, from candidates: [CGPoint]) -> CGPoint {
            for c in candidates where c != to { return CGPoint(x: to.x - c.x, y: to.y - c.y) }
            return .zero
        }
        func segment(startTangent: CGPoint, endTangent: CGPoint, end: CGPoint) {
            vertices[vertices.count - 1].outgoing = startTangent
            vertices.append(MarkerVertex(point: end, incoming: endTangent, outgoing: nil))
            current = end
        }

        path.cgPath.applyWithBlock { element in
            let pts = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint:
                vertices.append(MarkerVertex(point: pts[0], incoming: nil, outgoing: nil))
                current = pts[0]
                subpathStart = pts[0]
            case .addLineToPoint:
                guard !vertices.isEmpty else { break }
                let d = CGPoint(x: pts[0].x - current.x, y: pts[0].y - current.y)
                segment(startTangent: d, endTangent: d, end: pts[0])
            case .addQuadCurveToPoint:
                guard !vertices.isEmpty else { break }
                let end = pts[1]
                segment(startTangent: direction(from: current, towards: [pts[0], end]),
                        endTangent: direction(to: end, from: [pts[0], current]),
                        end: end)
            case .addCurveToPoint:
                guard !vertices.isEmpty else { break }
                // A control point coinciding with an end falls back to the next one (SVG 1.1 §11.6.2).
                let end = pts[2]
                segment(startTangent: direction(from: current, towards: [pts[0], pts[1], end]),
                        endTangent: direction(to: end, from: [pts[1], pts[0], current]),
                        end: end)
            case .closeSubpath:
                guard !vertices.isEmpty else { break }
                let d = CGPoint(x: subpathStart.x - current.x, y: subpathStart.y - current.y)
                segment(startTangent: d, endTangent: d, end: subpathStart)
            default:
                break
            }
        }
        return vertices
    }

    /// The direction bisecting `incoming` and `outgoing` (both non-normalised). Falls
    /// back to `outgoing` when they cancel (a 180° turn). Used for `marker-mid` (B107).
    public class func bisector(_ incoming: CGPoint, _ outgoing: CGPoint) -> CGPoint {
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
