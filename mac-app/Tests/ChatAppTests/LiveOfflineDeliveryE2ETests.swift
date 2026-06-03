import CryptoKit
import Foundation
import XCTest
@testable import ChatApp

final class LiveOfflineDeliveryE2ETests: XCTestCase {
    private var cleanupURLs: [URL] = []
    private var keychainStores: [KeychainStore] = []

    override func tearDownWithError() throws {
        for store in keychainStores {
            try store.delete()
        }
        for url in cleanupURLs {
            try? FileManager.default.removeItem(at: url)
        }
        try super.tearDownWithError()
    }

    @MainActor
    func testOfflineRecipientReceivesQueuedMessagesInOrderAndRestartReloadsHistory() async throws {
        let backendURLString = ProcessInfo.processInfo.environment["CHATAPP_LIVE_BACKEND_URL"]
        try XCTSkipUnless(backendURLString != nil, "CHATAPP_LIVE_BACKEND_URL is not set")

        guard let backendURLString, let backendURL = URL(string: backendURLString) else {
            XCTFail("CHATAPP_LIVE_BACKEND_URL is not a valid URL")
            return
        }

        let registrationClient = HTTPRegistrationClient(baseURL: backendURL)
        let authClient = HTTPAuthClient(baseURL: backendURL)
        let messageService = HTTPMessageService(baseURL: backendURL)
        let crypto = MessageCrypto()

        let alice = try await makeLiveUser(
            prefix: "off_a",
            registrationClient: registrationClient,
            authClient: authClient,
            messageService: messageService,
            crypto: crypto
        )
        let bob = try await makeLiveUser(
            prefix: "off_b",
            registrationClient: registrationClient,
            authClient: authClient,
            messageService: messageService,
            crypto: crypto
        )

        let bobEnvironment = try makeBobEnvironment(user: bob)
        let plaintexts = (1...6).map { "offline-\($0)-\(UUID().uuidString)" }
        let fetchedPrekey = await messageService.fetchPrekey(username: bob.username, token: alice.token)
        let prekey = try XCTUnwrap(fetchedPrekey)
        var sentIds: [String] = []

        for plaintext in plaintexts {
            let ciphertext = try crypto.encrypt(Data(plaintext.utf8), toRecipientX25519: prekey.x25519PublicKey)
            let result = await messageService.send(
                token: alice.token,
                recipientUsername: bob.username,
                ciphertext: ciphertext
            )
            guard case let .success(messageId, _) = result else {
                return XCTFail("Expected send to succeed, got \(result)")
            }
            sentIds.append(messageId)
        }

        let firstStore = LocalMessageStore()
        let firstCoordinator = makeCoordinator(
            service: messageService,
            environment: bobEnvironment,
            messageStore: firstStore
        )
        await firstCoordinator.reconnect()
        firstCoordinator.cancelLiveSubscription()

        XCTAssertEqual(firstStore.messages.map(\.id), sentIds)
        XCTAssertEqual(firstStore.messages.map(\.text), plaintexts)
        XCTAssertEqual(firstStore.messages.compactMap(\.seq).count, plaintexts.count)
        XCTAssertTrue(bobEnvironment.cursorStore.load(userId: bob.userId) > 0)

        let restartedStore = LocalMessageStore()
        let restartedCoordinator = makeCoordinator(
            service: messageService,
            environment: bobEnvironment,
            messageStore: restartedStore
        )
        await restartedCoordinator.syncOnLaunch()
        restartedCoordinator.cancelLiveSubscription()

        let reloadedMessages = restartedStore.conversationMessages(peerUsername: alice.username)
        XCTAssertEqual(reloadedMessages.count, plaintexts.count)
        XCTAssertEqual(Set(reloadedMessages.map(\.id)), Set(sentIds))
        XCTAssertEqual(Set(reloadedMessages.map(\.text)), Set(plaintexts))
        XCTAssertEqual(Set(restartedStore.messages.map(\.text)), Set(plaintexts))

        try writeProofArtifacts(messageIds: sentIds, plaintexts: plaintexts)
    }

    @MainActor
    private func makeLiveUser(
        prefix: String,
        registrationClient: HTTPRegistrationClient,
        authClient: HTTPAuthClient,
        messageService: HTTPMessageService,
        crypto: MessageCrypto
    ) async throws -> LiveOfflineUser {
        let usernameSuffix = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(20))
        let username = "\(prefix)_\(usernameSuffix)"
        let identity = CryptoIdentity(privateKey: Curve25519.Signing.PrivateKey())
        let x25519PrivateKey = Curve25519.KeyAgreement.PrivateKey()
        let x25519PublicKey = x25519PrivateKey.publicKey.rawRepresentation.base64EncodedString()

        let registration = await registrationClient.register(
            username: username,
            publicKeyBase64: identity.publicKeyBase64
        )
        let userId: String
        switch registration {
        case let .success(registeredUserId):
            userId = registeredUserId
        default:
            throw LiveOfflineError.registrationFailed(username, "\(registration)")
        }

        let token = try await signIn(username: username, identity: identity, authClient: authClient)
        let signature = crypto.signPrekey(x25519PublicKeyBase64: x25519PublicKey, with: identity)
        let published = await messageService.publishPrekey(
            token: token,
            x25519PublicKey: x25519PublicKey,
            signature: signature
        )
        XCTAssertTrue(published, "Expected signed prekey publish to succeed for \(username)")

        return LiveOfflineUser(
            username: username,
            userId: userId,
            token: token,
            identityPublicKeyBase64: identity.publicKeyBase64,
            x25519PrivateKey: x25519PrivateKey
        )
    }

    @MainActor
    private func signIn(
        username: String,
        identity: CryptoIdentity,
        authClient: HTTPAuthClient
    ) async throws -> String {
        let challenge = await authClient.requestChallenge(username: username)
        let challengeId: String
        let nonceBase64: String
        switch challenge {
        case let .challenge(returnedChallengeId, returnedNonceBase64):
            challengeId = returnedChallengeId
            nonceBase64 = returnedNonceBase64
        default:
            throw LiveOfflineError.challengeFailed(username, "\(challenge)")
        }

        let nonce = try XCTUnwrap(Data(base64Encoded: nonceBase64))
        let verification = await authClient.verify(
            challengeId: challengeId,
            signatureBase64: identity.sign(nonce).base64EncodedString()
        )
        switch verification {
        case let .success(token, _, returnedUsername):
            XCTAssertEqual(returnedUsername, username)
            return token
        default:
            throw LiveOfflineError.verifyFailed(username, "\(verification)")
        }
    }

    private func makeBobEnvironment(user: LiveOfflineUser) throws -> LiveOfflineEnvironment {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("live-offline-\(UUID().uuidString)", isDirectory: true)
        cleanupURLs.append(directory)

        let sessionKeychain = KeychainStore(
            service: "\(KeychainStore.defaultService).live-offline.\(UUID().uuidString)",
            account: "\(KeychainStore.defaultAccount).session",
            usesDataProtectionKeychain: false
        )
        let x25519Keychain = KeychainStore(
            service: "\(KeychainStore.defaultService).live-offline.\(UUID().uuidString)",
            account: "\(KeychainStore.defaultAccount).x25519",
            usesDataProtectionKeychain: false
        )
        keychainStores.append(sessionKeychain)
        keychainStores.append(x25519Keychain)

        try x25519Keychain.save(user.x25519PrivateKey.rawRepresentation)
        let sessionStore = SessionStore(keychainStore: sessionKeychain)
        try sessionStore.save(user.token)
        let accountStore = LocalAccountStore(directory: directory)
        try accountStore.save(LocalAccount(
            username: user.username,
            publicKeyBase64: user.identityPublicKeyBase64,
            userId: user.userId
        ))

        return LiveOfflineEnvironment(
            sessionStore: sessionStore,
            accountStore: accountStore,
            x25519KeyManager: X25519KeyManager(keychainStore: x25519Keychain),
            cursorStore: SyncCursorStore(directory: directory)
        )
    }

    @MainActor
    private func makeCoordinator(
        service: HTTPMessageService,
        environment: LiveOfflineEnvironment,
        messageStore: LocalMessageStore
    ) -> OfflineSyncCoordinator {
        OfflineSyncCoordinator(
            service: service,
            crypto: MessageCrypto(),
            x25519KeyManager: environment.x25519KeyManager,
            sessionStore: environment.sessionStore,
            accountStore: environment.accountStore,
            cursorStore: environment.cursorStore,
            messageStore: messageStore
        )
    }

    private func writeProofArtifacts(messageIds: [String], plaintexts: [String]) throws {
        let environment = ProcessInfo.processInfo.environment
        try writeIfRequested(messageIds.joined(separator: "\n"), path: environment["CHATAPP_OFFLINE_MESSAGE_IDS_OUT"])
        try writeIfRequested(plaintexts.joined(separator: "\n"), path: environment["CHATAPP_OFFLINE_PLAINTEXTS_OUT"])
    }

    private func writeIfRequested(_ value: String, path: String?) throws {
        guard let path else {
            return
        }
        try value.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
    }
}

private struct LiveOfflineUser {
    let username: String
    let userId: String
    let token: String
    let identityPublicKeyBase64: String
    let x25519PrivateKey: Curve25519.KeyAgreement.PrivateKey
}

private struct LiveOfflineEnvironment {
    let sessionStore: SessionStore
    let accountStore: LocalAccountStore
    let x25519KeyManager: X25519KeyManager
    let cursorStore: SyncCursorStore
}

private enum LiveOfflineError: Error, CustomStringConvertible {
    case registrationFailed(String, String)
    case challengeFailed(String, String)
    case verifyFailed(String, String)

    var description: String {
        switch self {
        case let .registrationFailed(username, result):
            return "Registration failed for \(username): \(result)"
        case let .challengeFailed(username, result):
            return "Challenge failed for \(username): \(result)"
        case let .verifyFailed(username, result):
            return "Verify failed for \(username): \(result)"
        }
    }
}
