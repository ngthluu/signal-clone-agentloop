import CryptoKit
import Foundation

enum MessageCryptoError: Error, Equatable {
    case invalidBase64
    case invalidEnvelope
    case unsupportedVersion(UInt8)
    case decryptFailed
}

struct MessageCrypto {
    private static let version: UInt8 = 0x01
    private static let ephemeralPublicKeyByteCount = 32
    private static let sharedInfo = Data("chatapp-dm-v1".utf8)

    func encrypt(_ plaintext: Data, toRecipientX25519 recipientPubBase64: String) throws -> String {
        guard let recipientPublicKeyData = Data(base64Encoded: recipientPubBase64) else {
            throw MessageCryptoError.invalidBase64
        }

        let recipientPublicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: recipientPublicKeyData)
        let ephemeralPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        let sharedSecret = try ephemeralPrivateKey.sharedSecretFromKeyAgreement(with: recipientPublicKey)
        let symmetricKey = Self.deriveSymmetricKey(from: sharedSecret)
        let sealedBox = try AES.GCM.seal(plaintext, using: symmetricKey)

        guard let combined = sealedBox.combined else {
            throw MessageCryptoError.invalidEnvelope
        }

        var envelope = Data([Self.version])
        envelope.append(ephemeralPrivateKey.publicKey.rawRepresentation)
        envelope.append(combined)
        return envelope.base64EncodedString()
    }

    func decrypt(_ envelopeBase64: String, withLocalX25519 localPrivate: Curve25519.KeyAgreement.PrivateKey) throws -> Data {
        guard let envelope = Data(base64Encoded: envelopeBase64) else {
            throw MessageCryptoError.invalidBase64
        }

        guard envelope.count > 1 + Self.ephemeralPublicKeyByteCount else {
            throw MessageCryptoError.invalidEnvelope
        }

        let version = envelope[envelope.startIndex]
        guard version == Self.version else {
            throw MessageCryptoError.unsupportedVersion(version)
        }

        let publicKeyStart = envelope.index(after: envelope.startIndex)
        let publicKeyEnd = envelope.index(publicKeyStart, offsetBy: Self.ephemeralPublicKeyByteCount)
        let ephemeralPublicKeyData = envelope[publicKeyStart..<publicKeyEnd]
        let combined = envelope[publicKeyEnd..<envelope.endIndex]

        do {
            let ephemeralPublicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: Data(ephemeralPublicKeyData))
            let sharedSecret = try localPrivate.sharedSecretFromKeyAgreement(with: ephemeralPublicKey)
            let symmetricKey = Self.deriveSymmetricKey(from: sharedSecret)
            let sealedBox = try AES.GCM.SealedBox(combined: Data(combined))
            return try AES.GCM.open(sealedBox, using: symmetricKey)
        } catch {
            throw MessageCryptoError.decryptFailed
        }
    }

    func signPrekey(x25519PublicKeyBase64: String, with identity: CryptoIdentity) -> String {
        let publicKeyData = Data(base64Encoded: x25519PublicKeyBase64)!
        return identity.sign(publicKeyData).base64EncodedString()
    }

    static func verifyPrekey(
        x25519PublicKeyBase64: String,
        signatureBase64: String,
        identityPublicKeyBase64: String
    ) -> Bool {
        guard
            let prekeyData = Data(base64Encoded: x25519PublicKeyBase64),
            let signatureData = Data(base64Encoded: signatureBase64),
            let identityPublicKeyData = Data(base64Encoded: identityPublicKeyBase64),
            let identityPublicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: identityPublicKeyData)
        else {
            return false
        }

        return identityPublicKey.isValidSignature(signatureData, for: prekeyData)
    }

    private static func deriveSymmetricKey(from sharedSecret: SharedSecret) -> SymmetricKey {
        sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: sharedInfo,
            outputByteCount: 32
        )
    }
}
