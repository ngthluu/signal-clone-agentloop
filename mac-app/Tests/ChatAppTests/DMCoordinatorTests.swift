import CryptoKit
import Foundation
import XCTest
@testable import ChatApp

final class DMCoordinatorTests: XCTestCase {
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
    func testStartConversationRejectsPeerWithInvalidPrekeySignature() async throws {
        let harness = try makeHarness()
        let peerKey = Curve25519.KeyAgreement.PrivateKey()
        let peerIdentity = CryptoIdentity(privateKey: Curve25519.Signing.PrivateKey())
        let badSignature = MessageCrypto().signPrekey(
            x25519PublicKeyBase64: Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation.base64EncodedString(),
            with: peerIdentity
        )
        harness.service.prekeys["bob"] = PrekeyResponse(
            userId: "user-b",
            username: "bob",
            identityPublicKey: peerIdentity.publicKeyBase64,
            x25519PublicKey: peerKey.publicKey.rawRepresentation.base64EncodedString(),
            keySignature: badSignature
        )

        await harness.coordinator.startConversation(withUsername: "bob")

        XCTAssertEqual(harness.coordinator.statusMessage, "Could not verify bob's keys.")
        XCTAssertNil(harness.coordinator.peerUsername)
        XCTAssertEqual(harness.service.historyRequests.count, 0)
    }

    @MainActor
    func testStartConversationShowsUserNotFoundForMissingPeer() async throws {
        let harness = try makeHarness()

        await harness.coordinator.startConversation(withUsername: "missing")

        XCTAssertEqual(harness.coordinator.statusMessage, "User not found.")
        XCTAssertNil(harness.coordinator.peerUsername)
    }

    @MainActor
    func testSendEncryptsCiphertextAndRecipientCanDecryptIt() async throws {
        let harness = try makeHarness()
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        try configureVerifiedPeer(in: harness, username: "bob", recipientKey: recipient)

        await harness.coordinator.startConversation(withUsername: "bob")
        await harness.coordinator.send(text: "hello bob")

        let sent = try XCTUnwrap(harness.service.sentMessages.last)
        XCTAssertEqual(sent.recipientUsername, "bob")
        XCTAssertNotEqual(sent.ciphertext, "hello bob")
        XCTAssertFalse(sent.ciphertext.contains("hello bob"))

        let decrypted = try MessageCrypto().decrypt(sent.ciphertext, withLocalX25519: recipient)
        XCTAssertEqual(String(decoding: decrypted, as: UTF8.self), "hello bob")
        XCTAssertEqual(harness.coordinator.messages.last?.text, "hello bob")
        XCTAssertEqual(harness.coordinator.messages.last?.isMine, true)
    }

    @MainActor
    func testLoadHistoryDecryptsInboundRecordIntoDisplayMessages() async throws {
        let harness = try makeHarness()
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        try configureVerifiedPeer(in: harness, username: "bob", recipientKey: recipient)

        let localPrivate = try harness.x25519.loadOrCreate()
        let ciphertext = try MessageCrypto().encrypt(
            Data("hello alice".utf8),
            toRecipientX25519: localPrivate.publicKey.rawRepresentation.base64EncodedString()
        )
        harness.service.histories["bob"] = [
            MessageRecord(
                id: "msg-in",
                senderId: "user-b",
                recipientId: "user-a",
                ciphertext: ciphertext,
                createdAt: "2026-06-03T00:00:00Z"
            )
        ]

        await harness.coordinator.startConversation(withUsername: "bob")

        XCTAssertEqual(harness.coordinator.messages, [
            DisplayMessage(
                id: "msg-in",
                isMine: false,
                text: "hello alice",
                createdAt: "2026-06-03T00:00:00Z"
            )
        ])
    }

    @MainActor
    func testSubscribeLiveDecryptsInboundRecordAndDedupesExistingMessages() async throws {
        let harness = try makeHarness()
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        try configureVerifiedPeer(in: harness, username: "bob", recipientKey: recipient)
        let localPrivate = try harness.x25519.loadOrCreate()
        let ciphertext = try MessageCrypto().encrypt(
            Data("hello live".utf8),
            toRecipientX25519: localPrivate.publicKey.rawRepresentation.base64EncodedString()
        )
        harness.service.liveRecords = [
            MessageRecord(
                id: "msg-live",
                senderId: "user-b",
                recipientId: "user-a",
                ciphertext: ciphertext,
                createdAt: "2026-06-03T00:00:00Z"
            ),
            MessageRecord(
                id: "msg-live",
                senderId: "user-b",
                recipientId: "user-a",
                ciphertext: ciphertext,
                createdAt: "2026-06-03T00:00:00Z"
            )
        ]

        await harness.coordinator.startConversation(withUsername: "bob")
        await harness.coordinator.subscribeLive()
        try await waitForMessages(in: harness, count: 1)

        XCTAssertEqual(harness.coordinator.messages, [
            DisplayMessage(
                id: "msg-live",
                isMine: false,
                text: "hello live",
                createdAt: "2026-06-03T00:00:00Z"
            )
        ])
    }

    @MainActor
    func testCancelLiveSubscriptionCancelsWithoutRemovingMessages() async throws {
        let harness = try makeHarness()
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        try configureVerifiedPeer(in: harness, username: "bob", recipientKey: recipient)

        await harness.coordinator.startConversation(withUsername: "bob")
        harness.coordinator.cancelLiveSubscription()

        XCTAssertEqual(harness.coordinator.messages, [])
    }

    @MainActor
    private func makeHarness() throws -> Harness {
        let sessionKeychain = KeychainStore(
            service: "\(KeychainStore.defaultService).dm.tests.\(UUID().uuidString)",
            account: "\(KeychainStore.defaultAccount).session.tests",
            usesDataProtectionKeychain: false
        )
        let x25519Keychain = KeychainStore(
            service: "\(KeychainStore.defaultService).dm.tests.\(UUID().uuidString)",
            account: "\(KeychainStore.defaultAccount).x25519.tests",
            usesDataProtectionKeychain: false
        )
        keychainStores.append(sessionKeychain)
        keychainStores.append(x25519Keychain)

        let sessionStore = SessionStore(keychainStore: sessionKeychain)
        try sessionStore.save("token-1")

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dm-coordinator-\(UUID().uuidString)", isDirectory: true)
        cleanupURLs.append(directory)
        let accountStore = LocalAccountStore(directory: directory)
        let identity = CryptoIdentity(privateKey: Curve25519.Signing.PrivateKey())
        try accountStore.save(LocalAccount(username: "alice", publicKeyBase64: identity.publicKeyBase64, userId: "user-a"))

        let x25519 = X25519KeyManager(keychainStore: x25519Keychain)
        let service = FakeMessageService()
        let coordinator = DMCoordinator(
            identityProvider: StubIdentityProvider(identity: identity),
            x25519KeyManager: x25519,
            sessionStore: sessionStore,
            accountStore: accountStore,
            service: service,
            crypto: MessageCrypto()
        )
        return Harness(coordinator: coordinator, service: service, x25519: x25519)
    }

    @MainActor
    private func configureVerifiedPeer(
        in harness: Harness,
        username: String,
        recipientKey: Curve25519.KeyAgreement.PrivateKey
    ) throws {
        let identity = CryptoIdentity(privateKey: Curve25519.Signing.PrivateKey())
        let x25519PublicKey = recipientKey.publicKey.rawRepresentation.base64EncodedString()
        let signature = MessageCrypto().signPrekey(x25519PublicKeyBase64: x25519PublicKey, with: identity)
        harness.service.prekeys[username] = PrekeyResponse(
            userId: "user-b",
            username: username,
            identityPublicKey: identity.publicKeyBase64,
            x25519PublicKey: x25519PublicKey,
            keySignature: signature
        )
    }

    @MainActor
    private func waitForMessages(in harness: Harness, count: Int) async throws {
        for _ in 0..<20 {
            if harness.coordinator.messages.count == count {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}

private struct Harness {
    let coordinator: DMCoordinator
    let service: FakeMessageService
    let x25519: X25519KeyManager
}

private struct StubIdentityProvider: IdentityProviding {
    let identity: CryptoIdentity

    func loadOrCreate() throws -> CryptoIdentity {
        identity
    }
}

private final class FakeMessageService: MessageService, @unchecked Sendable {
    var prekeys: [String: PrekeyResponse] = [:]
    var histories: [String: [MessageRecord]] = [:]
    var liveRecords: [MessageRecord] = []
    var sentMessages: [(recipientUsername: String, ciphertext: String)] = []
    var historyRequests: [(username: String, since: String?)] = []

    func publishPrekey(token: String, x25519PublicKey: String, signature: String) async -> Bool {
        true
    }

    func fetchPrekey(username: String, token: String) async -> PrekeyResponse? {
        prekeys[username]
    }

    func send(token: String, recipientUsername: String, ciphertext: String) async -> SendMessageResult {
        sentMessages.append((recipientUsername: recipientUsername, ciphertext: ciphertext))
        return .success(messageId: "msg-\(sentMessages.count)", createdAt: "2026-06-03T00:00:00Z")
    }

    func history(token: String, withUsername username: String, since: String?) async -> [MessageRecord] {
        historyRequests.append((username: username, since: since))
        return histories[username] ?? []
    }

    func inbox(token: String, since: Int) async -> InboxPage {
        InboxPage(messages: [], nextCursor: nil)
    }

    func conversations(token: String) async -> [ConversationSummary] {
        []
    }

    func liveMessages(token: String) -> AsyncThrowingStream<MessageRecord, Error> {
        AsyncThrowingStream { continuation in
            for record in liveRecords {
                continuation.yield(record)
            }
            continuation.finish()
        }
    }
}
