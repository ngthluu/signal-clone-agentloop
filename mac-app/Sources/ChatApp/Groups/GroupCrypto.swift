import CryptoKit
import Foundation

enum GroupCryptoError: Error, Equatable {
    case invalidBase64
    case invalidEnvelope
    case unsupportedVersion(UInt8)
    case decryptFailed
}

struct GroupCrypto {
    private static let version: UInt8 = 0x02
    private static let epochByteCount = 4

    func newGroupKey() -> Data {
        let key = SymmetricKey(size: .bits256)
        return key.withUnsafeBytes { Data($0) }
    }

    func wrapGroupKey(_ key: Data, toRecipientX25519 prekeyBase64: String) throws -> String {
        try MessageCrypto().encrypt(key, toRecipientX25519: prekeyBase64)
    }

    func unwrapGroupKey(
        _ wrappedBase64: String,
        withLocalX25519 priv: Curve25519.KeyAgreement.PrivateKey
    ) throws -> Data {
        try MessageCrypto().decrypt(wrappedBase64, withLocalX25519: priv)
    }

    func encryptGroupMessage(_ plaintext: Data, epoch: UInt32, groupKey: Data) throws -> String {
        let symmetricKey = SymmetricKey(data: groupKey)
        let sealedBox = try AES.GCM.seal(plaintext, using: symmetricKey)

        guard let combined = sealedBox.combined else {
            throw GroupCryptoError.invalidEnvelope
        }

        var envelope = Data([Self.version])
        var bigEndianEpoch = epoch.bigEndian
        withUnsafeBytes(of: &bigEndianEpoch) { epochBytes in
            envelope.append(contentsOf: epochBytes)
        }
        envelope.append(combined)
        return envelope.base64EncodedString()
    }

    func messageEpoch(of envelopeBase64: String) throws -> UInt32 {
        let envelope = try decodeEnvelope(envelopeBase64)
        let epochStart = envelope.index(after: envelope.startIndex)
        let epochEnd = envelope.index(epochStart, offsetBy: Self.epochByteCount)
        return envelope[epochStart..<epochEnd].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    func decryptGroupMessage(_ envelopeBase64: String, groupKey: Data) throws -> Data {
        let envelope = try decodeEnvelope(envelopeBase64)
        let combinedStart = envelope.index(envelope.startIndex, offsetBy: 1 + Self.epochByteCount)
        let combined = envelope[combinedStart..<envelope.endIndex]

        do {
            let sealedBox = try AES.GCM.SealedBox(combined: Data(combined))
            return try AES.GCM.open(sealedBox, using: SymmetricKey(data: groupKey))
        } catch {
            throw GroupCryptoError.decryptFailed
        }
    }

    private func decodeEnvelope(_ envelopeBase64: String) throws -> Data {
        guard let envelope = Data(base64Encoded: envelopeBase64) else {
            throw GroupCryptoError.invalidBase64
        }

        guard envelope.count >= 1 + Self.epochByteCount else {
            throw GroupCryptoError.invalidEnvelope
        }

        let version = envelope[envelope.startIndex]
        guard version == Self.version else {
            throw GroupCryptoError.unsupportedVersion(version)
        }

        return envelope
    }
}
