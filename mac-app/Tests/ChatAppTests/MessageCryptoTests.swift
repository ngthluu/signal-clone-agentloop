import CryptoKit
import Foundation
import XCTest
@testable import ChatApp

final class MessageCryptoTests: XCTestCase {
    func testEncryptDecryptRoundTripsToExactPlaintext() throws {
        let crypto = MessageCrypto()
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        let plaintext = Data("hello encrypted dm".utf8)

        let envelope = try crypto.encrypt(
            plaintext,
            toRecipientX25519: recipient.publicKey.rawRepresentation.base64EncodedString()
        )

        let decrypted = try crypto.decrypt(envelope, withLocalX25519: recipient)
        XCTAssertEqual(decrypted, plaintext)
    }

    func testTamperedEnvelopeThrows() throws {
        let crypto = MessageCrypto()
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        let envelope = try crypto.encrypt(
            Data("do not accept edits".utf8),
            toRecipientX25519: recipient.publicKey.rawRepresentation.base64EncodedString()
        )
        var bytes = try XCTUnwrap(Data(base64Encoded: envelope))
        bytes[bytes.count - 1] ^= 0x01

        XCTAssertThrowsError(try crypto.decrypt(bytes.base64EncodedString(), withLocalX25519: recipient))
    }

    func testThirdPartyCannotDecrypt() throws {
        let crypto = MessageCrypto()
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        let thirdParty = Curve25519.KeyAgreement.PrivateKey()
        let envelope = try crypto.encrypt(
            Data("recipient only".utf8),
            toRecipientX25519: recipient.publicKey.rawRepresentation.base64EncodedString()
        )

        XCTAssertThrowsError(try crypto.decrypt(envelope, withLocalX25519: thirdParty))
    }

    func testSamePlaintextEncryptsToDifferentEnvelopes() throws {
        let crypto = MessageCrypto()
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        let recipientPublic = recipient.publicKey.rawRepresentation.base64EncodedString()
        let plaintext = Data("same plaintext".utf8)

        let first = try crypto.encrypt(plaintext, toRecipientX25519: recipientPublic)
        let second = try crypto.encrypt(plaintext, toRecipientX25519: recipientPublic)

        XCTAssertNotEqual(first, second)
    }

    func testEnvelopeBytesDoNotContainPlaintext() throws {
        let crypto = MessageCrypto()
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        let plaintext = Data("PLAINTEXT_SENTINEL_crypto_test".utf8)

        let envelope = try crypto.encrypt(
            plaintext,
            toRecipientX25519: recipient.publicKey.rawRepresentation.base64EncodedString()
        )
        let envelopeBytes = try XCTUnwrap(Data(base64Encoded: envelope))

        XCTAssertNil(envelopeBytes.range(of: plaintext))
        XCTAssertEqual(envelopeBytes.first, 0x01)
        XCTAssertGreaterThan(envelopeBytes.count, 1 + 32 + 12 + 16)
    }

    func testPrekeySignatureVerifiesAndRejectsTampering() throws {
        let crypto = MessageCrypto()
        let identity = CryptoIdentity(privateKey: Curve25519.Signing.PrivateKey())
        let prekey = Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation
        let prekeyBase64 = prekey.base64EncodedString()

        let signature = crypto.signPrekey(x25519PublicKeyBase64: prekeyBase64, with: identity)

        XCTAssertTrue(MessageCrypto.verifyPrekey(
            x25519PublicKeyBase64: prekeyBase64,
            signatureBase64: signature,
            identityPublicKeyBase64: identity.publicKeyBase64
        ))

        var tamperedPrekey = prekey
        tamperedPrekey[0] ^= 0x01
        XCTAssertFalse(MessageCrypto.verifyPrekey(
            x25519PublicKeyBase64: tamperedPrekey.base64EncodedString(),
            signatureBase64: signature,
            identityPublicKeyBase64: identity.publicKeyBase64
        ))

        var signatureBytes = try XCTUnwrap(Data(base64Encoded: signature))
        signatureBytes[0] ^= 0x01
        XCTAssertFalse(MessageCrypto.verifyPrekey(
            x25519PublicKeyBase64: prekeyBase64,
            signatureBase64: signatureBytes.base64EncodedString(),
            identityPublicKeyBase64: identity.publicKeyBase64
        ))
    }
}
