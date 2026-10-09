import Foundation
import CoreGraphics

/// The scalar type used for vector components.
public typealias Scalar = Double

/// A 2D vector with x and y components, used for vector math.
public struct Vector2: Hashable {
    /// The horizontal component of the vector.
    public var x: Scalar
    /// The vertical component of the vector.
    public var y: Scalar
}

extension Vector2: CustomStringConvertible {
    /// A string representation of the vector.
    public var description: String {
        return "(x:\(self.x); y:\(self.y))"
    }
}

public extension Vector2 {
    /// The vector converted to a Core Graphics point.
    var point: CGPoint {
        return CGPoint(x: x, y: y)
    }
}

public extension Vector2 {
    /// The zero vector (0, 0).
    static let zero = Vector2(0, 0)
    /// The unit vector along the x axis (1, 0).
    static let x = Vector2(1, 0)
    /// The unit vector along the y axis (0, 1).
    static let y = Vector2(0, 1)

    /// The squared length (magnitude) of the vector.
    var lengthSquared: Scalar {
        return x * x + y * y
    }

    /// The length (magnitude) of the vector.
    var length: Scalar {
        return sqrt(lengthSquared)
    }

    /// The vector negated component-wise.
    var inverse: Vector2 {
        return -self
    }

    /// Creates a vector from the given x and y components.
    init(_ x: Scalar, _ y: Scalar) {
        self.init(x: x, y: y)
    }

    /// Creates a vector from an array of two scalar components.
    init(_ v: [Scalar]) {
        assert(v.count == 2, "array must contain 2 elements, contained \(v.count)")
        self.init(v[0], v[1])
    }

    /// Returns the vector's components as a two-element array.
    func toArray() -> [Scalar] {
        return [x, y]
    }

    /// Returns the dot product of this vector and another vector.
    func dot(_ v: Vector2) -> Scalar {
        return x * v.x + y * v.y
    }

    /// Returns the 2D cross product (z component) of this vector and another vector.
    func cross(_ v: Vector2) -> Scalar {
        return x * v.y - y * v.x
    }

    /// Returns the vector scaled to unit length, or the vector unchanged if it is zero or already unit length.
    func normalized() -> Vector2 {
        let lengthSquared = self.lengthSquared
        if lengthSquared ~= 0 || lengthSquared ~= 1 {
            return self
        }
        return self / sqrt(lengthSquared)
    }

    /// Returns the vector rotated by the given angle in radians.
    func rotated(by radians: Scalar) -> Vector2 {
        let cs = cos(radians)
        let sn = sin(radians)
        return Vector2(x * cs - y * sn, x * sn + y * cs)
    }

    /// Returns the vector rotated by the given angle in radians around a pivot point.
    func rotated(by radians: Scalar, around pivot: Vector2) -> Vector2 {
        return (self - pivot).rotated(by: radians) + pivot
    }

    /// Returns the angle in radians between this vector and another vector.
    func angle(with v: Vector2) -> Scalar {
        if self == v {
            return 0
        }

        let t1 = normalized()
        let t2 = v.normalized()
        let cross = t1.cross(t2)
        let dot = max(-1, min(1, t1.dot(t2)))

        return atan2(cross, dot)
    }

    /// Returns the vector linearly interpolated toward another vector by the given amount.
    func interpolated(with v: Vector2, by t: Scalar) -> Vector2 {
        return self + (v - self) * t
    }

    /// Returns the negation of the vector.
    static prefix func - (v: Vector2) -> Vector2 {
        return Vector2(-v.x, -v.y)
    }

    /// Returns the component-wise sum of two vectors.
    static func + (lhs: Vector2, rhs: Vector2) -> Vector2 {
        return Vector2(lhs.x + rhs.x, lhs.y + rhs.y)
    }

    /// Returns the component-wise difference of two vectors.
    static func - (lhs: Vector2, rhs: Vector2) -> Vector2 {
        return Vector2(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    /// Adds a scalar to each component of the vector.
    static func + (lhs: Vector2, rhs: Scalar) -> Vector2 {
        return Vector2(lhs.x + rhs, lhs.y + rhs)
    }

    /// Subtracts a scalar from each component of the vector.
    static func - (lhs: Vector2, rhs: Scalar) -> Vector2 {
        return Vector2(lhs.x - rhs, lhs.y - rhs)
    }

    /// Returns the component-wise product of two vectors.
    static func * (lhs: Vector2, rhs: Vector2) -> Vector2 {
        return Vector2(lhs.x * rhs.x, lhs.y * rhs.y)
    }

    /// Multiplies each component of the vector by a scalar.
    static func * (lhs: Vector2, rhs: Scalar) -> Vector2 {
        return Vector2(lhs.x * rhs, lhs.y * rhs)
    }

    /// Returns the component-wise quotient of two vectors.
    static func / (lhs: Vector2, rhs: Vector2) -> Vector2 {
        return Vector2(lhs.x / rhs.x, lhs.y / rhs.y)
    }

    /// Divides each component of the vector by a scalar.
    static func / (lhs: Vector2, rhs: Scalar) -> Vector2 {
        return Vector2(lhs.x / rhs, lhs.y / rhs)
    }

    /// Returns whether two vectors are approximately equal.
    static func ~= (lhs: Vector2, rhs: Vector2) -> Bool {
        return lhs.x ~= rhs.x && lhs.y ~= rhs.y
    }
}

extension CGPoint {
    var vector: Vector2 {
        return Vector2(Double(self.x), Double(self.y))
    }
}
