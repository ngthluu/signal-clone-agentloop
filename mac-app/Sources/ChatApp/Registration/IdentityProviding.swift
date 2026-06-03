import Foundation

protocol IdentityProviding {
    func loadOrCreate() throws -> CryptoIdentity
}

extension IdentityManager: IdentityProviding {}
