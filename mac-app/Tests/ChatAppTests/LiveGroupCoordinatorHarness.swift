import CryptoKit
import Foundation
import XCTest
@testable import ChatApp

final class LiveGroupCoordinatorTestSupport {
    private let registrationClient: HTTPRegistrationClient
    private let authClient: HTTPAuthClient
    private let messageService: HTTPMessageService
    private let groupService: HTTPGroupService
    private var cleanupURLs: [URL] = []
    private var keychainStores: [KeychainStore] = []

    init(backendURL: URL) {
        registrationClient = HTTPRegistrationClient(baseURL: backendURL)
        authClient = HTTPAuthClient(baseURL: backendURL)
        messageService = HTTPMessageService(baseURL: backendURL)
        groupService = HTTPGroupService(baseURL: backendURL)
    }

    @MainActor
    func makeUser(prefix: String, file: StaticString = #filePath, line: UInt = #line) async throws -> LiveGroupCoordinatorUser {
        let usernameSuffix = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(20))
        let username = "\(prefix)_\(usernameSuffix)"
        let identity = CryptoIdentity(privateKey: Curve25519.Signing.PrivateKey())

        let registration = await registrationClient.register(username: username, publicKeyBase64: identity.publicKeyBase64)
        let userId: String
        switch registration {
        case let .success(registeredUserId):
            userId = registeredUserId
        default:
            XCTFail("Registration failed for \(username): \(registration)", file: file, line: line)
            throw LiveGroupCoordinatorHarnessError.registrationFailed(username)
        }

        let token = try await signIn(username: username, identity: identity, file: file, line: line)

        let sessionKeychain = KeychainStore(
            service: "\(KeychainStore.defaultService).live.groups.\(UUID().uuidString)",
            account: "\(KeychainStore.defaultAccount).session",
            usesDataProtectionKeychain: false
        )
        let x25519Keychain = KeychainStore(
            service: "\(KeychainStore.defaultService).live.groups.\(UUID().uuidString)",
            account: "\(KeychainStore.defaultAccount).x25519",
            usesDataProtectionKeychain: false
        )
        keychainStores.append(sessionKeychain)
        keychainStores.append(x25519Keychain)

        let sessionStore = SessionStore(keychainStore: sessionKeychain)
        try sessionStore.save(token)

        let x25519KeyManager = X25519KeyManager(keychainStore: x25519Keychain)
        let x25519PublicKey = try x25519KeyManager.publicKeyBase64()
        let signature = MessageCrypto().signPrekey(x25519PublicKeyBase64: x25519PublicKey, with: identity)
        let published = await messageService.publishPrekey(
            token: token,
            x25519PublicKey: x25519PublicKey,
            signature: signature
        )
        XCTAssertTrue(published, "Expected signed prekey publish to succeed for \(username)", file: file, line: line)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("live-group-coordinator-\(UUID().uuidString)", isDirectory: true)
        cleanupURLs.append(directory)
        let accountStore = LocalAccountStore(directory: directory)
        try accountStore.save(LocalAccount(username: username, publicKeyBase64: identity.publicKeyBase64, userId: userId))

        let coordinator = GroupCoordinator(
            identityProvider: LiveGroupCoordinatorIdentityProvider(identity: identity),
            x25519KeyManager: x25519KeyManager,
            sessionStore: sessionStore,
            accountStore: accountStore,
            messageService: messageService,
            groupService: groupService,
            crypto: GroupCrypto()
        )

        return LiveGroupCoordinatorUser(
            username: username,
            userId: userId,
            token: token,
            coordinator: coordinator
        )
    }

    func cleanup() {
        for store in keychainStores {
            try? store.delete()
        }
        keychainStores.removeAll()

        for url in cleanupURLs {
            try? FileManager.default.removeItem(at: url)
        }
        cleanupURLs.removeAll()
    }

    @MainActor
    private func signIn(username: String, identity: CryptoIdentity, file: StaticString, line: UInt) async throws -> String {
        let challenge = await authClient.requestChallenge(username: username)
        let challengeId: String
        let nonceBase64: String
        switch challenge {
        case let .challenge(returnedChallengeId, returnedNonceBase64):
            challengeId = returnedChallengeId
            nonceBase64 = returnedNonceBase64
        default:
            XCTFail("Challenge failed for \(username): \(challenge)", file: file, line: line)
            throw LiveGroupCoordinatorHarnessError.challengeFailed(username)
        }

        let nonce = try XCTUnwrap(Data(base64Encoded: nonceBase64), file: file, line: line)
        let verification = await authClient.verify(
            challengeId: challengeId,
            signatureBase64: identity.sign(nonce).base64EncodedString()
        )
        switch verification {
        case let .success(token, _, returnedUsername):
            XCTAssertEqual(returnedUsername, username, file: file, line: line)
            return token
        default:
            XCTFail("Verify failed for \(username): \(verification)", file: file, line: line)
            throw LiveGroupCoordinatorHarnessError.verifyFailed(username)
        }
    }
}

struct LiveGroupCoordinatorUser {
    let username: String
    let userId: String
    let token: String
    let coordinator: GroupCoordinator
}

private struct LiveGroupCoordinatorIdentityProvider: IdentityProviding {
    let identity: CryptoIdentity

    func loadOrCreate() throws -> CryptoIdentity {
        identity
    }
}

private enum LiveGroupCoordinatorHarnessError: Error {
    case registrationFailed(String)
    case challengeFailed(String)
    case verifyFailed(String)
}
