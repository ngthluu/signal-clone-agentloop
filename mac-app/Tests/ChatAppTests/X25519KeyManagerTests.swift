import CryptoKit
import Foundation
import Security
import XCTest
@testable import ChatApp

final class X25519KeyManagerTests: XCTestCase {
    private let testStore = KeychainStore(
        service: "\(KeychainStore.defaultService).tests",
        account: "\(KeychainStore.defaultAccount).tests.x25519",
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

    func testX25519KeyRoundTripsThroughDistinctKeychainAccount() throws {
        let firstManager = X25519KeyManager(keychainStore: testStore)
        let firstKey = try firstManager.loadOrCreate()
        let firstPublicKeyBase64 = firstKey.publicKey.rawRepresentation.base64EncodedString()

        let relaunchedManager = X25519KeyManager(keychainStore: testStore)
        let relaunchedKey = try relaunchedManager.loadOrCreate()

        XCTAssertEqual(relaunchedKey.publicKey.rawRepresentation.base64EncodedString(), firstPublicKeyBase64)
        XCTAssertEqual(try relaunchedManager.publicKeyBase64(), firstPublicKeyBase64)
        XCTAssertTrue(testStore.account.hasSuffix(".x25519"))
    }

    func testLoadReturnsNilBeforeCreate() throws {
        let manager = X25519KeyManager(keychainStore: testStore)

        XCTAssertNil(try manager.load())
    }
}
