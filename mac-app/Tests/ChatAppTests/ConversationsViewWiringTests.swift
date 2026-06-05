import CryptoKit
import Foundation
import XCTest
@testable import ChatApp

final class ConversationsViewWiringTests: XCTestCase {
    private var cleanupURLs: [URL] = []
    private var keychainStores: [KeychainStore] = []

    override func tearDownWithError() throws {
        for store in keychainStores {
            try? store.delete()
        }
        for url in cleanupURLs {
            try? FileManager.default.removeItem(at: url)
        }
        try super.tearDownWithError()
    }

    @MainActor
    func testSidebarOrdersConversationsMostRecentFirst() async throws {
        let harness = try makeHarness()
        harness.conversationsService.records = [
            record(peerId: "peer-old", username: "bob", messageId: "msg-old", createdAt: "2026-06-03T10:00:00Z"),
            record(peerId: "peer-new", username: "cora", messageId: "msg-new", createdAt: "2026-06-03T12:00:00Z"),
            record(peerId: "peer-mid", username: "dev", messageId: "msg-mid", createdAt: "2026-06-03T11:00:00Z")
        ]

        await harness.store.refresh()

        XCTAssertEqual(harness.store.conversations.map(\.peerUsername), ["cora", "dev", "bob"])
    }

    func testSidebarStateSelectsLoadingWhenInitialRefreshIsInFlight() {
        XCTAssertEqual(
            ConversationListSidebarState.resolve(
                conversations: [],
                isLoading: true,
                hasLoaded: false
            ),
            .loading
        )
    }

    func testSidebarStateSelectsEmptyAfterRefreshWithoutRows() {
        XCTAssertEqual(
            ConversationListSidebarState.resolve(
                conversations: [],
                isLoading: false,
                hasLoaded: true
            ),
            .empty
        )
    }

    func testSidebarStateSelectsPopulatedWheneverRowsExist() {
        XCTAssertEqual(
            ConversationListSidebarState.resolve(
                conversations: [
                    record(peerId: "peer-a", username: "alice-peer", messageId: "msg-a", createdAt: "2026-06-03T10:00:00Z")
                ],
                isLoading: true,
                hasLoaded: true
            ),
            .populated
        )
    }

    @MainActor
    func testLiveRecordBumpsSidebarList() async throws {
        let harness = try makeHarness()
        harness.conversationsService.records = [
            record(peerId: "peer-a", username: "alice-peer", messageId: "msg-a", createdAt: "2026-06-03T10:00:00Z"),
            record(peerId: "peer-b", username: "bob-peer", messageId: "msg-b", createdAt: "2026-06-03T11:00:00Z")
        ]
        await harness.store.refresh()
        XCTAssertEqual(harness.conversationsService.fetchCount, 1)

        await harness.store.handleLiveRecord(MessageRecord(
            id: "msg-a-live",
            senderId: "peer-a",
            recipientId: "user-a",
            ciphertext: "ciphertext",
            createdAt: "2026-06-03T12:00:00Z"
        ))

        XCTAssertEqual(harness.conversationsService.fetchCount, 1)
        XCTAssertEqual(harness.store.conversations.map(\.peerUsername), ["alice-peer", "bob-peer"])
        XCTAssertEqual(harness.store.conversations.first?.lastMessageId, "msg-a-live")
        XCTAssertEqual(harness.store.conversations.first?.lastActivityAt, "2026-06-03T12:00:00Z")
    }

    @MainActor
    func testSelectingConversationLoadsFullDecryptedHistory() async throws {
        let harness = try makeHarness()
        let peerX25519 = Curve25519.KeyAgreement.PrivateKey()
        try configureVerifiedPeer(in: harness, username: "bob", userId: "user-b", recipientKey: peerX25519)

        let localPrivate = try harness.x25519.loadOrCreate()
        harness.messageService.histories["bob"] = [
            try inboundRecord(
                id: "msg-1",
                text: "first decrypted message",
                senderId: "user-b",
                recipientId: "user-a",
                createdAt: "2026-06-03T10:00:00Z",
                localPrivate: localPrivate
            ),
            try inboundRecord(
                id: "msg-2",
                text: "second decrypted message",
                senderId: "user-b",
                recipientId: "user-a",
                createdAt: "2026-06-03T10:01:00Z",
                localPrivate: localPrivate
            ),
            try inboundRecord(
                id: "msg-3",
                text: "third decrypted message",
                senderId: "user-b",
                recipientId: "user-a",
                createdAt: "2026-06-03T10:02:00Z",
                localPrivate: localPrivate
            )
        ]

        harness.store.selectedPeerUsername = "bob"
        await harness.coordinator.startConversation(withUsername: try XCTUnwrap(harness.store.selectedPeerUsername))

        XCTAssertEqual(harness.coordinator.peerUsername, "bob")
        XCTAssertEqual(harness.messageService.historyRequests.map(\.username), ["bob", "bob"])
        XCTAssertEqual(harness.coordinator.messages, [
            DisplayMessage(id: "msg-1", isMine: false, text: "first decrypted message", createdAt: "2026-06-03T10:00:00Z"),
            DisplayMessage(id: "msg-2", isMine: false, text: "second decrypted message", createdAt: "2026-06-03T10:01:00Z"),
            DisplayMessage(id: "msg-3", isMine: false, text: "third decrypted message", createdAt: "2026-06-03T10:02:00Z")
        ])
    }

    @MainActor
    func testTaskPublishesOwnPrekey() async throws {
        let harness = try makeHarness()

        await harness.coordinator.publishOwnPrekey()

        let publish = try XCTUnwrap(harness.messageService.publishedPrekeys.first)
        XCTAssertEqual(publish.token, "token-1")
        XCTAssertFalse(publish.x25519PublicKey.isEmpty)
        XCTAssertFalse(publish.signature.isEmpty)
        XCTAssertEqual(harness.coordinator.statusMessage, "")
    }

    @MainActor
    private func makeHarness() throws -> WiringHarness {
        let keychainPrefix = "\(KeychainStore.defaultService).conversations-view-wiring.tests.\(UUID().uuidString)"
        let sessionKeychain = KeychainStore(
            service: keychainPrefix,
            account: "\(KeychainStore.defaultAccount).session.tests",
            usesDataProtectionKeychain: false
        )
        let x25519Keychain = KeychainStore(
            service: keychainPrefix,
            account: "\(KeychainStore.defaultAccount).x25519.tests",
            usesDataProtectionKeychain: false
        )
        keychainStores.append(sessionKeychain)
        keychainStores.append(x25519Keychain)

        let sessionStore = SessionStore(keychainStore: sessionKeychain)
        try sessionStore.save("token-1")

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("conversations-view-wiring-\(UUID().uuidString)", isDirectory: true)
        cleanupURLs.append(directory)
        let accountStore = LocalAccountStore(directory: directory)
        let identity = CryptoIdentity(privateKey: Curve25519.Signing.PrivateKey())
        try accountStore.save(LocalAccount(username: "alice", publicKeyBase64: identity.publicKeyBase64, userId: "user-a"))

        let conversationsService = FakeConversationsService()
        let store = ConversationListStore(
            service: conversationsService,
            sessionStore: sessionStore,
            accountStore: accountStore,
            makeLiveStream: { _ in AsyncThrowingStream { $0.finish() } }
        )

        let x25519 = X25519KeyManager(keychainStore: x25519Keychain)
        let messageService = FakeMessageService()
        let coordinator = DMCoordinator(
            identityProvider: StubIdentityProvider(identity: identity),
            x25519KeyManager: x25519,
            sessionStore: sessionStore,
            accountStore: accountStore,
            service: messageService,
            crypto: MessageCrypto(),
            attachmentService: FakeAttachmentService(),
            fileCrypto: FileCrypto()
        )

        return WiringHarness(
            store: store,
            conversationsService: conversationsService,
            coordinator: coordinator,
            messageService: messageService,
            x25519: x25519
        )
    }

    @MainActor
    private func configureVerifiedPeer(
        in harness: WiringHarness,
        username: String,
        userId: String,
        recipientKey: Curve25519.KeyAgreement.PrivateKey
    ) throws {
        let identity = CryptoIdentity(privateKey: Curve25519.Signing.PrivateKey())
        let x25519PublicKey = recipientKey.publicKey.rawRepresentation.base64EncodedString()
        let signature = MessageCrypto().signPrekey(x25519PublicKeyBase64: x25519PublicKey, with: identity)
        harness.messageService.prekeys[username] = PrekeyResponse(
            userId: userId,
            username: username,
            identityPublicKey: identity.publicKeyBase64,
            x25519PublicKey: x25519PublicKey,
            keySignature: signature
        )
    }

    private func inboundRecord(
        id: String,
        text: String,
        senderId: String,
        recipientId: String,
        createdAt: String,
        localPrivate: Curve25519.KeyAgreement.PrivateKey
    ) throws -> MessageRecord {
        MessageRecord(
            id: id,
            senderId: senderId,
            recipientId: recipientId,
            ciphertext: try MessageCrypto().encrypt(
                Data(text.utf8),
                toRecipientX25519: localPrivate.publicKey.rawRepresentation.base64EncodedString()
            ),
            createdAt: createdAt
        )
    }

    private func record(peerId: String, username: String, messageId: String, createdAt: String) -> ConversationSummary {
        ConversationSummary(
            peerId: peerId,
            peerUsername: username,
            lastActivityAt: createdAt,
            lastMessageId: messageId
        )
    }
}

private struct WiringHarness {
    let store: ConversationListStore
    let conversationsService: FakeConversationsService
    let coordinator: DMCoordinator
    let messageService: FakeMessageService
    let x25519: X25519KeyManager
}

private struct StubIdentityProvider: IdentityProviding {
    let identity: CryptoIdentity

    func loadOrCreate() throws -> CryptoIdentity {
        identity
    }
}

private final class FakeConversationsService: ConversationsService, @unchecked Sendable {
    var records: [ConversationSummary] = []
    private(set) var fetchCount = 0

    func conversations(token: String) async -> [ConversationSummary] {
        fetchCount += 1
        return records
    }
}

private final class FakeMessageService: MessageService, @unchecked Sendable {
    var prekeys: [String: PrekeyResponse] = [:]
    var histories: [String: [MessageRecord]] = [:]
    var liveRecords: [MessageRecord] = []
    var sentMessages: [(recipientUsername: String, ciphertext: String)] = []
    var historyRequests: [(username: String, since: String?)] = []
    private(set) var publishedPrekeys: [(token: String, x25519PublicKey: String, signature: String)] = []

    func publishPrekey(token: String, x25519PublicKey: String, signature: String) async -> Bool {
        publishedPrekeys.append((token: token, x25519PublicKey: x25519PublicKey, signature: signature))
        return true
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

private final class FakeAttachmentService: AttachmentService, @unchecked Sendable {
    func upload(token: String, encryptedBlob: Data) async -> String? {
        "attachment-1"
    }

    func download(token: String, attachmentId: String) async -> Data? {
        nil
    }
}
