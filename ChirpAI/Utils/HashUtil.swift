import Foundation
import CryptoKit

struct HashUtil {
    static func md5(_ string: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }

    static func hashUInt8(_ index: Int, _ hash: Int) -> UInt8 {
        UInt8((hash >> (index * 8)) & 0xFF)
    }
}
