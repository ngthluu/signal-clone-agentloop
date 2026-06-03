import XCTest
@testable import ChatApp

final class ConversationListModelTests: XCTestCase {
    func testSortedOrdersMostRecentFirstAndTiesByUsername() {
        let items = [
            ConversationSummary(
                peerId: "peer-c",
                peerUsername: "carol",
                lastActivityAt: "2026-06-03T00:00:01Z",
                lastMessageId: "msg-c"
            ),
            ConversationSummary(
                peerId: "peer-b",
                peerUsername: "bob",
                lastActivityAt: "2026-06-03T00:00:03Z",
                lastMessageId: "msg-b"
            ),
            ConversationSummary(
                peerId: "peer-a",
                peerUsername: "alice",
                lastActivityAt: "2026-06-03T00:00:03Z",
                lastMessageId: "msg-a"
            )
        ]

        let sorted = ConversationList.sorted(items)

        XCTAssertEqual(sorted.map(\.peerUsername), ["alice", "bob", "carol"])
    }

    func testUpsertInsertsBumpsToNewerActivityAndNeverRegresses() {
        var items = [
            ConversationSummary(
                peerId: "peer-old",
                peerUsername: "old",
                lastActivityAt: "2026-06-03T00:00:01Z",
                lastMessageId: "msg-old"
            )
        ]

        items = ConversationList.upsert(
            items,
            peerId: "peer-new",
            peerUsername: "new",
            activityAt: "2026-06-03T00:00:02Z",
            lastMessageId: "msg-new"
        )

        XCTAssertEqual(items.map(\.peerUsername), ["new", "old"])
        XCTAssertEqual(items.first?.lastMessageId, "msg-new")

        items = ConversationList.upsert(
            items,
            peerId: "peer-old",
            peerUsername: "old-renamed",
            activityAt: "2026-06-03T00:00:04Z",
            lastMessageId: "msg-newer"
        )

        XCTAssertEqual(items.map(\.peerId), ["peer-old", "peer-new"])
        XCTAssertEqual(items.first?.peerUsername, "old-renamed")
        XCTAssertEqual(items.first?.lastActivityAt, "2026-06-03T00:00:04Z")
        XCTAssertEqual(items.first?.lastMessageId, "msg-newer")

        items = ConversationList.upsert(
            items,
            peerId: "peer-old",
            peerUsername: "old-still-newer",
            activityAt: "2026-06-03T00:00:03Z",
            lastMessageId: "msg-older"
        )

        XCTAssertEqual(items.first?.peerId, "peer-old")
        XCTAssertEqual(items.first?.lastActivityAt, "2026-06-03T00:00:04Z")
        XCTAssertEqual(items.first?.lastMessageId, "msg-newer")
        XCTAssertEqual(items.first?.peerUsername, "old-still-newer")
    }

    func testPeerIdReturnsOtherPartyForInboundAndOutboundRecords() {
        let inbound = MessageRecord(
            id: "msg-in",
            senderId: "peer-1",
            recipientId: "me",
            ciphertext: "ct-in",
            createdAt: "2026-06-03T00:00:01Z"
        )
        let outbound = MessageRecord(
            id: "msg-out",
            senderId: "me",
            recipientId: "peer-2",
            ciphertext: "ct-out",
            createdAt: "2026-06-03T00:00:02Z"
        )

        XCTAssertEqual(ConversationList.peerId(for: inbound, myUserId: "me"), "peer-1")
        XCTAssertEqual(ConversationList.peerId(for: outbound, myUserId: "me"), "peer-2")
    }
}
