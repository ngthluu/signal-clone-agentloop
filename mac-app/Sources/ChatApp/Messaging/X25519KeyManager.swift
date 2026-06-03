import CryptoKit
import Foundation

struct X25519KeyManager {
    private let keychainStore: KeychainStore

    init(
        keychainStore: KeychainStore = KeychainStore(account: "\(KeychainStore.defaultAccount).x25519")
    ) {
        self.keychainStore = keychainStore
    }

    func loadOrCreate() throws -> Curve25519.KeyAgreement.PrivateKey {
        if let privateKey = try load() {
            return privateKey
        }

        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        try keychainStore.save(privateKey.rawRepresentation)
        return privateKey
    }

    func load() throws -> Curve25519.KeyAgreement.PrivateKey? {
        guard let privateKeyData = try keychainStore.load() else {
            return nil
        }

        return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKeyData)
    }

    func publicKeyBase64() throws -> String {
        try loadOrCreate().publicKey.rawRepresentation.base64EncodedString()
    }
}
