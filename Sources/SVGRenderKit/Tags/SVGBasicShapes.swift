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

        let viewBox = parent.getSvgOptions().viewBox
        if let str = attributeDict["x"] {
            x = resolveLength(str, reference: viewBox.width)
        }
        if let str = attributeDict["y"] {
            y = resolveLength(str, reference: viewBox.height)
        }
        if let str = attributeDict["width"] {
            width = resolveLength(str, reference: viewBox.width)
        } else {
            throw SVGError.parseError(text: "not found key 'width' in tag 'rect'")
        }
        if let str = attributeDict["height"] {
            height = resolveLength(str, reference: viewBox.height)
        } else {
            throw SVGError.parseError(text: "not found key 'height' in tag 'rect'")
        }
        if let str = attributeDict["rx"] {
            rx = resolveLength(str, reference: viewBox.width)
        }
        if let str = attributeDict["ry"] {
            ry = resolveLength(str, reference: viewBox.height)
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

        let viewBox = parent.getSvgOptions().viewBox
        let diagSq = (viewBox.width * viewBox.width + viewBox.height * viewBox.height) / 2
        let diagonal = sqrt(diagSq)
        if let str = attributeDict["cx"] {
            cx = resolveLength(str, reference: viewBox.width)
        }
        if let str = attributeDict["cy"] {
            cy = resolveLength(str, reference: viewBox.height)
        }
        if let str = attributeDict["r"] {
            let value = resolveLength(str, reference: diagonal)
            if value < 0 {
                throw SVGError.parseError(text: "'r' == \(value) < 0 in tag 'circle'")
            }
            r = value
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

        let viewBox = parent.getSvgOptions().viewBox
        if let str = attributeDict["cx"] {
            cx = resolveLength(str, reference: viewBox.width)
        }
        if let str = attributeDict["cy"] {
            cy = resolveLength(str, reference: viewBox.height)
        }
        if let str = attributeDict["rx"] {
            let value = resolveLength(str, reference: viewBox.width)
            if value < 0 {
                throw SVGError.parseError(text: "'rx' == \(value) < 0 in tag 'ellipse'")
            }
            rx = value
        }
        if let str = attributeDict["ry"] {
            let value = resolveLength(str, reference: viewBox.height)
            if value < 0 {
                throw SVGError.parseError(text: "'ry' == \(value) < 0 in tag 'ellipse'")
            }
            ry = value
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

        let viewBox = parent.getSvgOptions().viewBox
        if let str = attributeDict["x1"] {
            x1 = resolveLength(str, reference: viewBox.width)
        }
        if let str = attributeDict["y1"] {
            y1 = resolveLength(str, reference: viewBox.height)
        }
        if let str = attributeDict["x2"] {
            x2 = resolveLength(str, reference: viewBox.width)
        }
        if let str = attributeDict["y2"] {
            y2 = resolveLength(str, reference: viewBox.height)
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
            let charSet = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ","))
            let arr = SVGUtils.split(string: str, separatorSet: charSet)
            // SVG 2: an odd trailing coordinate is dropped, the rest of the pairs render (B119-5).
            var index: Int = 0
            while index + 1 < arr.count {
                if let x = Double(arr[index]), let y = Double(arr[index + 1]) {
                    points.append(CGPoint(x: x, y: y))
                } else {
                    throw SVGError.parseError(text: "invalid convert point '\(arr[index]):\(arr[index + 1])' to float in tag 'polyline'")
                }
                index += 2
            }
            // Fewer than two points is unusable geometry: there is nothing to draw, so the
            // element is skipped with a log like any other (B85).
            guard points.count > 1 else {
                throw SVGError.parseError(text: "'points' has fewer than two complete pairs in tag 'polyline'")
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
            let charSet = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ","))
            let arr = SVGUtils.split(string: str, separatorSet: charSet)
            // SVG 2: an odd trailing coordinate is dropped, the rest of the pairs render (B119-5).
            var index: Int = 0
            while index + 1 < arr.count {
                if let x = Double(arr[index]), let y = Double(arr[index + 1]) {
                    points.append(CGPoint(x: x, y: y))
                } else {
                    throw SVGError.parseError(text: "invalid convert point '\(arr[index]):\(arr[index + 1])' to float in tag 'polygon'")
                }
                index += 2
            }
            // Fewer than two points is unusable geometry: there is nothing to draw, so the
            // element is skipped with a log like any other (B85).
            guard points.count > 1 else {
                throw SVGError.parseError(text: "'points' has fewer than two complete pairs in tag 'polygon'")
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
