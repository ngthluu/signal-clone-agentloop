import Foundation

struct DirectConversationSelection: Identifiable, Equatable, Sendable {
    let rowId: String
    let requestedUsername: String
    let knownPeerUserId: String?

    var id: String { rowId }

    init(rowId: String, requestedUsername: String, knownPeerUserId: String?) {
        self.rowId = rowId
        self.requestedUsername = requestedUsername
        self.knownPeerUserId = knownPeerUserId
    }

    init(peerUserId: String?, peerUsername: String) {
        self.rowId = peerUserId.map { "direct:\($0)" } ?? "direct:new:\(peerUsername)"
        self.requestedUsername = peerUsername
        self.knownPeerUserId = peerUserId
    }
}

enum ConversationsDetailRoute: Equatable {
    case none
    case direct(DirectConversationSelection)
    case group

    static func resolve(
        selectedRow: ChatListItem?,
        selectedDirect: DirectConversationSelection?
    ) -> ConversationsDetailRoute {
        if selectedRow?.kind == .group {
            return .group
        }
        if let selectedDirect {
            return .direct(selectedDirect)
        }
        return .none
    }
}
