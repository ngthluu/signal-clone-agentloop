import Foundation

struct ConversationSummary: Identifiable, Equatable, Sendable {
    let peerId: String
    let peerUsername: String
    let lastActivityAt: String
    let lastMessageId: String?

    var id: String {
        peerId
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
