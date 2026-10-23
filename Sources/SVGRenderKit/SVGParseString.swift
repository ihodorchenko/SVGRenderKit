import UIKit
import CoreGraphics

/////////////////////////////////////////////////////
//
// MARK: Type Definitions

internal enum PathType {
    case absolute, relative
}

/////////////////////////////////////////////////////
//
// MARK: Protocols

internal protocol Commandable {
    var numberOfRequiredParameters: Int { get }
    func execute(forPath: UIBezierPath, previousCommand: PathCommand?) -> SVGError?
}

/////////////////////////////////////////////////////
//
// MARK: Base Classes

internal class PathCharacter {
    var character: Character?
    
    convenience init(character: Character) {
        self.init()
        self.character = character
    }
}

internal class PathCommand: PathCharacter, Commandable {
    
    var numberOfRequiredParameters: Int {
        get {
            return 0
        }
    }
    var pathType: PathType = .absolute
    var parameters: [CGFloat] = []
    /// Lazy: the parser assigns its own path right after creating the command, so an eager
    /// `UIBezierPath()` per command letter is wasted.
    lazy var path: UIBezierPath = UIBezierPath()
    /// The current point of the supplied path when appending via `forPath:`,
    /// used as the reference for a relative command before any point is drawn.
    var initialPoint: CGPoint = .zero
    
    
    override init() {
        super.init()
    }
    
    convenience init(character: Character, pathType: PathType) {
        self.init()
        self.character = character
        self.pathType = pathType
    }

    func getGroups() -> [[CGFloat]] {
        let parametersGroupCount = self.numberOfRequiredParameters
        // `ClosePath` has zero required parameters; returning no groups avoids a
        // division-by-zero crash when a command queries the previous `ClosePath`
        // (e.g. a smooth curve following `Z`).
        guard parametersGroupCount > 0 else { return [] }
        var groups: [[CGFloat]] = []

        let count: Int = self.parameters.count / parametersGroupCount
        for index in 0..<count {
            let groupI = index * parametersGroupCount
            groups.append(Array(self.parameters[groupI..<(groupI + parametersGroupCount)]))
        }

        return groups
    }
    
    func execute(forPath: UIBezierPath, previousCommand: PathCommand? = nil) -> SVGError? {
        return SVGError.unexpectedError(text: "Subclasses must implement this method")
    }
    
    func canExecute() -> Bool {
        
        if self.numberOfRequiredParameters == 0 {
            return true
        }
        
        if self.parameters.count == 0 {
            return false
        }
        
        if self.parameters.count % self.numberOfRequiredParameters != 0 {
            return false
        }
        
        return true
    }

    func push(coordinate: CGFloat) {
        self.parameters.append(coordinate)
        return
    }
    
    func executeIfPossible(previousCommand: PathCommand? = nil) -> SVGError? {
        if self.canExecute() {
            if let error = self.execute(forPath: self.path, previousCommand: previousCommand) {
                return error
            } else {
                return nil
            }
        }
        var char: String
        if let character = self.character {
            char = String(character)
        } else { char = "<n/a>" }
        return SVGError.parseError(text: "\(char) can't execute")
    }
    
    func pointForPathType(_ point: CGPoint, currentPoint: CGPoint? = nil) -> CGPoint {
        switch self.pathType {
        case .absolute:
            return point
        case .relative:
            if self.path.isEmpty {
                // No point drawn yet: a leading relative move is absolute, but when
                // appending to an existing path it is relative to that path's end.
                return CGPoint(x: point.x + initialPoint.x, y: point.y + initialPoint.y)
            } else {
                let cp: CGPoint = currentPoint ?? self.path.currentPoint
                return CGPoint(x: point.x + cp.x, y: point.y + cp.y)
            }
        }
    }
}

/// Parses SVG path data (`d` attribute) strings into `UIBezierPath` objects.
public class SVGParseString {
    /// A completion handler that receives an optional error and the resulting path.
    public typealias SVGParseStringkCompletion = (_ svgError: SVGError?, _ bezierPath: UIBezierPath?) -> Void



    /// Lexical class of a path-data byte.
    fileprivate enum ByteClass {
        case command(PathCommand)
        case separator
        case sign
        case delimiter
        case number
        case invalid
    }

    /// Classifies one UTF-8 byte of path data. Only commands allocate (one object per command letter);
    /// digits, signs and separators are allocation-free.
    @inline(__always)
    fileprivate class func classify(_ byte: UInt8) -> ByteClass {
        switch byte {
        case UInt8(ascii: "A"): return .command(EllipticalArcTo(character: "A", pathType: .absolute))
        case UInt8(ascii: "a"): return .command(EllipticalArcTo(character: "a", pathType: .relative))
        case UInt8(ascii: "M"): return .command(MoveTo(character: "M", pathType: .absolute))
        case UInt8(ascii: "m"): return .command(MoveTo(character: "m", pathType: .relative))
        case UInt8(ascii: "C"): return .command(CurveTo(character: "C", pathType: .absolute))
        case UInt8(ascii: "c"): return .command(CurveTo(character: "c", pathType: .relative))
        case UInt8(ascii: "S"): return .command(SmoothCurveTo(character: "S", pathType: .absolute))
        case UInt8(ascii: "s"): return .command(SmoothCurveTo(character: "s", pathType: .relative))
        case UInt8(ascii: "L"): return .command(LineTo(character: "L", pathType: .absolute))
        case UInt8(ascii: "l"): return .command(LineTo(character: "l", pathType: .relative))
        case UInt8(ascii: "H"): return .command(HorizontalLineTo(character: "H", pathType: .absolute))
        case UInt8(ascii: "h"): return .command(HorizontalLineTo(character: "h", pathType: .relative))
        case UInt8(ascii: "V"): return .command(VerticalLineTo(character: "V", pathType: .absolute))
        case UInt8(ascii: "v"): return .command(VerticalLineTo(character: "v", pathType: .relative))
        case UInt8(ascii: "Q"): return .command(QuadraticCurveTo(character: "Q", pathType: .absolute))
        case UInt8(ascii: "q"): return .command(QuadraticCurveTo(character: "q", pathType: .relative))
        case UInt8(ascii: "T"): return .command(SmoothQuadraticCurveTo(character: "T", pathType: .absolute))
        case UInt8(ascii: "t"): return .command(SmoothQuadraticCurveTo(character: "t", pathType: .relative))
        case UInt8(ascii: "Z"): return .command(ClosePath(character: "Z", pathType: .absolute))
        case UInt8(ascii: "z"): return .command(ClosePath(character: "z", pathType: .relative))
        case UInt8(ascii: "-"), UInt8(ascii: "+"): return .sign
        case UInt8(ascii: "."): return .delimiter
        case UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "e"), UInt8(ascii: "E"): return .number
        case UInt8(ascii: " "), UInt8(ascii: ","), 0x0A, 0x09, 0x0D, 0x0B, 0x0C: return .separator
        default: return .invalid
        }
    }

    /// The number being scanned, kept as raw bytes with O(1) emptiness / decimal-point / exponent checks.
    internal struct ByteNumber {
        var bytes: [UInt8] = []
        var hasDelimiter = false

        init() { bytes.reserveCapacity(24) }

        var isEmpty: Bool { return bytes.isEmpty }
        var isLastE: Bool { return bytes.last == UInt8(ascii: "e") || bytes.last == UInt8(ascii: "E") }

        mutating func push(_ byte: UInt8) {
            if byte == UInt8(ascii: ".") { hasDelimiter = true }
            bytes.append(byte)
        }

        mutating func clear() {
            bytes.removeAll(keepingCapacity: true)
            hasDelimiter = false
        }

        /// Malformed numbers (`1e-`, `.`, `-`) and
        /// non-finite (`1e999`) are rejected. Short numbers fit a small string, so no heap allocation.
        var asCGFloat: CGFloat? {
            guard !bytes.isEmpty else { return nil }
            if let value = Double(String(decoding: bytes, as: UTF8.self)), value.isFinite { return CGFloat(value) }
            return nil
        }
    }

    /// The character that starts at the given UTF-8 offset, for error messages.
    fileprivate class func invalidCharacter(in string: String, utf8Offset: Int) -> Character {
        let index = string.utf8.index(string.utf8.startIndex, offsetBy: utf8Offset)
        return string[index...].first ?? "?"
    }

    @inline(__always)
    fileprivate class func isASCIIDigit(_ byte: UInt8) -> Bool {
        return byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")
    }

    /// Merges the completed subpaths with the one in progress, for a partial result
    /// when parsing stops at an error (B85: render the path up to the error).
    fileprivate class func partialPath(_ completed: UIBezierPath, _ inProgress: UIBezierPath) -> UIBezierPath? {
        let result = completed
        if !inProgress.isEmpty {
            result.append(inProgress)
        }
        return result.isEmpty ? nil : result
    }

    /// Parses an SVG path data string into a `UIBezierPath`.
    /// - parameter pathString: The SVG path data string, which must begin with a MoveTo (`M`/`m`) command.
    /// - parameter forPath: An optional existing path to append the parsed commands to.
    /// - returns: A tuple containing the resulting path (or `nil`) and an optional error.
    public class func parseSVGPath(pathString: String, forPath: UIBezierPath? = nil) -> (path: UIBezierPath?, error: SVGError?) {

        // Trim surrounding whitespace so a leading space before `M`/`m` (valid in
        // SVG path data) doesn't reject the path.
        let workingString = pathString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !(workingString.hasPrefix("M") || workingString.hasPrefix("m")) {
            return (path: nil, error: SVGError.parseError(text: "Path d attribute must begin with MoveTo Command (\"M\")"))
        }

        var returnPath = UIBezierPath()

        if let suppliedPath = forPath {
            returnPath = suppliedPath
        }
        var currentPath: UIBezierPath = UIBezierPath()

        var previousCommand: PathCommand?
        var currentPathCommand: PathCommand = PathCommand(character: "M")
        var currentNumber = ByteNumber()


        let pushCoordinateAndExecuteIfPossible: () -> SVGError? = {
            if currentNumber.isEmpty == false {
                if let newCoordinate = currentNumber.asCGFloat {
                    currentPathCommand.push(coordinate: newCoordinate)
                }
            }
            let error = currentPathCommand.executeIfPossible(previousCommand: previousCommand)
            if let error = error {
                return error
            } else {
                previousCommand = currentPathCommand
            }
            currentNumber.clear()
            return nil
        }
        let pushCoordinateAndClear: () -> Void = {
            if currentNumber.isEmpty == false {
                if let newCoordinate = currentNumber.asCGFloat {
                    currentPathCommand.push(coordinate: newCoordinate)
                }
                currentNumber.clear()
            }
            return
        }
        var thisEnd: Bool = false
        // Single pass over UTF-8. The index of the last byte is computed once: `String.count` is O(n),
        // and evaluating it per command made parsing quadratic in the path length.
        let bytes = Array(workingString.utf8)
        let lastIndex = bytes.count - 1
        for (index, byte) in bytes.enumerated() {

            thisEnd = false
            switch classify(byte) {
            case .command(let command):
                if let error = pushCoordinateAndExecuteIfPossible() {
                    if index > 0 {// ignored for the start
                        return (path: partialPath(returnPath, currentPath), error: error)
                    }
                }
                currentPathCommand = command
                currentPathCommand.path = currentPath
                // `currentPoint` on an empty path logs a CoreGraphics error each time, which is costly
                // when it happens for every command before the first `Z`; an empty path is at the origin.
                currentPathCommand.initialPoint = returnPath.isEmpty ? .zero : returnPath.currentPoint

                if let closeCommand = currentPathCommand as? ClosePath {
                    if let error = closeCommand.execute(
                        forPath: currentPath, previousCommand: previousCommand) { return (nil, error) }
                    let currentPoint: CGPoint = currentPath.currentPoint
                    returnPath.append(currentPath)
                    currentPath = UIBezierPath()
                    currentPath.move(to: currentPoint)

                }
                if index == lastIndex {
                    thisEnd = true
                }
            case .separator:
                pushCoordinateAndClear()
            case .sign where !currentNumber.isLastE:
                pushCoordinateAndClear()
                currentNumber.push(byte)
            case .sign, .delimiter, .number:
                if byte == UInt8(ascii: "."), currentNumber.hasDelimiter {
                    pushCoordinateAndClear()
                }
                currentNumber.push(byte)
                // The elliptical-arc large-arc / sweep flags are single characters
                // (SVG 1.1 §8.3.8), so flush right after the flag byte. Otherwise
                // compact output like `a2 2 0 011 1` (SVGO) reads "011" as one number.
                if currentPathCommand is EllipticalArcTo, isASCIIDigit(byte) {
                    let parameterIndex = currentPathCommand.parameters.count % currentPathCommand.numberOfRequiredParameters
                    if parameterIndex == 3 || parameterIndex == 4 {
                        pushCoordinateAndClear()
                    }
                }
            case .invalid:
                return (path: partialPath(returnPath, currentPath),
                        error: SVGError.parseError(text: "Invalid character \"\(invalidCharacter(in: workingString, utf8Offset: index))\" found"))
            }
        }
        if thisEnd == false {
            if let error = pushCoordinateAndExecuteIfPossible() { return (path: partialPath(returnPath, currentPath), error: error) }
            returnPath.append(currentPath)
        } else if !(currentPathCommand is ClosePath) {
            // The path ends with a dangling command letter (e.g. a trailing 'L').
            // Preserve the path accumulated before it instead of silently dropping it.
            returnPath.append(currentPath)
        }

        return (path: returnPath, error: nil)
    }
}
