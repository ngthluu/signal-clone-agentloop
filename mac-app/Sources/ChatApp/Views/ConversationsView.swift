import SwiftUI

struct ConversationsView: View {
    @ObservedObject var listStore: ConversationListStore
    @ObservedObject var dmCoordinator: DMCoordinator

    var body: some View {
        NavigationSplitView {
            ConversationListView(store: listStore)
        } detail: {
            if listStore.selectedPeerUsername != nil {
                ConversationView(
                    coordinator: dmCoordinator,
                    onStartConversation: { username in
                        await selectConversation(username)
                    },
                    onSend: { text in
                        await send(text)
                    }
                )
            } else {
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
            await listStore.refresh()
            listStore.subscribe()
            await dmCoordinator.publishOwnPrekey()
        }
        .onDisappear {
            listStore.cancelSubscription()
        }
        .onChange(of: listStore.selectedPeerUsername) { username in
            Task {
                await openSelectedConversation(username)
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
            listStore.selectedPeerUsername = trimmed
            return
        }
        await dmCoordinator.startConversation(withUsername: trimmed)
    }

    private func openSelectedConversation(_ username: String?) async {
        guard let username else {
            dmCoordinator.cancelLiveSubscription()
            return
        }
        await dmCoordinator.startConversation(withUsername: username)
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
            listStore.noteLocalActivity(
                peerId: summary.peerId,
                peerUsername: summary.peerUsername,
                at: sent.createdAt,
                lastMessageId: sent.id
            )
        } else {
            await listStore.refresh()
        }
    }
}
