import CryptoKit
import Foundation
import XCTest
@testable import ChatApp

final class FileCryptoTests: XCTestCase {
    func testEncryptDecryptRoundTripReturnsExactBytesForSmallPayload() throws {
        let crypto = FileCrypto()
        let key = crypto.newFileKey()
        let plaintext = Data("small attachment payload".utf8)

        let encrypted = try crypto.encrypt(plaintext, using: key)
        let decrypted = try crypto.decrypt(encrypted, using: key)

        XCTAssertEqual(decrypted, plaintext)
    }

    func testEncryptDecryptRoundTripReturnsExactBytesForBinaryPayload() throws {
        let crypto = FileCrypto()
        let key = crypto.newFileKey()
        let plaintext = Data([0x00, 0x01, 0x02, 0xff, 0x7f, 0x80, 0x00, 0xff])

        let encrypted = try crypto.encrypt(plaintext, using: key)
        let decrypted = try crypto.decrypt(encrypted, using: key)

        XCTAssertEqual(decrypted, plaintext)
    }

    func testNearTenMegabyteFileRoundTrips() throws {
        let crypto = FileCrypto()
        let key = crypto.newFileKey()
        let plaintext = randomData(byteCount: 10 * 1024 * 1024)

        let encrypted = try crypto.encrypt(plaintext, using: key)
        let decrypted = try crypto.decrypt(encrypted, using: key)

        XCTAssertEqual(decrypted, plaintext)
    }

    func testWrongKeyFailsToDecrypt() throws {
        let crypto = FileCrypto()
        let plaintext = Data("wrong key must fail".utf8)
        let encrypted = try crypto.encrypt(plaintext, using: crypto.newFileKey())

        XCTAssertThrowsError(try crypto.decrypt(encrypted, using: crypto.newFileKey())) { error in
            XCTAssertEqual(error as? FileCryptoError, .decryptFailed)
        }
    }

    func testTamperedBlobThrows() throws {
        let crypto = FileCrypto()
        let key = crypto.newFileKey()
        var encrypted = try crypto.encrypt(Data("tamper must fail".utf8), using: key)
        encrypted[encrypted.index(encrypted.startIndex, offsetBy: encrypted.count / 2)] ^= 0x01

        XCTAssertThrowsError(try crypto.decrypt(encrypted, using: key)) { error in
            XCTAssertEqual(error as? FileCryptoError, .decryptFailed)
        }
    }

    func testEncryptedBlobDoesNotContainPlaintextBytes() throws {
        let crypto = FileCrypto()
        let sentinel = Data("FILE_ATTACHMENT_PLAINTEXT_SENTINEL".utf8)
        let plaintext = Data("prefix ".utf8) + sentinel + Data(" suffix".utf8)

        let encrypted = try crypto.encrypt(plaintext, using: crypto.newFileKey())

        XCTAssertNil(encrypted.range(of: sentinel))
        XCTAssertEqual(encrypted.count, plaintext.count + 12 + 16)
    }

    private func randomData(byteCount: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }
}
