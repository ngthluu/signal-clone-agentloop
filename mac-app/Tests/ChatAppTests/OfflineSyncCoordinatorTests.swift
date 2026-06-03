import CryptoKit
import Foundation
import XCTest
@testable import ChatApp

final class OfflineSyncCoordinatorTests: XCTestCase {
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
    func testReconnectAppliesOfflineInboxMessagesInServerSeqOrder() async throws {
        let harness = try makeHarness()
        harness.service.inboxPages = [
            InboxPage(messages: [
                try harness.inboxMessage(seq: 11, id: "msg-1", text: "first"),
                try harness.inboxMessage(seq: 12, id: "msg-2", text: "second"),
                try harness.inboxMessage(seq: 13, id: "msg-3", text: "third")
            ], nextCursor: 13),
            InboxPage(messages: [], nextCursor: nil)
        ]

        await harness.coordinator.reconnect()

        XCTAssertEqual(harness.store.messages.map(\.text), ["first", "second", "third"])
        XCTAssertEqual(harness.store.messages.map(\.id), ["msg-1", "msg-2", "msg-3"])
        XCTAssertEqual(harness.cursorStore.load(userId: "user-a"), 13)
        XCTAssertEqual(harness.service.inboxRequests, [0, 13])
    }

    @MainActor
    func testSyncOnLaunchReloadsConversationHistoriesAndDecryptsIntoFreshStore() async throws {
        let harness = try makeHarness()
        harness.service.conversationResults = [
            ConversationSummary(peerUserId: "user-b", peerUsername: "bob", lastActivity: "2026-06-03T00:00:02Z", lastSeq: 2),
            ConversationSummary(peerUserId: "user-c", peerUsername: "carol", lastActivity: "2026-06-03T00:00:03Z", lastSeq: 3)
        ]
        harness.service.histories = [
            "bob": [
                try harness.message(id: "bob-1", senderId: "user-b", recipientId: "user-a", text: "from bob"),
                try harness.message(id: "bob-2", senderId: "user-a", recipientId: "user-b", text: "to bob")
            ],
            "carol": [
                try harness.message(id: "carol-1", senderId: "user-c", recipientId: "user-a", text: "from carol")
            ]
        ]
        harness.service.inboxPages = [InboxPage(messages: [], nextCursor: nil)]

        await harness.coordinator.syncOnLaunch()

        XCTAssertEqual(harness.service.historyRequests.map(\.username), ["bob", "carol"])
        XCTAssertEqual(harness.store.messages.map(\.id), ["bob-1", "bob-2", "carol-1"])
        XCTAssertEqual(harness.store.messages.map(\.text), ["from bob", "to bob", "from carol"])
        XCTAssertEqual(Set(harness.store.conversationMessages(peerUsername: "bob").map(\.id)), ["bob-1", "bob-2"])
        XCTAssertEqual(harness.store.conversationMessages(peerUsername: "carol").map(\.id), ["carol-1"])
    }

    @MainActor
    func testPersistedCursorPreventsRedeliveryOnSecondReconnect() async throws {
        let harness = try makeHarness()
        harness.service.inboxPages = [
            InboxPage(messages: [
                try harness.inboxMessage(seq: 21, id: "msg-1", text: "once")
            ], nextCursor: 21),
            InboxPage(messages: [], nextCursor: nil),
            InboxPage(messages: [], nextCursor: nil)
        ]

        await harness.coordinator.reconnect()
        await harness.coordinator.reconnect()

        XCTAssertEqual(harness.store.messages.map(\.id), ["msg-1"])
        XCTAssertEqual(harness.cursorStore.load(userId: "user-a"), 21)
        XCTAssertEqual(harness.service.inboxRequests, [0, 21, 21])
    }

    @MainActor
    func testHistoryInboxAndLiveDuplicateIsStoredOnce() async throws {
        let harness = try makeHarness()
        let duplicate = try harness.message(id: "dup-1", senderId: "user-b", recipientId: "user-a", text: "only once")
        harness.service.conversationResults = [
            ConversationSummary(peerUserId: "user-b", peerUsername: "bob", lastActivity: duplicate.createdAt, lastSeq: 31)
        ]
        harness.service.histories = ["bob": [duplicate]]
        harness.service.inboxPages = [
            InboxPage(messages: [InboxMessageRecord(seq: 31, id: duplicate.id, senderId: duplicate.senderId, recipientId: duplicate.recipientId, ciphertext: duplicate.ciphertext, createdAt: duplicate.createdAt)], nextCursor: 31),
            InboxPage(messages: [], nextCursor: nil)
        ]
        harness.service.liveRecords = [duplicate]

        await harness.coordinator.syncOnLaunch()
        try await waitUntil { harness.service.liveSubscribed }

        XCTAssertEqual(harness.store.messages.map(\.id), ["dup-1"])
        XCTAssertEqual(harness.store.messages.map(\.text), ["only once"])
    }

    @MainActor
    private func makeHarness() throws -> Harness {
        let sessionKeychain = KeychainStore(
            service: "\(KeychainStore.defaultService).offline-sync.tests.\(UUID().uuidString)",
            account: "\(KeychainStore.defaultAccount).session.tests",
            usesDataProtectionKeychain: false
        )
        let x25519Keychain = KeychainStore(
            service: "\(KeychainStore.defaultService).offline-sync.tests.\(UUID().uuidString)",
            account: "\(KeychainStore.defaultAccount).x25519.tests",
            usesDataProtectionKeychain: false
        )
        keychainStores.append(sessionKeychain)
        keychainStores.append(x25519Keychain)

        let sessionStore = SessionStore(keychainStore: sessionKeychain)
        try sessionStore.save("token-1")

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("offline-sync-\(UUID().uuidString)", isDirectory: true)
        cleanupURLs.append(directory)
        let accountStore = LocalAccountStore(directory: directory)
        try accountStore.save(LocalAccount(username: "alice", publicKeyBase64: "identity-a", userId: "user-a"))

        let x25519 = X25519KeyManager(keychainStore: x25519Keychain)
        _ = try x25519.loadOrCreate()
        let service = FakeOfflineMessageService()
        let store = LocalMessageStore()
        let cursorStore = SyncCursorStore(directory: directory)
        let coordinator = OfflineSyncCoordinator(
            service: service,
            crypto: MessageCrypto(),
            x25519KeyManager: x25519,
            sessionStore: sessionStore,
            accountStore: accountStore,
            cursorStore: cursorStore,
            messageStore: store
        )
        return Harness(
            coordinator: coordinator,
            service: service,
            store: store,
            cursorStore: cursorStore,
            x25519: x25519
        )
    }

    @MainActor
    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        for _ in 0..<20 {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Condition was not met.", file: file, line: line)
    }
}

private struct Harness {
    let coordinator: OfflineSyncCoordinator
    let service: FakeOfflineMessageService
    let store: LocalMessageStore
    let cursorStore: SyncCursorStore
    let x25519: X25519KeyManager

    func message(
        id: String,
        senderId: String,
        recipientId: String,
        text: String,
        createdAt: String = "2026-06-03T00:00:00Z"
    ) throws -> MessageRecord {
        let localPrivate = try x25519.loadOrCreate()
        let ciphertext = try MessageCrypto().encrypt(
            Data(text.utf8),
            toRecipientX25519: localPrivate.publicKey.rawRepresentation.base64EncodedString()
        )
        return MessageRecord(
            id: id,
            senderId: senderId,
            recipientId: recipientId,
            ciphertext: ciphertext,
            createdAt: createdAt
        )
    }

    func inboxMessage(seq: Int, id: String, text: String) throws -> InboxMessageRecord {
        let record = try message(id: id, senderId: "user-b", recipientId: "user-a", text: text)
        return InboxMessageRecord(
            seq: seq,
            id: record.id,
            senderId: record.senderId,
            recipientId: record.recipientId,
            ciphertext: record.ciphertext,
            createdAt: record.createdAt
        )
    }
}

private final class FakeOfflineMessageService: MessageService, @unchecked Sendable {
    var conversationResults: [ConversationSummary] = []
    var histories: [String: [MessageRecord]] = [:]
    var inboxPages: [InboxPage] = []
    var liveRecords: [MessageRecord] = []
    var historyRequests: [(username: String, since: String?)] = []
    var inboxRequests: [Int] = []
    var liveSubscribed = false

    func publishPrekey(token: String, x25519PublicKey: String, signature: String) async -> Bool {
        true
    }

    func fetchPrekey(username: String, token: String) async -> PrekeyResponse? {
        nil
    }

    func send(token: String, recipientUsername: String, ciphertext: String) async -> SendMessageResult {
        .failure("unused")
    }

    func history(token: String, withUsername username: String, since: String?) async -> [MessageRecord] {
        historyRequests.append((username: username, since: since))
        return histories[username] ?? []
    }

    func inbox(token: String, since: Int) async -> InboxPage {
        inboxRequests.append(since)
        guard !inboxPages.isEmpty else {
            return InboxPage(messages: [], nextCursor: nil)
        }
        return inboxPages.removeFirst()
    }

    func conversations(token: String) async -> [ConversationSummary] {
        conversationResults
    }

    func liveMessages(token: String) -> AsyncThrowingStream<MessageRecord, Error> {
        AsyncThrowingStream { continuation in
            liveSubscribed = true
            for record in liveRecords {
                continuation.yield(record)
            }
            continuation.finish()
        }
    }
}
