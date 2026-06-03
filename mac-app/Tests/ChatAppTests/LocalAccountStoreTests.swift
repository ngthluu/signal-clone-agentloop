import XCTest
@testable import ChatApp

final class LocalAccountStoreTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testSaveRoundTripsCurrentAccountAndHasAccount() throws {
        let store = LocalAccountStore(directory: temporaryDirectory)
        let account = LocalAccount(
            username: "alice",
            publicKeyBase64: "public-key",
            userId: "user-1"
        )

        XCTAssertFalse(store.hasAccount)
        XCTAssertNil(store.currentAccount())

        try store.save(account)

        XCTAssertTrue(store.hasAccount)
        XCTAssertEqual(store.currentAccount(), account)
    }

    func testFreshStoreInSameDirectoryLoadsPersistedAccount() throws {
        let account = LocalAccount(
            username: "alice",
            publicKeyBase64: "public-key",
            userId: "user-1"
        )
        try LocalAccountStore(directory: temporaryDirectory).save(account)

        let relaunchedStore = LocalAccountStore(directory: temporaryDirectory)

        XCTAssertTrue(relaunchedStore.hasAccount)
        XCTAssertEqual(relaunchedStore.currentAccount(), account)
    }

    func testAccountFileContainsOnlyPublicAccountMaterial() throws {
        let store = LocalAccountStore(directory: temporaryDirectory)
        try store.save(LocalAccount(
            username: "alice",
            publicKeyBase64: "public-key",
            userId: "user-1"
        ))

        let accountFile = temporaryDirectory.appendingPathComponent("account.json")
        let data = try Data(contentsOf: accountFile)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(Set(object.keys), ["username", "publicKeyBase64", "userId"])

        let fileText = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(fileText.localizedCaseInsensitiveContains("private"))
        XCTAssertFalse(fileText.localizedCaseInsensitiveContains("secret"))
    }

    func testClearRemovesPersistedAccount() throws {
        let store = LocalAccountStore(directory: temporaryDirectory)
        try store.save(LocalAccount(
            username: "alice",
            publicKeyBase64: "public-key",
            userId: "user-1"
        ))

        try store.clear()

        XCTAssertFalse(store.hasAccount)
        XCTAssertNil(store.currentAccount())
    }
}
