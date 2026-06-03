import SwiftUI

struct ConversationView: View {
    @ObservedObject var coordinator: DMCoordinator
    var onStartConversation: ((String) async -> Void)? = nil
    var onSend: ((String) async -> Void)? = nil

    @State private var username = ""
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                TextField("Username", text: $username)
                    .textFieldStyle(.roundedBorder)
                Button("Start") {
                    Task {
                        if let onStartConversation {
                            await onStartConversation(username)
                        } else {
                            await coordinator.startConversation(withUsername: username)
                        }
                    }
                }
            }

            Text(coordinator.peerUsername.map { "DM with \($0)" } ?? "Start a DM")
                .font(.headline)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(coordinator.messages) { message in
                        HStack {
                            if message.isMine {
                                Spacer(minLength: 48)
                            }
                            Text(message.text)
                                .padding(.vertical, 7)
                                .padding(.horizontal, 10)
                                .background(message.isMine ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            if !message.isMine {
                                Spacer(minLength: 48)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 220)

            HStack(spacing: 8) {
                TextField("Message", text: $draft)
                    .textFieldStyle(.roundedBorder)
                Button("Send") {
                    let text = draft
                    draft = ""
                    Task {
                        if let onSend {
                            await onSend(text)
                        } else {
                            await coordinator.send(text: text)
                        }
                    }
                }
                .disabled(coordinator.peerUsername == nil || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Text(coordinator.statusMessage)
                .foregroundStyle(.secondary)
                .frame(minHeight: 20, alignment: .leading)
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 420)
    }
}
