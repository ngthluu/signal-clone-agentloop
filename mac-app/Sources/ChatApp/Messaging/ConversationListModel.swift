import Foundation

struct ConversationSummary: Codable, Identifiable, Equatable, Sendable {
    let peerUserId: String
    let peerUsername: String
    let lastActivity: String
    let lastSeq: Int
    let lastMessageId: String?

    var id: String {
        peerUserId
    }

    var peerId: String {
        peerUserId
    }

    var lastActivityAt: String {
        lastActivity
    }

    var lastCreatedAt: String {
        lastActivity
    }

    init(peerUserId: String, peerUsername: String, lastActivity: String, lastSeq: Int) {
        self.peerUserId = peerUserId
        self.peerUsername = peerUsername
        self.lastActivity = lastActivity
        self.lastSeq = lastSeq
        self.lastMessageId = nil
    }

    init(peerId: String, peerUsername: String, lastActivityAt: String, lastMessageId: String?) {
        self.peerUserId = peerId
        self.peerUsername = peerUsername
        self.lastActivity = lastActivityAt
        self.lastSeq = 0
        self.lastMessageId = lastMessageId
    }

    enum CodingKeys: String, CodingKey {
        case peerUserId = "peer_user_id"
        case peerUsername = "peer_username"
        case lastActivity = "last_activity"
        case lastSeq = "last_seq"
        case lastMessageId = "last_message_id"
    }
}

enum ConversationList {
    static func sorted(_ items: [ConversationSummary]) -> [ConversationSummary] {
        items.sorted { lhs, rhs in
            if lhs.lastActivityAt == rhs.lastActivityAt {
                return lhs.peerUsername < rhs.peerUsername
            }
            // Backend timestamps are fixed-width RFC3339 UTC strings ending in Z,
            // so lexicographic comparison preserves chronological ordering.
            return lhs.lastActivityAt > rhs.lastActivityAt
        }
    }

    static func upsert(
        _ items: [ConversationSummary],
        peerId: String,
        peerUsername: String,
        activityAt: String,
        lastMessageId: String?
    ) -> [ConversationSummary] {
        var nextItems = items

        if let index = nextItems.firstIndex(where: { $0.peerId == peerId }) {
            let existing = nextItems[index]
            let isNewer = activityAt > existing.lastActivityAt
            nextItems[index] = ConversationSummary(
                peerId: peerId,
                peerUsername: peerUsername,
                lastActivityAt: isNewer ? activityAt : existing.lastActivityAt,
                lastMessageId: isNewer ? lastMessageId : existing.lastMessageId
            )
        } else {
            nextItems.append(
                ConversationSummary(
                    peerId: peerId,
                    peerUsername: peerUsername,
                    lastActivityAt: activityAt,
                    lastMessageId: lastMessageId
                )
            )
        }

        return sorted(nextItems)
    }

    static func peerId(for record: MessageRecord, myUserId: String) -> String {
        record.senderId == myUserId ? record.recipientId : record.senderId
    }

    static func contains(_ items: [ConversationSummary], peerId: String) -> Bool {
        items.contains { $0.peerId == peerId }
    }
}
