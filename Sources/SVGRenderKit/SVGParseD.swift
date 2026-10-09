import Foundation
import UIKit

/////////////////////////////////////////////////////
//
// MARK: Command Implementations

internal class MoveTo: PathCommand {

    override var numberOfRequiredParameters: Int {
        get {
            return 2
        }
    }

    override func execute(forPath: UIBezierPath, previousCommand: PathCommand? = nil) -> SVGError? {
        guard self.parameters.count > 0 && self.parameters.count % self.numberOfRequiredParameters == 0 else {
            return SVGError.parseError(text: "MoveTo: parameters.count (\(parameters.count) % \(numberOfRequiredParameters)) == \(self.parameters.count % self.numberOfRequiredParameters)")
        }

        let groups = self.getGroups()

        let point = self.pointForPathType(CGPoint(x: groups[0][0], y: groups[0][1]))
        forPath.move(to: point)
        for index in 1..<groups.count {
            let group = groups[index]
            let point = self.pointForPathType(CGPoint(x: group[0], y: group[1]), currentPoint: forPath.currentPoint)
            forPath.addLine(to: point)
        }
        return nil
    }
}

internal class ClosePath: PathCommand {
    var firstCommand: PathCommand?

    override var numberOfRequiredParameters: Int {
        get {
            return 0
        }
    }

    override func execute(forPath: UIBezierPath, previousCommand: PathCommand? = nil) -> SVGError? {


        forPath.close()
        return nil
    }
}

internal class LineTo: PathCommand {

    override var numberOfRequiredParameters: Int {
        get {
            return 2
        }
    }

    override func execute(forPath: UIBezierPath, previousCommand: PathCommand? = nil) -> SVGError? {
        guard self.parameters.count > 0 && self.parameters.count % self.numberOfRequiredParameters == 0 else {
            return SVGError.parseError(text: "LineTo: parameters.count (\(parameters.count) != \(numberOfRequiredParameters))")
        }
        let groups = self.getGroups()
        groups.forEach { (group) in
            let point = self.pointForPathType(CGPoint(x: group[0], y: group[1]))
            forPath.addLine(to: point)
        }
        return nil
    }
}

internal class HorizontalLineTo: PathCommand {

    override var numberOfRequiredParameters: Int {
        get {
            return 1
        }
    }

    override func execute(forPath: UIBezierPath, previousCommand: PathCommand? = nil) -> SVGError? {
        if numberOfRequiredParameters != parameters.count {
            return SVGError.parseError(text: "HorizontalLineTo: parameters.count (\(parameters.count) != \(numberOfRequiredParameters))")
        }

        let x = self.parameters[0]
        let point: CGPoint
        if self.pathType == PathType.absolute {
            point = CGPoint(x: x, y: forPath.currentPoint.y)
        } else {
            point = CGPoint(x: forPath.currentPoint.x + x, y: forPath.currentPoint.y)
        }

        forPath.addLine(to: point)
        return nil
    }
}

internal class VerticalLineTo: PathCommand {

    override var numberOfRequiredParameters: Int {
        get {
            return 1
        }
    }

    override func execute(forPath: UIBezierPath, previousCommand: PathCommand? = nil) -> SVGError? {
        if numberOfRequiredParameters != parameters.count {
            return SVGError.parseError(text: "VerticalLineTo: parameters.count (\(parameters.count) != (numberOfRequiredParameters))")
        }
        let y = self.parameters[0]
        let point: CGPoint
        if self.pathType == PathType.absolute {
            point = CGPoint(x: forPath.currentPoint.x, y: y)
        } else {
            point = CGPoint(x: forPath.currentPoint.x, y: forPath.currentPoint.y + y)
        }

        forPath.addLine(to: point)
        return nil
    }
}

/// взято с SVGKit
internal class EllipticalArcTo: PathCommand {
    struct BezierCurve {
        var toPoint: CGPoint
        var p1: CGPoint
        var p2: CGPoint
    }

    override var numberOfRequiredParameters: Int {
        get {
            return 7
        }
    }

    let ellipseArcToCurves: EllipseArcToCurves = EllipseArcToCurves()

    override func execute(forPath: UIBezierPath, previousCommand: PathCommand? = nil) -> SVGError? {
        guard self.parameters.count > 0 && self.parameters.count % self.numberOfRequiredParameters == 0 else {
            return SVGError.parseError(text: "EllipticalArcTo: parameters.count (\(parameters.count) != (numberOfRequiredParameters))")
        }
        let groups = self.getGroups()
        var error: SVGError?
        groups.forEach { (group) in
            if let e = self.execute_v3(forPath: forPath, parameters: group, previousCommand: previousCommand) {
                error = e
                return
            }
        }
        return error
    }

    fileprivate func execute_v3(forPath: UIBezierPath, parameters: [CGFloat], previousCommand: PathCommand? = nil) -> SVGError? {
        let startPoint: CGPoint = forPath.currentPoint
        let x1: CGFloat = startPoint.x
        let y1: CGFloat = startPoint.y
        let endPoint: CGPoint
        if self.pathType == PathType.absolute {
            endPoint = CGPoint(x: parameters[5], y: parameters[6])
        } else {
            endPoint = CGPoint(x: x1 + parameters[5], y: y1 + parameters[6])
        }
        let xAngle: Scalar = Scalar(parameters[2])
        let largeArcFlag: Bool = Int(parameters[3]) == 1
        let sweepFlag: Bool = Int(parameters[4]) == 1
        let rx: Scalar = Scalar(parameters[0])
        let ry: Scalar = Scalar(parameters[1])

        let curves = self.ellipseArcToCurves.a2c(
            startPoint: startPoint.vector, endPoint: endPoint.vector,
            rx: rx, ry: ry, largeArcFlag: largeArcFlag, sweepFlag: sweepFlag, phi: xAngle)

        if curves.count == 0 {
            return SVGError.content(text: "can't get curves array from ellipse arc")
        }

        curves.forEach { (curve) in
            forPath.addCurve(to: curve.p2.point, controlPoint1: curve.p1a.point, controlPoint2: curve.p2a.point)
        }
        return nil
    }
}

internal class CurveTo: PathCommand {

    override var numberOfRequiredParameters: Int {
        get {
            return 6
        }
    }

    override func execute(forPath: UIBezierPath, previousCommand: PathCommand? = nil) -> SVGError? {
        let count: Int = self.parameters.count / self.numberOfRequiredParameters
        for index in 0..<count {
            let i = index * self.numberOfRequiredParameters
            let startControl = self.pointForPathType(CGPoint(x: self.parameters[i + 0], y: self.parameters[i + 1]))
            let endControl = self.pointForPathType(CGPoint(x: self.parameters[i + 2], y: self.parameters[i + 3]))
            let point = self.pointForPathType(CGPoint(x: self.parameters[i + 4], y: self.parameters[i + 5]))
            forPath.addCurve(to: point, controlPoint1: startControl, controlPoint2: endControl)
        }
        return nil
    }
}

internal class SmoothCurveTo: PathCommand {

    override var numberOfRequiredParameters: Int {
        get {
            return 4
        }
    }

    override func execute(forPath: UIBezierPath, previousCommand: PathCommand? = nil) -> SVGError? {
        guard self.parameters.count > 0 && self.parameters.count % self.numberOfRequiredParameters == 0 else {
            return SVGError.parseError(text: "SmoothCurveTo: parameters.count (\(parameters.count) % (\(self.numberOfRequiredParameters))")
        }
        if let prevCommand = previousCommand,
           let commandLetter = prevCommand.character,
           let previousParams = prevCommand.getGroups().last
        {


            let groups = self.getGroups()
            for index in 0..<groups.count {
                let group = groups[index]
                let point = self.pointForPathType(
                    CGPoint(x: group[2], y: group[3]))
                let controlEnd = self.pointForPathType(
                    CGPoint(x: group[0], y: group[1]))

                let currentPoint = forPath.currentPoint

                var controlStartX = currentPoint.x
                var controlStartY = currentPoint.y

                if index == 0 {
                    switch commandLetter {
                        case "C":
                            guard previousParams.count == 6 else {
                                return SVGError.parseError(
                                    text: "Must count previous parameters Bézier curve for SmoothCurveTo equal 6")
                            }
                            controlStartX = (2.0 * currentPoint.x) - previousParams[2]
                            controlStartY = (2.0 * currentPoint.y) - previousParams[3]
                        case "c":
                            guard previousParams.count == 6 else {
                                return SVGError.parseError(
                                    text: "Must count previous parameters Bézier curve for SmoothCurveTo equal 6")
                            }
                            let oldCurrentPoint = CGPoint(
                                x: currentPoint.x - previousParams[4], y: currentPoint.y - previousParams[5])
                            controlStartX = (2.0 * currentPoint.x) - (previousParams[2] + oldCurrentPoint.x)
                            controlStartY = (2.0 * currentPoint.y) - (previousParams[3] + oldCurrentPoint.y)
                        case "S":
                            guard previousParams.count == 4 else {
                                return SVGError.parseError(
                                    text: "Must count previous parameters Bézier curve for SmoothCurveTo equal 4")
                            }
                            controlStartX = (2.0 * currentPoint.x) - previousParams[0]
                            controlStartY = (2.0 * currentPoint.y) - previousParams[1]
                        case "s":
                            guard previousParams.count == 4 else {
                                return SVGError.parseError(
                                    text: "Must count previous parameters Bézier curve for SmoothCurveTo equal 4")
                            }
                            let oldCurrentPoint = CGPoint(
                                x: currentPoint.x - previousParams[2], y: currentPoint.y - previousParams[3])
                            controlStartX = (2.0 * currentPoint.x) - (previousParams[0] + oldCurrentPoint.x)
                            controlStartY = (2.0 * currentPoint.y) - (previousParams[1] + oldCurrentPoint.y)
                        default:
                            break

                    }
                } else {
                    let prevGroup = groups[index - 1]
                    switch self.pathType {
                        case .absolute:
                            controlStartX = (2.0 * currentPoint.x) - prevGroup[0]
                            controlStartY = (2.0 * currentPoint.y) - prevGroup[1]
                        case .relative:
                            let oldCurrentPoint = CGPoint(
                                x: currentPoint.x - prevGroup[2], y: currentPoint.y - prevGroup[3])
                            controlStartX = (2.0 * currentPoint.x) - (prevGroup[0] + oldCurrentPoint.x)
                            controlStartY = (2.0 * currentPoint.y) - (prevGroup[1] + oldCurrentPoint.y)
                    }
                }
                forPath.addCurve(
                    to: point, controlPoint1: CGPoint(x: controlStartX, y: controlStartY),
                    controlPoint2: controlEnd)
            }
        } else {
            return SVGError.parseError(text: "Must supply previous parameters for SmoothCurveTo")
        }
        return nil
    }
}

internal class QuadraticCurveTo: PathCommand {

    override var numberOfRequiredParameters: Int {
        get {
            return 4
        }
    }

    override func execute(forPath: UIBezierPath, previousCommand: PathCommand? = nil) -> SVGError? {
        guard self.parameters.count > 0 && self.parameters.count % self.numberOfRequiredParameters == 0 else {
            return SVGError.parseError(text: "QuadraticCurveTo: parameters.count (\(parameters.count) != (numberOfRequiredParameters))")
        }
        let groups = self.getGroups()
        groups.forEach { (group) in
            let controlPoint = self.pointForPathType(CGPoint(x: group[0], y: group[1]))
            let point = self.pointForPathType(CGPoint(x: group[2], y: group[3]))
            forPath.addQuadCurve(to: point, controlPoint: controlPoint)
        }
        return nil
    }
}

internal class SmoothQuadraticCurveTo: PathCommand {

    override var numberOfRequiredParameters: Int {
        get {
            return 2
        }
    }

    override func execute(forPath: UIBezierPath, previousCommand: PathCommand? = nil) -> SVGError? {
        if numberOfRequiredParameters != parameters.count {
            return SVGError.parseError(text: "SmoothQuadraticCurveTo: parameters.count (\(parameters.count) != (numberOfRequiredParameters))")
        }

        if let previousParams = previousCommand?.parameters {

            let point = self.pointForPathType(CGPoint(x: self.parameters[0], y: self.parameters[1]))
            var controlPoint = forPath.currentPoint

            if let previousChar = previousCommand?.character {
                let currentPoint = forPath.currentPoint

                if previousChar == "Q" {
                    controlPoint = CGPoint(x: (2.0 * currentPoint.x) - previousParams[0], y: (2.0 * currentPoint.y) - previousParams[1])
                } else {
                    let oldCurrentPoint = CGPoint(x: currentPoint.x - previousParams[2], y: currentPoint.y - previousParams[3])
                    controlPoint = CGPoint(x: (2.0 * currentPoint.x) - (previousParams[0] + oldCurrentPoint.x), y: (2.0 * currentPoint.y) - (previousParams[1] + oldCurrentPoint.y))
                }
            } else {
                return SVGError.parseError(text: "Must supply previous command for SmoothQuadraticCurveTo")
            }

            forPath.addQuadCurve(to: point, controlPoint: controlPoint)

        } else {
            return SVGError.parseError(text: "Must supply previous parameters for SmoothQuadraticCurveTo")
        }
        return nil
    }
}
