import CryptoKit
import Foundation

enum FileCryptoError: Error, Equatable {
    case decryptFailed
}

struct FileCrypto {
    func newFileKey() -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }

    func encrypt(_ data: Data, using key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.seal(data, using: key)
        guard let combined = sealedBox.combined else {
            throw FileCryptoError.decryptFailed
        }
        return combined
    }

    func decrypt(_ blob: Data, using key: SymmetricKey) throws -> Data {
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: blob)
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            throw FileCryptoError.decryptFailed
        }
    }
}
