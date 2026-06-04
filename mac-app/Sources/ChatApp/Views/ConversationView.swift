import SwiftUI

struct ConversationView: View {
    @ObservedObject var coordinator: DMCoordinator
    var onStartConversation: ((String) async -> Void)? = nil
    var onSend: ((String) async -> Void)? = nil

    @State private var username = ""
    @StateObject private var composer = MessageComposerModel()

    init(
        coordinator: DMCoordinator,
        onStartConversation: ((String) async -> Void)? = nil,
        onSend: ((String) async -> Void)? = nil
    ) {
        self.coordinator = coordinator
        self.onStartConversation = onStartConversation
        self.onSend = onSend
    }

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
                CursorTrackingTextField(
                    "Message",
                    text: $composer.draft,
                    caretUTF16Offset: $composer.caretUTF16Offset,
                    onSubmit: sendCurrentDraft
                )
                Button {
                    composer.togglePicker()
                } label: {
                    Image(systemName: "face.smiling")
                }
                .help("Emoji")
                .popover(isPresented: $composer.isPickerPresented) {
                    EmojiPickerView(model: composer)
                }
                Button("Send") {
                    sendCurrentDraft()
                }
                .disabled(!composer.canSend || coordinator.peerUsername == nil)
            }

            Text(coordinator.statusMessage)
                .foregroundStyle(.secondary)
                .frame(minHeight: 20, alignment: .leading)
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 420)
    }

    @MainActor
    private func sendCurrentDraft() {
        guard composer.canSend, coordinator.peerUsername != nil else {
            return
        }

        let text = composer.draft
        Task {
            if let onSend {
                await onSend(text)
            } else {
                await coordinator.send(text: text)
            }
            composer.reset()
        }
    }
}
