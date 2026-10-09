import UIKit

/// Utility functions for string processing and hashing used throughout the library.
open class SVGUtils {

    /// Trims white space and new line characters, returns a new string.
    open class func trimmed(string: String) -> String {
        return string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Splits a string by a substring separator, omitting empty components.
    open class func split(string: String, separator: String) -> [String] {
        return string.components(separatedBy: separator).filter {
            !trimmed(string: $0).isEmpty
        }
    }

    /// Splits a string by the characters in a character set, omitting empty components.
    open class func split(string: String, separatorSet: CharacterSet) -> [String] {
        return string.components(separatedBy: separatorSet).filter {
            !trimmed(string: $0).isEmpty
        }
    }

    /// Computes the MD5 hash of the given string.
    /// - returns: The MD5 digest as a hexadecimal string.
    open class func md5(_ string: String) -> String {
        return MD5(string)
    }
}
