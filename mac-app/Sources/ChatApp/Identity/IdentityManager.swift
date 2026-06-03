import CryptoKit
import Foundation

struct IdentityManager {
    private let keychainStore: KeychainStore

    init(keychainStore: KeychainStore = KeychainStore()) {
        self.keychainStore = keychainStore
    }

    func loadOrCreate() throws -> CryptoIdentity {
        if let identity = try load() {
            return identity
        }

        let privateKey = Curve25519.Signing.PrivateKey()
        try keychainStore.save(privateKey.rawRepresentation)
        return CryptoIdentity(privateKey: privateKey)
    }

    func load() throws -> CryptoIdentity? {
        guard let privateKeyData = try keychainStore.load() else {
            return nil
        }

        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData)
        return CryptoIdentity(privateKey: privateKey)
    }

    func reset() throws {
        try keychainStore.delete()
    }
}
