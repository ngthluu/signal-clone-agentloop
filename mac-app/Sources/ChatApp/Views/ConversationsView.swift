import SwiftUI

struct ConversationsView: View {
    @ObservedObject var chatListStore: ChatListStore
    @ObservedObject var listStore: ConversationListStore
    @ObservedObject var dmCoordinator: DMCoordinator
    @ObservedObject var groupCoordinator: GroupCoordinator

    var body: some View {
        NavigationSplitView {
            ChatListView(store: chatListStore)
        } detail: {
            switch chatListStore.route {
            case .group:
                GroupView(coordinator: groupCoordinator)
            case let .direct(selection):
                ConversationView(
                    coordinator: dmCoordinator,
                    selection: selection,
                    onStartConversation: { username in
                        await selectConversation(username)
                    },
                    onSend: { text in
                        await send(text)
                    }
                )
            case .none:
                VStack(spacing: 10) {
                    Image(systemName: "message")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Select a conversation")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 520, minHeight: 420)
            }
        }
        .task {
            await chatListStore.refresh()
            listStore.subscribe()
            await dmCoordinator.publishOwnPrekey()
        }
        .onDisappear {
            listStore.cancelSubscription()
        }
        .onChange(of: chatListStore.selectedDirectConversation) { selection in
            Task {
                await openSelectedConversation(selection)
            }
        }
    }

    private func selectConversation(_ username: String) async {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            await dmCoordinator.startConversation(withUsername: trimmed)
            return
        }

        if listStore.selectedPeerUsername != trimmed {
            await chatListStore.selectDirect(username: trimmed)
            return
        }
        await dmCoordinator.startConversation(withUsername: trimmed)
    }

    private func openSelectedConversation(_ selection: DirectConversationSelection?) async {
        guard let selection else {
            dmCoordinator.closeSelectedConversation()
            return
        }
        await dmCoordinator.open(selection)
    }

    private func send(_ text: String) async {
        let peerUsername = dmCoordinator.peerUsername ?? listStore.selectedPeerUsername
        let beforeCount = dmCoordinator.messages.count

        await dmCoordinator.send(text: text)

        guard
            dmCoordinator.messages.count > beforeCount,
            let sent = dmCoordinator.messages.last,
            sent.isMine,
            let peerUsername
        else {
            return
        }

        if let summary = listStore.summary(forPeerUsername: peerUsername) {
            await chatListStore.noteDirectActivity(peerUsername: summary.peerUsername, message: sent)
        } else {
            await chatListStore.refresh()
        }
    }
}
