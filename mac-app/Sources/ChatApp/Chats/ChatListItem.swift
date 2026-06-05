import Foundation

enum ChatListItemKind: Equatable {
    case direct
    case group
}

struct ChatListItem: Identifiable, Equatable {
    let id: String
    let kind: ChatListItemKind
    let title: String
    let activityAt: String
    let peerUsername: String?
    let groupId: String?
    let detail: String

    static func direct(_ summary: ConversationSummary) -> ChatListItem {
        ChatListItem(
            id: "direct:\(summary.peerId)",
            kind: .direct,
            title: summary.peerUsername,
            activityAt: summary.lastActivityAt,
            peerUsername: summary.peerUsername,
            groupId: nil,
            detail: summary.lastActivityAt
        )
    }

    static func group(_ summary: GroupSummary) -> ChatListItem {
        ChatListItem(
            id: "group:\(summary.id)",
            kind: .group,
            title: summary.name,
            activityAt: summary.createdAt,
            peerUsername: nil,
            groupId: summary.id,
            detail: "Group - \(summary.createdAt)"
        )
    }
}

enum ChatList {
    static func sorted(_ items: [ChatListItem]) -> [ChatListItem] {
        items.sorted { lhs, rhs in
            if lhs.activityAt == rhs.activityAt {
                if lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedSame {
                    return lhs.id < rhs.id
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return lhs.activityAt > rhs.activityAt
        }
    }
}
