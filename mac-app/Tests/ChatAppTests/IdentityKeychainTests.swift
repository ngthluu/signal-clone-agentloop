import CryptoKit
import Foundation
import Security
import XCTest
@testable import ChatApp

final class IdentityKeychainTests: XCTestCase {
    private let testStore = KeychainStore(
        service: "\(KeychainStore.defaultService).tests",
        account: "\(KeychainStore.defaultAccount).tests",
        usesDataProtectionKeychain: false
    )

    override func setUpWithError() throws {
        try super.setUpWithError()
        try testStore.delete()
    }

    override func tearDownWithError() throws {
        try testStore.delete()
        try super.tearDownWithError()
    }

    func testIdentityRoundTripsThroughKeychainWithStablePublicKey() throws {
        let firstManager = IdentityManager(keychainStore: testStore)
        let firstIdentity = try firstManager.loadOrCreate()

        XCTAssertFalse(firstIdentity.publicKeyBase64.isEmpty)

        let relaunchedManager = IdentityManager(keychainStore: testStore)
        let relaunchedIdentity = try relaunchedManager.loadOrCreate()

        XCTAssertEqual(relaunchedIdentity.publicKeyBase64, firstIdentity.publicKeyBase64)
    }

    func testPrivateKeyIsReachableViaKeychainAPI() throws {
        let manager = IdentityManager(keychainStore: testStore)
        let identity = try manager.loadOrCreate()

        let privateKeyData = try readPrivateKeyDataFromKeychain()
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData)
        let recoveredPublicKeyBase64 = privateKey.publicKey.rawRepresentation.base64EncodedString()

        XCTAssertEqual(recoveredPublicKeyBase64, identity.publicKeyBase64)
    }

    func testDeletingKeychainItemMakesIdentityUnrecoverable() throws {
        let manager = IdentityManager(keychainStore: testStore)
        let identity = try manager.loadOrCreate()

        try testStore.delete()

        XCTAssertNil(try manager.load())

        let replacementIdentity = try IdentityManager(keychainStore: testStore).loadOrCreate()
        XCTAssertNotEqual(replacementIdentity.publicKeyBase64, identity.publicKeyBase64)
    }

    func testIdentityExposesNoRawPrivateBytes() throws {
        let identity = CryptoIdentity(privateKey: Curve25519.Signing.PrivateKey())

        XCTAssertFalse(identity.publicKeyBase64.isEmpty)
    }

    private func readPrivateKeyDataFromKeychain() throws -> Data {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: testStore.service,
            kSecAttrAccount as String: testStore.account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
        if testStore.usesDataProtectionKeychain {
            query[kSecUseDataProtectionKeychain as String] = true
        }

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw KeychainError.unexpectedData
            }
            return data
        default:
            throw KeychainError.unhandledStatus(status)
        }
    }
}
