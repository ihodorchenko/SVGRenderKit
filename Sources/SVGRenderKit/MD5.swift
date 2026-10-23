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
