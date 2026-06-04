import XCTest
@testable import ChatApp

final class ConversationListStoreTests: XCTestCase {
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
    func testRefreshMapsRecordsAndSortsMostRecentFirst() async throws {
        let harness = try makeHarness()
        harness.service.records = [
            record(peerId: "peer-old", username: "bob", messageId: "msg-old", createdAt: "2026-06-03T10:00:00Z"),
            record(peerId: "peer-new", username: "cora", messageId: "msg-new", createdAt: "2026-06-03T12:00:00Z")
        ]

        await harness.store.refresh()

        XCTAssertEqual(harness.store.conversations.map(\.peerUsername), ["cora", "bob"])
        XCTAssertEqual(harness.store.conversations.first?.lastActivityAt, "2026-06-03T12:00:00Z")
    }

    @MainActor
    func testRefreshIncludesInboundOnlyPeerReturnedByBackend() async throws {
        let harness = try makeHarness()
        harness.service.records = [
            record(peerId: "peer-inbound", username: "bob", messageId: "msg-from-bob", createdAt: "2026-06-03T12:00:00Z")
        ]

        await harness.store.refresh()

        XCTAssertEqual(harness.store.conversations.map(\.peerUsername), ["bob"])
        XCTAssertEqual(harness.store.conversations.first?.peerId, "peer-inbound")
        XCTAssertEqual(harness.store.conversations.first?.lastMessageId, "msg-from-bob")
    }

    @MainActor
    func testHandleLiveRecordForKnownPeerBumpsAndDoesNotFetchAgain() async throws {
        let harness = try makeHarness()
        harness.service.records = [
            record(peerId: "peer-a", username: "alice-peer", messageId: "msg-a", createdAt: "2026-06-03T10:00:00Z"),
            record(peerId: "peer-b", username: "bob-peer", messageId: "msg-b", createdAt: "2026-06-03T11:00:00Z")
        ]
        await harness.store.refresh()
        XCTAssertEqual(harness.service.fetchCount, 1)

        await harness.store.handleLiveRecord(MessageRecord(
            id: "msg-a-new",
            senderId: "peer-a",
            recipientId: "user-me",
            ciphertext: "ciphertext",
            createdAt: "2026-06-03T12:00:00Z"
        ))

        XCTAssertEqual(harness.service.fetchCount, 1)
        XCTAssertEqual(harness.store.conversations.map(\.peerUsername), ["alice-peer", "bob-peer"])
        XCTAssertEqual(harness.store.conversations.first?.lastMessageId, "msg-a-new")
    }

    @MainActor
    func testHandleLiveRecordForUnknownPeerRefreshesOnce() async throws {
        let harness = try makeHarness()
        harness.service.records = [
            record(peerId: "peer-known", username: "known", messageId: "msg-known", createdAt: "2026-06-03T10:00:00Z")
        ]
        await harness.store.refresh()
        XCTAssertEqual(harness.service.fetchCount, 1)

        harness.service.records = [
            record(peerId: "peer-new", username: "new-peer", messageId: "msg-new", createdAt: "2026-06-03T12:00:00Z"),
            record(peerId: "peer-known", username: "known", messageId: "msg-known", createdAt: "2026-06-03T10:00:00Z")
        ]
        await harness.store.handleLiveRecord(MessageRecord(
            id: "msg-new",
            senderId: "peer-new",
            recipientId: "user-me",
            ciphertext: "ciphertext",
            createdAt: "2026-06-03T12:00:00Z"
        ))

        XCTAssertEqual(harness.service.fetchCount, 2)
        XCTAssertEqual(harness.store.conversations.map(\.peerUsername), ["new-peer", "known"])
    }

    @MainActor
    func testSubscribeConsumesInjectedLiveStream() async throws {
        let liveRecord = MessageRecord(
            id: "msg-live",
            senderId: "peer-a",
            recipientId: "user-me",
            ciphertext: "ciphertext",
            createdAt: "2026-06-03T12:00:00Z"
        )
        let harness = try makeHarness(liveRecords: [liveRecord])
        harness.service.records = [
            record(peerId: "peer-a", username: "alice-peer", messageId: "msg-a", createdAt: "2026-06-03T10:00:00Z")
        ]
        await harness.store.refresh()

        harness.store.subscribe()
        try await waitForLastMessageId("msg-live", in: harness.store)

        XCTAssertEqual(harness.store.conversations.first?.lastMessageId, "msg-live")
        XCTAssertEqual(harness.service.fetchCount, 1)
        harness.store.cancelSubscription()
    }

    @MainActor
    func testHandleLiveRecordUpdatesLastActivityAtOnKnownPeer() async throws {
        let harness = try makeHarness()
        harness.service.records = [
            record(peerId: "peer-bob", username: "bob", messageId: "msg-1", createdAt: "2024-01-01T00:00:00Z")
        ]
        await harness.store.refresh()
        XCTAssertEqual(harness.service.fetchCount, 1)

        await harness.store.handleLiveRecord(MessageRecord(
            id: "msg-2",
            senderId: "peer-bob",
            recipientId: "user-me",
            ciphertext: "ciphertext",
            createdAt: "2024-06-01T00:00:00Z"
        ))

        XCTAssertEqual(harness.store.conversations.first?.lastActivityAt, "2024-06-01T00:00:00Z")
        XCTAssertEqual(harness.service.fetchCount, 1)
    }

    @MainActor
    func testSelectedPeerUsernameRoundTrips() throws {
        let harness = try makeHarness()

        harness.store.selectedPeerUsername = "bob"

        XCTAssertEqual(harness.store.selectedPeerUsername, "bob")
    }

    @MainActor
    private func makeHarness(liveRecords: [MessageRecord] = []) throws -> Harness {
        let sessionKeychain = KeychainStore(
            service: "\(KeychainStore.defaultService).conversation-list.tests.\(UUID().uuidString)",
            account: "\(KeychainStore.defaultAccount).session.tests",
            usesDataProtectionKeychain: false
        )
        keychainStores.append(sessionKeychain)
        let sessionStore = SessionStore(keychainStore: sessionKeychain)
        try sessionStore.save("token-1")

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("conversation-list-store-\(UUID().uuidString)", isDirectory: true)
        cleanupURLs.append(directory)
        let accountStore = LocalAccountStore(directory: directory)
        try accountStore.save(LocalAccount(username: "me", publicKeyBase64: "public-key", userId: "user-me"))

        let service = FakeConversationsService()
        let store = ConversationListStore(
            service: service,
            sessionStore: sessionStore,
            accountStore: accountStore,
            makeLiveStream: { _ in
                AsyncThrowingStream { continuation in
                    for record in liveRecords {
                        continuation.yield(record)
                    }
                    continuation.finish()
                }
            }
        )
        return Harness(store: store, service: service)
    }

    @MainActor
    private func waitForLastMessageId(_ messageId: String, in store: ConversationListStore) async throws {
        for _ in 0..<20 {
            let current = store.conversations.first?.lastMessageId
            if current == messageId {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Timed out waiting for conversation list live update.")
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

private struct Harness {
    let store: ConversationListStore
    let service: FakeConversationsService
}

private final class FakeConversationsService: ConversationsService, @unchecked Sendable {
    var records: [ConversationSummary] = []
    private(set) var fetchCount = 0

    func conversations(token: String) async -> [ConversationSummary] {
        fetchCount += 1
        return records
    }
}
