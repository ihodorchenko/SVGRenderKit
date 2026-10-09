import UIKit

internal enum SVGTransformType: String {
    case matrix
    case translate
    case rotate
    case scale
    case skewX
    case skewY
}

/// Parses an SVG transform string into a CATransform3D.
open class SVGTransform {
    private class TransformElement {
        let type: SVGTransformType
        let values: [CGFloat]

        init(type: SVGTransformType, values: [CGFloat]) {
            self.type = type
            self.values = values
        }
    }

    class func get(string: String, base: CATransform3D = CATransform3DIdentity) throws -> CATransform3D {
        var transformArray: [TransformElement] = []
        var transform = base
        var key: String = ""
        var tempValue: String = ""
        var isValue: Bool = false
        var string = string.replacingOccurrences(of: ", ", with: " ")
        string = string.replacingOccurrences(of: ",", with: " ")
        for char in string {
            if char == "(" {
                isValue = true
            } else if char == ")" {
                isValue = false
                let charSet: CharacterSet = CharacterSet(charactersIn: " ")
                let valueArr: [String] = SVGUtils.split(string: tempValue, separatorSet: charSet)
                var numberArr: [CGFloat] = []
                for num in valueArr {
                    if let d = Double(num) {
                        numberArr.append(CGFloat(d))
                    }
                }
                if valueArr.count > 0 {
                    if let type = SVGTransformType.init(rawValue: key.trimmed) {
                        transformArray.append(
                            TransformElement(type: type, values: numberArr))
                    } else {
                        throw SVGError.parseError(text: "transform type \(key) not supported")
                    }
                } else {
                    throw SVGError.content(text: "transform values == 0")
                }
                key = ""
                tempValue = ""
            } else {
                if isValue == true {
                    tempValue.append(char)
                } else {
                    key.append(char)
                }
            }
        }

        for transformElem in transformArray {
            let values = transformElem.values
            switch transformElem.type {
            case .matrix:
                if values.count == 6 {
                    let tr = CATransform3D(m11: values[0], m12: values[1], m13: 0, m14: 0,
                                           m21: values[2], m22: values[3], m23: 0, m24: 0,
                                           m31: 0, m32: 0, m33: 1, m34: 0,
                                           m41: values[4], m42: values[5], m43: 0, m44: 1)
                    transform = CATransform3DConcat(transform, tr)
                } else {
                    throw SVGError.parseError(text: "when parse 'matrix'")
                }
                break
            case .translate:
                if values.count == 2 {
                    transform = CATransform3DTranslate(transform, values[0], values[1], 0)
                } else if values.count == 1 {
                    transform = CATransform3DTranslate(transform, values[0], 0, 0)
                } else {
                    throw SVGError.parseError(text: "when parse transform 'translate'")
                }
                break
            case .rotate:
                if values.count == 1 {
                    transform = CATransform3DRotate(transform, values[0]*CGFloat.pi / 180.0, 0, 0, 1)
                } else if values.count == 3 {
                    transform = CATransform3DTranslate(transform, values[1], values[2], 0)
                    transform = CATransform3DRotate(transform, values[0]*CGFloat.pi / 180.0, 0, 0, 1)
                    transform = CATransform3DTranslate(transform, -values[1], -values[2], 0)
                } else {
                    throw SVGError.parseError(text: "when parse transform 'rotate'")
                }
                break
            case .scale:
                if values.count == 2 {
                    transform = CATransform3DScale(transform, values[0], values[1], 1)
                } else if values.count == 1 {
                    transform = CATransform3DScale(transform, values[0], values[0], 1)
                } else {
                    throw SVGError.parseError(text: "when parse transform 'scale'")
                }
                break
            case .skewX:
                if values.count == 1 {
                    let v = tan(values[0] * CGFloat.pi / 180.0)
                    let tr = CATransform3D(m11: 1, m12: 0, m13: 0, m14: 0,
                                           m21: v, m22: 1, m23: 0, m24: 0,
                                           m31: 0, m32: 0, m33: 1, m34: 0,
                                           m41: 0, m42: 0, m43: 0, m44: 1)
                    transform = CATransform3DConcat(transform, tr)
                } else {
                    throw SVGError.parseError(text: "when parse transform 'skewX'")
                }
                break
            case .skewY:
                if values.count == 1 {
                    let v = tan(values[0] * CGFloat.pi / 180.0)
                    let tr = CATransform3D(m11: 1, m12: v, m13: 0, m14: 0,
                                           m21: 0, m22: 1, m23: 0, m24: 0,
                                           m31: 0, m32: 0, m33: 1, m34: 0,
                                           m41: 0, m42: 0, m43: 0, m44: 1)
                    transform = CATransform3DConcat(transform, tr)
                } else {
                    throw SVGError.parseError(text: "when parse transform 'skewY'")
                }
                break
            }
        }
        return transform
    }
}
