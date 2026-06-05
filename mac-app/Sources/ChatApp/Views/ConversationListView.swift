import SwiftUI

enum ConversationListSidebarState: Equatable {
    case loading
    case empty
    case populated

    static func resolve(
        conversations: [ConversationSummary],
        isLoading: Bool,
        hasLoaded: Bool
    ) -> ConversationListSidebarState {
        if !conversations.isEmpty {
            return .populated
        }

        if isLoading || !hasLoaded {
            return .loading
        }

        return .empty
    }
}

struct ConversationListView: View {
    @ObservedObject var store: ConversationListStore
    @State private var newUsername = ""

    private var sidebarState: ConversationListSidebarState {
        ConversationListSidebarState.resolve(
            conversations: store.conversations,
            isLoading: store.isLoading,
            hasLoaded: store.hasLoaded
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sidebarContent

            HStack(spacing: 8) {
                TextField("Username", text: $newUsername)
                    .textFieldStyle(.roundedBorder)
                Button("New") {
                    selectNewConversation()
                }
                .disabled(newUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding([.horizontal, .bottom], 12)
        }
        .navigationTitle("Messages")
        .frame(minWidth: 220)
    }

    @ViewBuilder
    private var sidebarContent: some View {
        switch sidebarState {
        case .loading:
            sidebarPlaceholder {
                ProgressView()
                Text("Loading conversations")
                    .foregroundStyle(.secondary)
            }
        case .empty:
            sidebarPlaceholder {
                Text("No conversations yet")
                    .foregroundStyle(.secondary)
            }
        case .populated:
            List(selection: $store.selectedPeerUsername) {
                ForEach(store.conversations) { conversation in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(conversation.peerUsername)
                            .font(.body)
                        Text(conversation.lastActivityAt)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .tag(Optional(conversation.peerUsername))
                }
            }
        }
    }

    private func sidebarPlaceholder<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 10) {
            Spacer()
            content()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func selectNewConversation() {
        let username = newUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty else {
            return
        }
        store.selectedPeerUsername = username
        newUsername = ""
    }
}
