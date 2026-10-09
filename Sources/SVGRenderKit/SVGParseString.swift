import UIKit
import CoreGraphics

/////////////////////////////////////////////////////
//
// MARK: Type Definitions

internal enum PathType {
    case absolute, relative
}

internal struct NumberStack {
    private let signCharset = CharacterSet(charactersIn: "+-")
    var characterStack: String = ""
    var asCGFloat: CGFloat? {
        get {
            if self.characterStack.count > 0 {
                return CGFloat(strtod(self.characterStack, nil))
            }
            return nil
        }
    }
    var isEmpty: Bool {
        get {
            if self.characterStack.count > 0 {
                return false
            }
            return true
        }
    }

    var isHaveDelim: Bool {
        get {
            return characterStack.contains(".")
        }
    }

    var isHaveE: Bool {
        get {
            let eCharset = CharacterSet(charactersIn: "eE")
            return characterStack.rangeOfCharacter(from: eCharset) != nil
        }
    }

    var isLastE: Bool {
        get {
            return self.characterStack.last == "e" || self.characterStack.last == "E"
        }
    }

    var isHaveSign: Bool {
        get {
            return characterStack.rangeOfCharacter(from: self.signCharset) != nil
        }
    }
    
    init() { }
    
    init(startCharacter: Character) {
        self.characterStack = String(startCharacter)
    }
    
    mutating func push(_ character: Character) {
        self.characterStack += String(character)
    }
    
    mutating func clear() {
        self.characterStack = String()
    }
}

internal struct PreviousCommand {
    var commandLetter: String?
    var parameters: [CGFloat]?
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

internal class NumberCharacter: PathCharacter {}
internal class NumberDelimiterCharacter: NumberCharacter {}
internal class SeparatorCharacter: PathCharacter {}
internal class SignCharacter: NumberCharacter {}

internal class PathCommand: PathCharacter, Commandable {
    
    var numberOfRequiredParameters: Int {
        get {
            return 0
        }
    }
    var pathType: PathType = .absolute
    var parameters: [CGFloat] = []
    var path: UIBezierPath = UIBezierPath()
    
    
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
    
    func pushCoordinateAndExecuteIfPossible(_ coordinate: CGFloat, previousCommand: PathCommand? = nil) -> (previousCommand: PreviousCommand?, svgError: SVGError?) {
        self.parameters.append(coordinate)
        if self.canExecute() {
            if let error = self.execute(forPath: self.path, previousCommand: previousCommand) {
                return (nil, error)
            } else {
                let returnParameters = self.parameters
                return (PreviousCommand(commandLetter: String(self.character!), parameters: returnParameters), nil)
            }
        }
        return (nil, nil)
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
                return point
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



    fileprivate class func getPathCharacter(char: Character) -> PathCharacter? {
        switch char {
        case "A":
            return EllipticalArcTo(character: "A", pathType: PathType.absolute)
        case "a":
            return EllipticalArcTo(character: "a", pathType: PathType.relative)
        case "M":
            return MoveTo(character: "M", pathType: PathType.absolute)
        case "m":
            return MoveTo(character: "m", pathType: PathType.relative)
        case "C":
            return CurveTo(character: "C", pathType: PathType.absolute)
        case "c":
            return CurveTo(character: "c", pathType: PathType.relative)
        case "S":
            return SmoothCurveTo(character: "S", pathType: PathType.absolute)
        case "s":
            return SmoothCurveTo(character: "s", pathType: PathType.relative)
        case "L":
            return LineTo(character: "L", pathType: PathType.absolute)
        case "l":
            return LineTo(character: "l", pathType: PathType.relative)
        case "H":
            return HorizontalLineTo(character: "H", pathType: PathType.absolute)
        case "h":
            return HorizontalLineTo(character: "h", pathType: PathType.relative)
        case "V":
            return VerticalLineTo(character: "V", pathType: PathType.absolute)
        case "v":
            return VerticalLineTo(character: "v", pathType: PathType.relative)
        case "Q":
            return QuadraticCurveTo(character: "Q", pathType: PathType.absolute)
        case "q":
            return QuadraticCurveTo(character: "q", pathType: PathType.relative)
        case "T":
            return SmoothQuadraticCurveTo(character: "T", pathType: PathType.absolute)
        case "t":
            return SmoothQuadraticCurveTo(character: "t", pathType: PathType.relative)
        case "Z":
            return ClosePath(character: "Z", pathType: PathType.absolute)
        case "z":
            return ClosePath(character: "z", pathType: PathType.relative)
        case "-":
            return SignCharacter(character: "-")
        case "+":
            return SignCharacter(character: "+")
        case ".":
            return NumberDelimiterCharacter(character: ".")
        case "0":
            return NumberCharacter(character: "0")
        case "1":
            return NumberCharacter(character: "1")
        case "2":
            return NumberCharacter(character: "2")
        case "3":
            return NumberCharacter(character: "3")
        case "4":
            return NumberCharacter(character: "4")
        case "5":
            return NumberCharacter(character: "5")
        case "6":
            return NumberCharacter(character: "6")
        case "7":
            return NumberCharacter(character: "7")
        case "8":
            return NumberCharacter(character: "8")
        case "9":
            return NumberCharacter(character: "9")
        case "e":
            return NumberCharacter(character: "e")
        case " ":
            return SeparatorCharacter(character: " ")
        case ",":
            return SeparatorCharacter(character: ",")
        default:
            return nil
        }
    }

    /// Parses an SVG path data string into a `UIBezierPath`.
    /// - parameter pathString: The SVG path data string, which must begin with a MoveTo (`M`/`m`) command.
    /// - parameter forPath: An optional existing path to append the parsed commands to.
    /// - returns: A tuple containing the resulting path (or `nil`) and an optional error.
    public class func parseSVGPath(pathString: String, forPath: UIBezierPath? = nil) -> (path: UIBezierPath?, error: SVGError?) {

        if !(pathString.hasPrefix("M") || pathString.hasPrefix("m")) {
            return (path: nil, error: SVGError.parseError(text: "Path d attribute must begin with MoveTo Command (\"M\")"))
        }

        let workingString = pathString

        var returnPath = UIBezierPath()

        if let suppliedPath = forPath {
            returnPath = suppliedPath
        }
        var currentPath: UIBezierPath = UIBezierPath()

        var previousCommand: PathCommand?
        var currentPathCommand: PathCommand = PathCommand(character: "M")
        var currentNumberStack: NumberStack = NumberStack()


        let pushCoordinateAndExecuteIfPossible: () -> SVGError? = {
            if currentNumberStack.isEmpty == false {
                if let newCoordinate = currentNumberStack.asCGFloat {
                    currentPathCommand.push(coordinate: newCoordinate)
                }
            }
            let error = currentPathCommand.executeIfPossible(previousCommand: previousCommand)
            if let error = error {
                return error
            } else {
                previousCommand = currentPathCommand
            }
            currentNumberStack.clear()
            return nil
        }
        let pushCoordinateAndClear: () -> Void = {
            if currentNumberStack.isEmpty == false {
                if let newCoordinate = currentNumberStack.asCGFloat {
                    currentPathCommand.push(coordinate: newCoordinate)
                }
                currentNumberStack.clear()
            }
            return
        }
        var firstCommand: PathCommand?
        var thisEnd: Bool = false
        for (index, thisCharacter) in workingString.enumerated() {

            thisEnd = false
            if let pathCharacter = getPathCharacter(char: thisCharacter) {

                if pathCharacter is PathCommand {

                    if let error = pushCoordinateAndExecuteIfPossible() {
                        if index > 0 {//игнорить для старта
                            return (path: nil, error: error)
                        }
                    }
                    currentPathCommand = pathCharacter as! PathCommand
                    currentPathCommand.path = currentPath
                    if firstCommand == nil {
                        firstCommand = currentPathCommand
                    }

                    if let closeCommand = currentPathCommand as? ClosePath {
                        if index == workingString.count - 1 {
                            closeCommand.firstCommand = firstCommand
                        }

                        if let error = closeCommand.execute(
                            forPath: currentPath, previousCommand: previousCommand) { return (nil, error) }
                        let currentPoint: CGPoint = currentPath.currentPoint
                        returnPath.append(currentPath)
                        currentPath = UIBezierPath()
                        currentPath.move(to: currentPoint)

                    }
                    if index == workingString.count - 1 {
                        thisEnd = true
                    }
                } else if pathCharacter is SeparatorCharacter {
                    pushCoordinateAndClear()
                } else if pathCharacter is SignCharacter && !currentNumberStack.isLastE {
                    pushCoordinateAndClear()
                    currentNumberStack = NumberStack(startCharacter: thisCharacter)
                } else {
                    if pathCharacter is NumberDelimiterCharacter && currentNumberStack.isHaveDelim == true {
                        pushCoordinateAndClear()

                    }

                    if currentNumberStack.isEmpty == false {
                        if currentNumberStack.characterStack == "0" && thisCharacter != "." {
                            pushCoordinateAndClear()
                        }
                        currentNumberStack.push(thisCharacter)
                    } else {
                        currentNumberStack = NumberStack(startCharacter: thisCharacter)
                    }
                }
            } else {
                returnPath.removeAllPoints()
                return (path: nil, error: SVGError.parseError(text: "Invalid character \"\(thisCharacter)\" found"))
            }
        }
        if thisEnd == false {
            if let error = pushCoordinateAndExecuteIfPossible() { return (path: nil, error: error) }
            returnPath.append(currentPath)
        }

        return (path: returnPath, error: nil)
    }
}
