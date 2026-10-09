import Foundation

///from https://github.com/fontello/svgpath
///Перевод ellipse arc в набор кривых
class EllipseArcToCurves {
    let pi2: Scalar = Scalar.pi * 2

    func a2c(
        startPoint: Vector2, endPoint: Vector2, rx: Scalar, ry: Scalar,
        largeArcFlag: Bool, sweepFlag: Bool, phi: Scalar) -> [UnitArc]
    {
        var rx = rx
        var ry = ry
        let x1: Scalar = startPoint.x
        let y1: Scalar = startPoint.y
        let x2: Scalar = endPoint.x
        let y2: Scalar = endPoint.y
        let fa = largeArcFlag
        let fs = sweepFlag

        let sin_phi = sin(phi * self.pi2 / 360)
        let cos_phi = cos(phi * self.pi2 / 360)

        // Make sure radii are valid
        let x1p =  cos_phi*(x1 - x2)/2 + sin_phi*(y1 - y2)/2
        let y1p = -sin_phi*(x1 - x2)/2 + cos_phi*(y1 - y2)/2

        if (x1p == 0 && y1p == 0) {
            // we're asked to draw line to itself
            return [];
        }

        if (rx == 0 || ry == 0) {
            // one of the radii is zero
            return [];
        }

        // Compensate out-of-range radii
        rx = abs(rx);
        ry = abs(ry);

        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry);
        if (lambda > 1) {
            rx *= sqrt(lambda);
            ry *= sqrt(lambda);
        }

        // Get center parameters (cx, cy, theta1, delta_theta)
        let cc = self.getArcCenter(
            x1: x1, y1: y1, x2: x2, y2: y2, fa: fa, fs: fs, rx: rx,
            ry: ry, sin_phi: sin_phi, cos_phi: cos_phi)

        var result: [UnitArc] = [];
        var theta1 = cc.theta1;
        var delta_theta = cc.delta_theta;

        // Split an arc to multiple segments, so each segment
        // will be less than τ/4 (= 90°)
        //
        let segments: Int = Int(max(ceil(abs(delta_theta) / (self.pi2 / 4)), 1))
        delta_theta /= Scalar(segments)

        for _ in 0..<segments {
            result.append(self.approximateUnitArc(theta1: theta1, delta_theta: delta_theta))
            theta1 += delta_theta
        }

        func transformBack(point: Vector2) -> Vector2 {
            var x = point.x
            var y = point.y
            // scale
            x *= rx
            y *= ry
            // rotate
            let xp = cos_phi*x - sin_phi*y
            let yp = sin_phi*x + cos_phi*y

            // translate
            return Vector2(xp + cc.cx, yp + cc.cy)
        }

        return result.map { (unit) in
            let res = UnitArc(
                p1: transformBack(point: unit.p1), p1a: transformBack(point: unit.p1a),
                p2a: transformBack(point: unit.p2a), p2: transformBack(point: unit.p2))
            return res
        }
    }

    func getArcCenter(
        x1: Scalar, y1: Scalar, x2: Scalar, y2: Scalar, fa: Bool, fs: Bool,
        rx: Scalar, ry: Scalar, sin_phi: Scalar, cos_phi: Scalar) -> (cx: Scalar, cy: Scalar, theta1: Scalar, delta_theta: Scalar)
    {
        let x1p: Scalar =  cos_phi*(x1-x2)/2 + sin_phi*(y1-y2)/2
        let y1p: Scalar = -sin_phi*(x1-x2)/2 + cos_phi*(y1-y2)/2

        let rx_sq: Scalar  =  rx * rx
        let ry_sq: Scalar  =  ry * ry
        let x1p_sq: Scalar = x1p * x1p
        let y1p_sq: Scalar = y1p * y1p

        // Step 2.
        //
        // Compute coordinates of the centre of this ellipse (cx', cy')
        // in the new coordinate system.
        //
        var radicant = (rx_sq * ry_sq) - (rx_sq * y1p_sq) - (ry_sq * x1p_sq)

        if (radicant < 0) {
            // due to rounding errors it might be e.g. -1.3877787807814457e-17
            radicant = 0
        }

        radicant /=   (rx_sq * y1p_sq) + (ry_sq * x1p_sq)
        radicant = sqrt(radicant) * (fa == fs ? -1 : 1)

        let cxp = radicant *  rx/ry * y1p
        let cyp = radicant * -ry/rx * x1p

        // Step 3.
        //
        // Transform back to get centre coordinates (cx, cy) in the original
        // coordinate system.
        //
        let cx = cos_phi * cxp - sin_phi * cyp + (x1 + x2) / 2
        let cy = sin_phi * cxp + cos_phi * cyp + (y1 + y2) / 2

        // Step 4.
        //
        // Compute angles (theta1, delta_theta).
        //
        let v1x =  (x1p - cxp) / rx;
        let v1y =  (y1p - cyp) / ry;
        let v2x = (-x1p - cxp) / rx;
        let v2y = (-y1p - cyp) / ry;

        let theta1: Scalar = self.unit_vector_angle(ux: 1, uy: 0, vx: v1x, vy: v1y)
        var delta_theta: Scalar = self.unit_vector_angle(ux: v1x, uy: v1y, vx: v2x, vy: v2y)

        if (fs == false && delta_theta > 0) {
            delta_theta -= self.pi2
        }
        if (fs == true && delta_theta < 0) {
            delta_theta += self.pi2
        }
        return (cx: cx, cy: cy, theta1: theta1, delta_theta: delta_theta)
    }

    func approximateUnitArc(theta1: Scalar, delta_theta: Scalar)
    -> UnitArc
    {
        let alpha = 4/3 * tan(delta_theta/4)

        let x1 = cos(theta1)
        let y1 = sin(theta1)
        let x2 = cos(theta1 + delta_theta)
        let y2 = sin(theta1 + delta_theta)
        return UnitArc(
            p1: Vector2(x1, y1),
            p1a: Vector2(x1 - y1 * alpha, y1 + x1 * alpha),
            p2a: Vector2(x2 + y2 * alpha, y2 - x2 * alpha),
            p2: Vector2(x2, y2))
    }

    // Calculate an angle between two unit vectors
    //
    // Since we measure angle between radii of circular arcs,
    // we can use simplified math (without length normalization)
    func unit_vector_angle(ux: Scalar, uy: Scalar, vx: Scalar, vy: Scalar) -> Scalar {
        let sign: Scalar = (ux * vy - uy * vx < 0) ? -1 : 1;
        var dot: Scalar  = ux * vx + uy * vy;

        // Add this to work with arbitrary vectors:
        // dot /= Math.sqrt(ux * ux + uy * uy) * Math.sqrt(vx * vx + vy * vy);

        // rounding errors, e.g. -1.0000000000000002 can screw up this
        if (dot >  1.0) { dot =  1.0; }
        if (dot < -1.0) { dot = -1.0; }

        return sign * acos(dot);
    }
}

extension EllipseArcToCurves {
    struct UnitArc {
        var p1: Vector2
        var p1a: Vector2
        var p2a: Vector2
        var p2: Vector2
    }
}
