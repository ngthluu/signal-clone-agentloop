import CryptoKit
import XCTest
@testable import ChatApp

final class LiveRegistrationE2ETests: XCTestCase {
    @MainActor
    func testLiveRegistrationPersistsAccountAndDuplicateShowsTakenError() async throws {
        let backendURLString = ProcessInfo.processInfo.environment["CHATAPP_LIVE_BACKEND_URL"]
        try XCTSkipUnless(backendURLString != nil, "CHATAPP_LIVE_BACKEND_URL is not set")

        guard let backendURLString, let backendURL = URL(string: backendURLString) else {
            XCTFail("CHATAPP_LIVE_BACKEND_URL is not a valid URL")
            return
        }

        let usernameSuffix = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(20))
        let username = "live_\(usernameSuffix)"
        let identity = CryptoIdentity(privateKey: Curve25519.Signing.PrivateKey())
        let client = HTTPRegistrationClient(baseURL: backendURL)

        let successfulStore = LocalAccountStore(directory: try makeTemporaryDirectory())
        let successfulCoordinator = RegistrationCoordinator(
            identityProvider: StubLiveIdentityProvider(identity: identity),
            service: client,
            accountStore: successfulStore
        )

        await successfulCoordinator.register(username: username)

        XCTAssertTrue(successfulCoordinator.isRegistered)
        XCTAssertTrue(successfulCoordinator.statusMessage.isEmpty)
        let account = try XCTUnwrap(successfulStore.currentAccount())
        XCTAssertEqual(account.username, username)
        XCTAssertEqual(account.publicKeyBase64, identity.publicKeyBase64)
        XCTAssertFalse(account.userId.isEmpty)

        let duplicateStore = LocalAccountStore(directory: try makeTemporaryDirectory())
        let duplicateCoordinator = RegistrationCoordinator(
            identityProvider: StubLiveIdentityProvider(identity: identity),
            service: client,
            accountStore: duplicateStore
        )

        await duplicateCoordinator.register(username: username)

        XCTAssertFalse(duplicateCoordinator.isRegistered)
        XCTAssertTrue(duplicateCoordinator.statusMessage.localizedCaseInsensitiveContains("taken"))
        XCTAssertNil(duplicateStore.currentAccount())
    }

    private func makeTemporaryDirectory() throws -> URL {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        return temporaryDirectory
    }
}

private struct StubLiveIdentityProvider: IdentityProviding {
    let identity: CryptoIdentity

    func loadOrCreate() throws -> CryptoIdentity {
        identity
    }
}
