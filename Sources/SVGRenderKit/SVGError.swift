import UIKit

/// Errors thrown while parsing or rendering SVG content.
public enum SVGError: Error, LocalizedError {
    /// The SVG markup could not be parsed.
    case parseError(text: String)
    /// An unexpected error occurred during processing.
    case unexpectedError(text: String)
    /// The SVG content is invalid or unsupported.
    case content(text: String)

    /// A human-readable description of the error.
    public var description: String {
        switch self {
        case .parseError(let text):
            return "ParseError: \(text)"
        case .unexpectedError(let text):
            return "UnexpectedError: \(text)"
        case .content(let text):
            return "ContentError: \(text)"
        }
    }

    /// A localized description of the error.
    public var localizedDescription: String {
        return self.description
    }

    /// The localized description used by the `LocalizedError` protocol.
    public var errorDescription: String? {
        return self.description
    }
}

/// A destination for library diagnostics.
public protocol SVGLogger {
    /// Logs a diagnostic message.
    func log(_ message: String)
}

/// Logs messages to the console via `print`.
public struct PrintSVGLogger: SVGLogger {
    public init() {}

    public func log(_ message: String) {
        print(message)
    }
}

/// Central logging facade for the library.
public class SVGLog {
    /// The active logger. Defaults to `PrintSVGLogger`.
    public static var logger: SVGLogger = PrintSVGLogger()

    class func addLog(svgError: SVGError) {
        logger.log("Error SVG: \(svgError.description)")
    }

    class func addSLog(errorStr: String) {
        logger.log("Error SVG: \(errorStr)")
    }
}
