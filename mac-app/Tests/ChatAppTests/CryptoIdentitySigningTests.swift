import CryptoKit
import Foundation
import XCTest
@testable import ChatApp

final class CryptoIdentitySigningTests: XCTestCase {
    func testSignProducesVerifiableSignatureAndRejectsTamperedMessage() throws {
        let identity = CryptoIdentity(privateKey: Curve25519.Signing.PrivateKey())
        let message = Data("server nonce".utf8)

        let signature = identity.sign(message)

        XCTAssertEqual(signature.count, 64)

        let publicKeyData = try XCTUnwrap(Data(base64Encoded: identity.publicKeyBase64))
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
        XCTAssertTrue(publicKey.isValidSignature(signature, for: message))
        XCTAssertFalse(publicKey.isValidSignature(signature, for: Data("tampered nonce".utf8)))
    }
}
