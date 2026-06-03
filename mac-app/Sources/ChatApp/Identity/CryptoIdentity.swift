import CryptoKit
import Foundation

struct CryptoIdentity {
    private let privateKey: Curve25519.Signing.PrivateKey

    var publicKeyBase64: String {
        privateKey.publicKey.rawRepresentation.base64EncodedString()
    }

    init(privateKey: Curve25519.Signing.PrivateKey) {
        self.privateKey = privateKey
    }

    func sign(_ data: Data) -> Data {
        try! privateKey.signature(for: data)
    }
}
