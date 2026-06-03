import SwiftUI

struct ConversationListView: View {
    @ObservedObject var store: ConversationListStore
    @State private var newUsername = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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

    private func selectNewConversation() {
        let username = newUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty else {
            return
        }
        store.selectedPeerUsername = username
        newUsername = ""
    }
}
