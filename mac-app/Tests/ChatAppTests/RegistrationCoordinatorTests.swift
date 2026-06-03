import CryptoKit
import XCTest
@testable import ChatApp

final class RegistrationCoordinatorTests: XCTestCase {
    @MainActor
    func testSuccessfulRegistrationPersistsAccountAndMarksRegistered() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        let identity = CryptoIdentity(privateKey: Curve25519.KeyAgreement.PrivateKey())
        let store = LocalAccountStore(directory: temporaryDirectory)
        let service = FakeRegistrationService(result: .success(userId: "user-1"))
        let coordinator = RegistrationCoordinator(
            identityProvider: StubIdentityProvider(identity: identity),
            service: service,
            accountStore: store
        )

        await coordinator.register(username: " alice ")

        XCTAssertTrue(coordinator.isRegistered)
        XCTAssertTrue(coordinator.statusMessage.isEmpty)
        XCTAssertEqual(service.requests, [
            RegistrationRequest(username: "alice", publicKeyBase64: identity.publicKeyBase64)
        ])
        XCTAssertEqual(store.currentAccount(), LocalAccount(
            username: "alice",
            publicKeyBase64: identity.publicKeyBase64,
            userId: "user-1"
        ))
    }

    @MainActor
    func testUsernameTakenShowsClearErrorAndDoesNotPersistAccount() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        let store = LocalAccountStore(directory: temporaryDirectory)
        let coordinator = RegistrationCoordinator(
            identityProvider: StubIdentityProvider(),
            service: FakeRegistrationService(result: .usernameTaken),
            accountStore: store
        )

        await coordinator.register(username: "alice")

        XCTAssertFalse(coordinator.isRegistered)
        XCTAssertFalse(coordinator.statusMessage.isEmpty)
        XCTAssertTrue(coordinator.statusMessage.localizedCaseInsensitiveContains("taken"))
        XCTAssertNil(store.currentAccount())
    }

    @MainActor
    func testExistingAccountMarksCoordinatorRegisteredAtInit() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        let store = LocalAccountStore(directory: temporaryDirectory)
        try store.save(LocalAccount(
            username: "alice",
            publicKeyBase64: "public-key",
            userId: "user-1"
        ))

        let coordinator = RegistrationCoordinator(
            identityProvider: StubIdentityProvider(),
            service: FakeRegistrationService(result: .failure("unused")),
            accountStore: store
        )

        XCTAssertTrue(coordinator.isRegistered)
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

private struct RegistrationRequest: Equatable {
    let username: String
    let publicKeyBase64: String
}

private struct StubIdentityProvider: IdentityProviding {
    let identity: CryptoIdentity

    init(identity: CryptoIdentity = CryptoIdentity(privateKey: Curve25519.KeyAgreement.PrivateKey())) {
        self.identity = identity
    }

    func loadOrCreate() throws -> CryptoIdentity {
        identity
    }
}

private final class FakeRegistrationService: RegistrationService, @unchecked Sendable {
    private let result: RegistrationResult
    private(set) var requests: [RegistrationRequest] = []

    init(result: RegistrationResult) {
        self.result = result
    }

    func register(username: String, publicKeyBase64: String) async -> RegistrationResult {
        requests.append(RegistrationRequest(username: username, publicKeyBase64: publicKeyBase64))
        return result
    }
}
