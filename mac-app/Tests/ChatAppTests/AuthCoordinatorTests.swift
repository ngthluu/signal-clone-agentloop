import CryptoKit
import Foundation
import XCTest
@testable import ChatApp

final class AuthCoordinatorTests: XCTestCase {
    private var keychainStore: KeychainStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        keychainStore = KeychainStore(
            service: "\(KeychainStore.defaultService).tests",
            account: "\(KeychainStore.defaultAccount).session.\(UUID().uuidString).tests",
            usesDataProtectionKeychain: false
        )
        try keychainStore.delete()
    }

    override func tearDownWithError() throws {
        try keychainStore.delete()
        keychainStore = nil
        try super.tearDownWithError()
    }

    @MainActor
    func testSuccessfulSignInSignsChallengePersistsTokenAndMarksAuthenticated() async throws {
        let identity = CryptoIdentity(privateKey: Curve25519.Signing.PrivateKey())
        let nonce = Data("server-nonce".utf8)
        let service = FakeAuthenticationService(
            challengeResult: .challenge(challengeId: "challenge-1", nonceBase64: nonce.base64EncodedString()),
            verifyResult: .success(token: "session-token", userId: "user-1", username: "alice")
        )
        let sessionStore = SessionStore(keychainStore: keychainStore)
        let coordinator = try makeCoordinator(
            identity: identity,
            service: service,
            sessionStore: sessionStore
        )

        await coordinator.signIn()

        XCTAssertTrue(coordinator.isAuthenticated)
        XCTAssertTrue(coordinator.statusMessage.isEmpty)
        XCTAssertEqual(sessionStore.load(), "session-token")
        XCTAssertEqual(service.challengeUsernames, ["alice"])
        XCTAssertEqual(service.verifyRequests.map(\.challengeId), ["challenge-1"])

        let signature = Data(base64Encoded: service.verifyRequests[0].signatureBase64)
        let publicKeyData = Data(base64Encoded: identity.publicKeyBase64)!
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
        XCTAssertEqual(signature?.count, 64)
        XCTAssertTrue(publicKey.isValidSignature(signature!, for: nonce))
    }

    @MainActor
    func testRejectedProofLeavesUnauthenticatedShowsStatusAndStoresNoToken() async throws {
        let service = FakeAuthenticationService(
            challengeResult: .challenge(
                challengeId: "challenge-1",
                nonceBase64: Data("server-nonce".utf8).base64EncodedString()
            ),
            verifyResult: .rejected
        )
        let sessionStore = SessionStore(keychainStore: keychainStore)
        let coordinator = try makeCoordinator(service: service, sessionStore: sessionStore)

        await coordinator.signIn()

        XCTAssertFalse(coordinator.isAuthenticated)
        XCTAssertFalse(coordinator.statusMessage.isEmpty)
        XCTAssertNil(sessionStore.load())
    }

    @MainActor
    func testSignOutClearsSessionTokenAndMarksUnauthenticated() async throws {
        let sessionStore = SessionStore(keychainStore: keychainStore)
        try sessionStore.save("session-token")
        let coordinator = try makeCoordinator(sessionStore: sessionStore)

        coordinator.signOut()

        XCTAssertFalse(coordinator.isAuthenticated)
        XCTAssertNil(sessionStore.load())
    }

    @MainActor
    func testExistingSessionTokenMarksAuthenticatedAtInit() async throws {
        let sessionStore = SessionStore(keychainStore: keychainStore)
        try sessionStore.save("persisted-token")

        let coordinator = try makeCoordinator(sessionStore: sessionStore)

        XCTAssertTrue(coordinator.isAuthenticated)
    }

    @MainActor
    private func makeCoordinator(
        identity: CryptoIdentity = CryptoIdentity(privateKey: Curve25519.Signing.PrivateKey()),
        service: FakeAuthenticationService = FakeAuthenticationService(),
        sessionStore: SessionStore
    ) throws -> AuthCoordinator {
        let temporaryDirectory = try makeTemporaryDirectory()
        let accountStore = LocalAccountStore(directory: temporaryDirectory)
        try accountStore.save(LocalAccount(
            username: "alice",
            publicKeyBase64: identity.publicKeyBase64,
            userId: "user-1"
        ))

        return AuthCoordinator(
            identityProvider: StubAuthIdentityProvider(identity: identity),
            service: service,
            sessionStore: sessionStore,
            accountStore: accountStore
        )
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

private struct StubAuthIdentityProvider: IdentityProviding {
    let identity: CryptoIdentity

    func loadOrCreate() throws -> CryptoIdentity {
        identity
    }
}

private final class FakeAuthenticationService: AuthenticationService, @unchecked Sendable {
    struct VerifyRequest: Equatable {
        let challengeId: String
        let signatureBase64: String
    }

    private let challengeResult: ChallengeResult
    private let verifyResult: VerifyResult
    private(set) var challengeUsernames: [String] = []
    private(set) var verifyRequests: [VerifyRequest] = []

    init(
        challengeResult: ChallengeResult = .failure("unused"),
        verifyResult: VerifyResult = .failure("unused")
    ) {
        self.challengeResult = challengeResult
        self.verifyResult = verifyResult
    }

    func requestChallenge(username: String) async -> ChallengeResult {
        challengeUsernames.append(username)
        return challengeResult
    }

    func verify(challengeId: String, signatureBase64: String) async -> VerifyResult {
        verifyRequests.append(VerifyRequest(
            challengeId: challengeId,
            signatureBase64: signatureBase64
        ))
        return verifyResult
    }

    func validateSession(token: String) async -> Bool {
        false
    }
}
