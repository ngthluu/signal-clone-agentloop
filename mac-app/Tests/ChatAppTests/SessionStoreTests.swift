import Foundation
import XCTest
@testable import ChatApp

final class SessionStoreTests: XCTestCase {
    private let keychainStore = KeychainStore(
        service: "\(KeychainStore.defaultService).tests",
        account: "\(KeychainStore.defaultAccount).session.tests",
        usesDataProtectionKeychain: false
    )

    override func setUpWithError() throws {
        try super.setUpWithError()
        try keychainStore.delete()
    }

    override func tearDownWithError() throws {
        try keychainStore.delete()
        try super.tearDownWithError()
    }

    func testSessionTokenRoundTripsThroughKeychainAndCanBeCleared() throws {
        let store = SessionStore(keychainStore: keychainStore)

        XCTAssertNil(store.load())

        try store.save("token-1")
        XCTAssertEqual(store.load(), "token-1")

        try store.clear()
        XCTAssertNil(store.load())
    }

    func testFreshSessionStoreLoadsPersistedTokenFromSameKeychainAccount() throws {
        let firstStore = SessionStore(keychainStore: keychainStore)
        try firstStore.save("persisted-token")

        let relaunchedStore = SessionStore(keychainStore: keychainStore)

        XCTAssertEqual(relaunchedStore.load(), "persisted-token")
    }

    func testClearRemovesTokenForFreshSessionStore() throws {
        let firstStore = SessionStore(keychainStore: keychainStore)
        try firstStore.save("token-1")

        let clearingStore = SessionStore(keychainStore: keychainStore)
        try clearingStore.clear()

        XCTAssertNil(SessionStore(keychainStore: keychainStore).load())
    }
}
