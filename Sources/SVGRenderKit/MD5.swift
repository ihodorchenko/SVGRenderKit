import Foundation
import CryptoKit

/// Computes the MD5 hash of the given string and returns it as an uppercase hexadecimal string.
/// - Parameter input: The string to hash.
/// - Returns: The 32-character hexadecimal MD5 digest.
public func MD5(_ input: String) -> String {
    return MD5(Array(input.utf8))
}

/// Computes the MD5 hash of the given bytes and returns it as an uppercase hexadecimal string.
/// - Parameter bytes: The raw bytes to hash.
/// - Returns: The 32-character hexadecimal MD5 digest.
public func MD5(_ bytes: [UInt8]) -> String {
    return Insecure.MD5.hash(data: Data(bytes))
        .map { String(format: "%02X", $0) }
        .joined()
}
