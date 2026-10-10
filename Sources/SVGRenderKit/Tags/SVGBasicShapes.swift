import UIKit

/// A drawable rectangle shape that renders an SVG `<rect>` element.
open class SVGShapeRect: SVGShapeObject {
    class override var key: String { get { return "rect" }}

    var x: CGFloat = 0
    var y: CGFloat = 0
    var width: CGFloat?
    var height: CGFloat?
    var rx: CGFloat?
    var ry: CGFloat?

    /// Initializes a rectangle by parsing its `x`, `y`, `width`, `height`, and corner-radius attributes.
    public required init(xmlElement: XMLElement, addDict: [String: String]? = nil, parent: SVGShapesContainer) throws {
        try super.init(xmlElement: xmlElement, addDict: addDict, parent: parent)

        if let str = attributeDict["x"] {
            if let f: Float = Float(str.trimmed) { x = CGFloat(f) } else {
                throw SVGError.parseError(text: "invalid convert 'x' to float '\(str)'")
            }
        }
        if let str = attributeDict["y"] {
            if let f: Float = Float(str.trimmed) { y = CGFloat(f) } else {
                throw SVGError.parseError(text: "invalid convert 'y' to float '\(str)'")
            }
        }
        if let str = attributeDict["width"] {
            if let f: Float = Float(str.trimmed) { width = CGFloat(f) } else {
                throw SVGError.parseError(text: "invalid convert 'width' to float '\(str)'")
            }
        } else {
            throw SVGError.parseError(text: "not found key 'width' in tag 'rect'")
        }
        if let str = attributeDict["height"] {
            if let f: Float = Float(str.trimmed) { height = CGFloat(f) } else {
                throw SVGError.parseError(text: "invalid convert 'height' to float '\(str)'")
            }
        } else {
            throw SVGError.parseError(text: "not found key 'height' in tag 'rect'")
        }
        if let str = attributeDict["rx"] {
            if let f: Float = Float(str.trimmed) { rx = CGFloat(f) } else {
                throw SVGError.parseError(text: "invalid convert 'rx' to float '\(str)'")
            }
        }
        if let str = attributeDict["ry"] {
            if let f: Float = Float(str.trimmed) { ry = CGFloat(f) } else {
                throw SVGError.parseError(text: "invalid convert 'ry' to float '\(str)'")
            }
        }

        if let width = width, let height = height {
            let path: UIBezierPath
            var cornerRadii: CGSize? = nil
            if let rx = self.rx, let ry = self.ry {
                cornerRadii = CGSize(width: rx, height: ry)
            } else if let rx = self.rx {
                cornerRadii = CGSize(width: rx, height: rx)
            } else if let ry = self.ry {
                cornerRadii = CGSize(width: ry, height: ry)
            }
            if let cornerRadii = cornerRadii {
                path = SVGShapeRect.roundedRectPath(
                    rect: CGRect(x: x, y: y, width: width, height: height),
                    rx: cornerRadii.width,
                    ry: cornerRadii.height)
            } else {
                path = UIBezierPath(rect: CGRect(x: x, y: y, width: width, height: height))
            }
            self.path = path
        }
    }

    /// Builds a rounded-rectangle path with true elliptical corners.
    ///
    /// `UIBezierPath(roundedRect:byRoundingCorners:cornerRadii:)` collapses an
    /// oversized or non-square radius into a single circular radius, but SVG clamps
    /// `rx`/`ry` independently (to half width / half height) and draws elliptical
    /// corners. Each 90° corner is approximated with a cubic Bézier using the
    /// standard circle constant κ ≈ 0.5523, which is accurate to well under a pixel.
    private static func roundedRectPath(rect: CGRect, rx: CGFloat, ry: CGFloat) -> UIBezierPath {
        let rx = min(max(0, rx), rect.width / 2)
        let ry = min(max(0, ry), rect.height / 2)
        guard rx > 0, ry > 0 else { return UIBezierPath(rect: rect) }

        let kappa: CGFloat = 0.552284749831
        let minX = rect.minX
        let minY = rect.minY
        let maxX = rect.maxX
        let maxY = rect.maxY

        let path = UIBezierPath()
        path.move(to: CGPoint(x: minX + rx, y: minY))
        path.addLine(to: CGPoint(x: maxX - rx, y: minY))
        // top-right corner
        path.addCurve(
            to: CGPoint(x: maxX, y: minY + ry),
            controlPoint1: CGPoint(x: maxX - rx + rx * kappa, y: minY),
            controlPoint2: CGPoint(x: maxX, y: minY + ry - ry * kappa))
        path.addLine(to: CGPoint(x: maxX, y: maxY - ry))
        // bottom-right corner
        path.addCurve(
            to: CGPoint(x: maxX - rx, y: maxY),
            controlPoint1: CGPoint(x: maxX, y: maxY - ry + ry * kappa),
            controlPoint2: CGPoint(x: maxX - rx + rx * kappa, y: maxY))
        path.addLine(to: CGPoint(x: minX + rx, y: maxY))
        // bottom-left corner
        path.addCurve(
            to: CGPoint(x: minX, y: maxY - ry),
            controlPoint1: CGPoint(x: minX + rx - rx * kappa, y: maxY),
            controlPoint2: CGPoint(x: minX, y: maxY - ry + ry * kappa))
        path.addLine(to: CGPoint(x: minX, y: minY + ry))
        // top-left corner
        path.addCurve(
            to: CGPoint(x: minX + rx, y: minY),
            controlPoint1: CGPoint(x: minX, y: minY + ry - ry * kappa),
            controlPoint2: CGPoint(x: minX + rx - rx * kappa, y: minY))
        path.close()
        return path
    }
}

/// A drawable circle shape that renders an SVG `<circle>` element.
open class SVGShapeCircle: SVGShapeObject {
    class override var key: String { get { return "circle" }}

    var cx: CGFloat = 0
    var cy: CGFloat = 0
    var r: CGFloat?

    /// Initializes a circle by parsing its `cx`, `cy`, and `r` attributes.
    public required init(xmlElement: XMLElement, addDict: [String: String]? = nil, parent: SVGShapesContainer) throws {
        try super.init(xmlElement: xmlElement, addDict: addDict, parent: parent)

        if let str = attributeDict["cx"] {
            if let f: Float = Float(str.trimmed) { cx = CGFloat(f) } else {
                throw SVGError.parseError(text: "invalid convert 'cx' to float '\(str)'")
            }
        }
        if let str = attributeDict["cy"] {
            if let f: Float = Float(str.trimmed) { cy = CGFloat(f) } else {
                throw SVGError.parseError(text: "invalid convert 'cy' to float '\(str)'")
            }
        }
        if let str = attributeDict["r"] {
            if let f: Float = Float(str.trimmed) { r = CGFloat(f) } else {
                throw SVGError.parseError(text: "invalid convert 'r' to float '\(str)'")
            }
        } else {
            throw SVGError.parseError(text: "not found key 'r' in tag 'circle'")
        }

        if let r = r {
            let circlePath = UIBezierPath(arcCenter: CGPoint(x: cx, y: cy), radius: r, startAngle: CGFloat(0), endAngle:CGFloat(Double.pi * 2), clockwise: true)
            self.path = circlePath
        }
    }
}

/// A drawable ellipse shape that renders an SVG `<ellipse>` element.
open class SVGShapeEllipse: SVGShapeObject {
    class override var key: String { get { return "ellipse" }}

    var cx: CGFloat = 0
    var cy: CGFloat = 0
    var rx: CGFloat = 0
    var ry: CGFloat = 0

    /// Initializes an ellipse by parsing its `cx`, `cy`, `rx`, and `ry` attributes.
    public required init(xmlElement: XMLElement, addDict: [String: String]? = nil, parent: SVGShapesContainer) throws {
        try super.init(xmlElement: xmlElement, addDict: addDict, parent: parent)

        if let str = attributeDict["cx"] {
            if let f: Float = Float(str.trimmed) { cx = CGFloat(f) } else {
                throw SVGError.parseError(text: "invalid convert 'cx' to float '\(str)'")
            }
        }
        if let str = attributeDict["cy"] {
            if let f: Float = Float(str.trimmed) { cy = CGFloat(f) } else {
                throw SVGError.parseError(text: "invalid convert 'cy' to float '\(str)'")
            }
        }
        if let str = attributeDict["rx"] {
            if let f: Float = Float(str.trimmed) { rx = CGFloat(f) } else {
                throw SVGError.parseError(text: "invalid convert 'rx' to float '\(str)'")
            }
            if rx < 0 {
                throw SVGError.parseError(text: "'rx' == \(rx) < 0 in tag 'ellipse'")
            }
        }
        if let str = attributeDict["ry"] {
            if let f: Float = Float(str.trimmed) { ry = CGFloat(f) } else {
                throw SVGError.parseError(text: "invalid convert 'ry' to float '\(str)'")
            }
            if ry < 0 {
                throw SVGError.parseError(text: "'ry' == \(ry) < 0 in tag 'ellipse'")
            }
        }

        if rx > 0, ry > 0 {
            let path = UIBezierPath(
                ovalIn: CGRect(x: CGFloat(cx - rx),
                               y: CGFloat(cy - ry),
                               width: CGFloat(rx*2), height: CGFloat(ry*2)))
            self.path = path
        }
    }
}

/// A drawable line shape that renders an SVG `<line>` element.
open class SVGShapeLine: SVGShapeObject {
    class override var key: String { get { return "line" }}

    var x1: CGFloat = 0
    var y1: CGFloat = 0
    var x2: CGFloat = 0
    var y2: CGFloat = 0

    /// Initializes a line by parsing its `x1`, `y1`, `x2`, and `y2` attributes.
    public required init(xmlElement: XMLElement, addDict: [String: String]? = nil, parent: SVGShapesContainer) throws {
        try super.init(xmlElement: xmlElement, addDict: addDict, parent: parent)

        if let str = attributeDict["x1"] {
            if let f: Float = Float(str.trimmed) { x1 = CGFloat(f) } else {
                throw SVGError.parseError(text: "invalid convert 'x1' to float '\(str)'")
            }
        }
        if let str = attributeDict["y1"] {
            if let f: Float = Float(str.trimmed) { y1 = CGFloat(f) } else {
                throw SVGError.parseError(text: "invalid convert 'y1' to float '\(str)'")
            }
        }
        if let str = attributeDict["x2"] {
            if let f: Float = Float(str.trimmed) { x2 = CGFloat(f) } else {
                throw SVGError.parseError(text: "invalid convert 'x2' to float '\(str)'")
            }
        }
        if let str = attributeDict["y2"] {
            if let f: Float = Float(str.trimmed) { y2 = CGFloat(f) } else {
                throw SVGError.parseError(text: "invalid convert 'y2' to float '\(str)'")
            }
        }

        let path = UIBezierPath()
        path.move(to: CGPoint(x: x1, y: y1))
        path.addLine(to: CGPoint(x: x2, y: y2))
        self.path = path
    }

}

/// A drawable polyline shape that renders an SVG `<polyline>` element as an open path.
open class SVGShapePolyline: SVGShapeObject {
    class override var key: String { get { return "polyline" }}

    private(set) var points: [CGPoint] = []

    /// Initializes a polyline by parsing its `points` attribute into an ordered list of points.
    public required init(xmlElement: XMLElement, addDict: [String: String]? = nil, parent: SVGShapesContainer) throws {
        try super.init(xmlElement: xmlElement, addDict: addDict, parent: parent)

        if let str = attributeDict["points"] {
            let charSet = CharacterSet(charactersIn: " ,")
            let arr = SVGUtils.split(string: str, separatorSet: charSet)
            if arr.count % 2 == 0 {
                let count = arr.count
                var index: Int = 0
                while index < count {
                    if let x = Double(arr[index]), let y = Double(arr[index + 1]) {
                        points.append(CGPoint(x: x, y: y))
                    } else {
                        throw SVGError.parseError(text: "invalid convert point '\(arr[index]):\(arr[index + 1])' to float in tag 'polyline'")
                    }
                    index += 2
                }
            } else {
                throw SVGError.parseError(text: "'points' not 'count % 2 == 0' in tag 'polyline'")
            }
        }

        if points.count > 1 {
            let path = UIBezierPath()
            path.move(to: points[0])
            for index in 1..<points.count {
                path.addLine(to: points[index])
            }
            self.path = path
        }
    }
}

/// A drawable polygon shape that renders an SVG `<polygon>` element as a closed path.
open class SVGShapePolygon: SVGShapeObject {
    class override var key: String { get { return "polygon" }}

    private(set) var points: [CGPoint] = []

    /// Initializes a polygon by parsing its `points` attribute and closing the resulting path.
    public required init(xmlElement: XMLElement, addDict: [String: String]? = nil, parent: SVGShapesContainer) throws {
        try super.init(xmlElement: xmlElement, addDict: addDict, parent: parent)

        if let str = attributeDict["points"] {
            let charSet = CharacterSet(charactersIn: " ,")
            let arr = SVGUtils.split(string: str, separatorSet: charSet)
            if arr.count % 2 == 0 {
                let count = arr.count
                var index: Int = 0
                while index < count {
                    if let x = Double(arr[index]), let y = Double(arr[index + 1]) {
                        points.append(CGPoint(x: x, y: y))
                    } else {
                        throw SVGError.parseError(text: "invalid convert point '\(arr[index]):\(arr[index + 1])' to float in tag 'polygon'")
                    }
                    index += 2
                }
            } else {
                throw SVGError.parseError(text: "'points' not 'count % 2 == 0' in tag 'polygon'")
            }
        }

        if points.count > 1 {
            let path = UIBezierPath()
            path.move(to: points[0])
            for index in 1..<points.count {
                path.addLine(to: points[index])
            }
            path.close()
            self.path = path
        }
    }

}
