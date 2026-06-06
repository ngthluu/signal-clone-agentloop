import Foundation

@MainActor
final class ChatListStore: ObservableObject {
    @Published private(set) var rows: [ChatListItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false
    @Published var selectedRow: ChatListItem?
    @Published private(set) var selectedDirectConversation: DirectConversationSelection?

    let conversationListStore: ConversationListStore
    let groupCoordinator: GroupCoordinator

    init(
        conversationListStore: ConversationListStore,
        groupCoordinator: GroupCoordinator
    ) {
        self.conversationListStore = conversationListStore
        self.groupCoordinator = groupCoordinator
        self.conversationListStore.onConversationsChanged = { [weak self] in
            self?.rebuildRows()
        }
    }

    func refresh() async {
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }

        await conversationListStore.refresh()
        await groupCoordinator.refreshGroups()
        rebuildRows()
    }

    func rebuildRows() {
        let previousSelection = selectedRow
        let previousDirectSelection = selectedDirectConversation
        let directRows = conversationListStore.conversations.map(ChatListItem.direct)
        let groupRows = groupCoordinator.groups.map(ChatListItem.group)
        rows = ChatList.sorted(directRows + groupRows)

        if let previousSelection {
            if let exact = rows.first(where: { $0.id == previousSelection.id }) {
                selectedRow = exact
            } else if previousSelection.kind == .direct, let username = previousSelection.peerUsername {
                selectedRow = rows.first { $0.peerUsername == username }
            } else {
                selectedRow = nil
            }
        }

        if let selectedRow, let selection = selectedRow.directSelection {
            selectedDirectConversation = selection
        } else if let previousDirectSelection {
            selectedDirectConversation = rows
                .first { $0.peerUsername == previousDirectSelection.requestedUsername }?
                .directSelection ?? previousDirectSelection
        } else {
            selectedDirectConversation = nil
        }
    }

    var route: ConversationsDetailRoute {
        ConversationsDetailRoute.resolve(
            selectedRow: selectedRow,
            selectedDirect: selectedDirectConversation
        )
    }

    func isSelected(_ row: ChatListItem) -> Bool {
        return selectedRow?.id == row.id
    }

    func select(_ row: ChatListItem) async {
        switch row.kind {
        case .direct:
            selectedRow = row
            selectedDirectConversation = row.directSelection
            groupCoordinator.clearOpenGroupState()
            conversationListStore.selectedPeerUsername = row.peerUsername
        case .group:
            selectedRow = nil
            selectedDirectConversation = nil
            groupCoordinator.clearOpenGroupState()
            conversationListStore.selectedPeerUsername = nil
            if let groupId = row.groupId {
                await groupCoordinator.openGroup(id: groupId)
                if groupCoordinator.groupId == groupId {
                    selectedRow = row
                }
            }
        }
    }

    func selectDirect(username: String) async {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        if let row = rows.first(where: { $0.peerUsername == trimmed }) {
            await select(row)
            return
        }

        await select(ChatListItem(
            id: "direct:new:\(trimmed)",
            kind: .direct,
            title: trimmed,
            activityAt: "",
            peerUsername: trimmed,
            groupId: nil,
            detail: "New conversation"
        ))
    }

    @discardableResult
    func createGroup(name: String, memberUsernames: [String]) async -> Bool {
        let previousGroupId = groupCoordinator.groupId
        await groupCoordinator.createGroup(name: name, memberUsernames: memberUsernames)
        await refresh()
        guard let groupId = groupCoordinator.groupId,
              groupId != previousGroupId,
              let row = rows.first(where: { $0.groupId == groupId }) else {
            return false
        }
        selectedRow = row
        selectedDirectConversation = nil
        conversationListStore.selectedPeerUsername = nil
        return true
    }

    func noteDirectActivity(peerUsername: String, message: DisplayMessage) async {
        if let summary = conversationListStore.summary(forPeerUsername: peerUsername) {
            conversationListStore.noteLocalActivity(
                peerId: summary.peerId,
                peerUsername: summary.peerUsername,
                at: message.createdAt,
                lastMessageId: message.id
            )
            rebuildRows()
        } else {
            await refresh()
        }
    }
}
