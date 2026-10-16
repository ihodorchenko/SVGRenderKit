import Foundation
import CryptoKit

/// Uppercase hexadecimal MD5 of `bytes`: a cache key, not a security primitive.
func md5Hex(_ bytes: [UInt8]) -> String {
    return Insecure.MD5.hash(data: Data(bytes))
        .map { String(format: "%02X", $0) }
        .joined()
}

func md5Hex(_ input: String) -> String {
    return md5Hex(Array(input.utf8))
}

/// Computes the MD5 hash of the given string and returns it as an uppercase hexadecimal string.
@available(*, deprecated, message: "An implementation detail of the parser cache; use CryptoKit or `SVGUtils.md5(_:)`.")
public func MD5(_ input: String) -> String {
    return md5Hex(input)
}

/// Computes the MD5 hash of the given bytes and returns it as an uppercase hexadecimal string.
@available(*, deprecated, message: "An implementation detail of the parser cache; use CryptoKit or `SVGUtils.md5(_:)`.")
public func MD5(_ bytes: [UInt8]) -> String {
    return md5Hex(bytes)
}
