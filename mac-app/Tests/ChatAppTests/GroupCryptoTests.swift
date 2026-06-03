import CryptoKit
import Foundation
import XCTest
@testable import ChatApp

final class GroupCryptoTests: XCTestCase {
    func testNewGroupKeyIsThirtyTwoBytes() {
        let key = GroupCrypto().newGroupKey()

        XCTAssertEqual(key.count, 32)
    }

    func testWrapAndUnwrapGroupKeyRoundTripsToExactBytes() throws {
        let crypto = GroupCrypto()
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        let groupKey = crypto.newGroupKey()

        let wrapped = try crypto.wrapGroupKey(
            groupKey,
            toRecipientX25519: recipient.publicKey.rawRepresentation.base64EncodedString()
        )
        let unwrapped = try crypto.unwrapGroupKey(wrapped, withLocalX25519: recipient)

        XCTAssertEqual(unwrapped, groupKey)
        XCTAssertEqual(Data(base64Encoded: wrapped)?.first, 0x01)
    }

    func testThirdPartyCannotUnwrapGroupKey() throws {
        let crypto = GroupCrypto()
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        let thirdParty = Curve25519.KeyAgreement.PrivateKey()
        let wrapped = try crypto.wrapGroupKey(
            crypto.newGroupKey(),
            toRecipientX25519: recipient.publicKey.rawRepresentation.base64EncodedString()
        )

        XCTAssertThrowsError(try crypto.unwrapGroupKey(wrapped, withLocalX25519: thirdParty))
    }

    func testEncryptDecryptGroupMessageRoundTripsToExactPlaintext() throws {
        let crypto = GroupCrypto()
        let groupKey = crypto.newGroupKey()
        let plaintext = Data("hello encrypted group".utf8)

        let envelope = try crypto.encryptGroupMessage(plaintext, epoch: 7, groupKey: groupKey)
        let decrypted = try crypto.decryptGroupMessage(envelope, groupKey: groupKey)

        XCTAssertEqual(decrypted, plaintext)
    }

    func testWrongGroupKeyFailsToDecryptGroupMessage() throws {
        let crypto = GroupCrypto()
        let envelope = try crypto.encryptGroupMessage(
            Data("wrong key must fail".utf8),
            epoch: 1,
            groupKey: crypto.newGroupKey()
        )

        XCTAssertThrowsError(try crypto.decryptGroupMessage(envelope, groupKey: crypto.newGroupKey()))
    }

    func testMessageEpochRecoversEmbeddedBigEndianEpoch() throws {
        let crypto = GroupCrypto()
        let epoch: UInt32 = 0x01020304

        let envelope = try crypto.encryptGroupMessage(
            Data("epoch sentinel".utf8),
            epoch: epoch,
            groupKey: crypto.newGroupKey()
        )
        let decoded = try XCTUnwrap(Data(base64Encoded: envelope))

        XCTAssertEqual(try crypto.messageEpoch(of: envelope), epoch)
        XCTAssertEqual(decoded[0], 0x02)
        XCTAssertEqual(Array(decoded[1...4]), [0x01, 0x02, 0x03, 0x04])
    }

    func testMessageEnvelopeDoesNotContainPlaintextBytes() throws {
        let crypto = GroupCrypto()
        let plaintext = Data("GROUP_PLAINTEXT_SENTINEL_crypto_test".utf8)

        let envelope = try crypto.encryptGroupMessage(plaintext, epoch: 0, groupKey: crypto.newGroupKey())
        let decoded = try XCTUnwrap(Data(base64Encoded: envelope))

        XCTAssertEqual(decoded.first, 0x02)
        XCTAssertNil(decoded.range(of: plaintext))
        XCTAssertGreaterThan(decoded.count, 1 + 4 + 12 + 16)
    }

    func testSamePlaintextEncryptedTwiceProducesDifferentEnvelopes() throws {
        let crypto = GroupCrypto()
        let groupKey = crypto.newGroupKey()
        let plaintext = Data("same group plaintext".utf8)

        let first = try crypto.encryptGroupMessage(plaintext, epoch: 2, groupKey: groupKey)
        let second = try crypto.encryptGroupMessage(plaintext, epoch: 2, groupKey: groupKey)

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try crypto.decryptGroupMessage(first, groupKey: groupKey), plaintext)
        XCTAssertEqual(try crypto.decryptGroupMessage(second, groupKey: groupKey), plaintext)
    }

    func testInvalidGroupEnvelopeErrorsAreStable() throws {
        let crypto = GroupCrypto()

        XCTAssertThrowsError(try crypto.messageEpoch(of: "not-base64")) { error in
            XCTAssertEqual(error as? GroupCryptoError, .invalidBase64)
        }

        XCTAssertThrowsError(try crypto.messageEpoch(of: Data([0x02, 0x00]).base64EncodedString())) { error in
            XCTAssertEqual(error as? GroupCryptoError, .invalidEnvelope)
        }

        XCTAssertThrowsError(try crypto.messageEpoch(of: Data([0x01, 0, 0, 0, 0]).base64EncodedString())) { error in
            XCTAssertEqual(error as? GroupCryptoError, .unsupportedVersion(0x01))
        }
    }
}
