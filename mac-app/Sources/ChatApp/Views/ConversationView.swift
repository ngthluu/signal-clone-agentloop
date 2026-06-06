import AppKit
import SwiftUI

struct ConversationView: View {
    @ObservedObject var coordinator: DMCoordinator
    let selection: DirectConversationSelection?
    var onStartConversation: ((String) async -> Void)? = nil
    var onSend: ((String) async -> Void)? = nil
    var onSendAttachment: ((Data, String, String) async -> Void)? = nil

    @State private var username = ""
    @StateObject private var composer = MessageComposerModel()
    private let maxAttachmentBytes = 10 * 1024 * 1024

    init(
        coordinator: DMCoordinator,
        selection: DirectConversationSelection? = nil,
        onStartConversation: ((String) async -> Void)? = nil,
        onSend: ((String) async -> Void)? = nil,
        onSendAttachment: ((Data, String, String) async -> Void)? = nil
    ) {
        self.coordinator = coordinator
        self.selection = selection
        self.onStartConversation = onStartConversation
        self.onSend = onSend
        self.onSendAttachment = onSendAttachment
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

            Text(selection.map { "DM with \($0.requestedUsername)" } ?? coordinator.peerUsername.map { "DM with \($0)" } ?? "Start a DM")
                .font(.headline)

            historyContent
                .frame(minHeight: 220)

            HStack(spacing: 8) {
                Button {
                    pickAttachment()
                } label: {
                    Image(systemName: "paperclip")
                }
                .help("Attach file")
                .disabled(coordinator.peerUsername == nil)
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

    private var presentation: ConversationHistoryPresentationState {
        ConversationHistoryPresentationState.resolve(
            detailState: coordinator.detailState,
            messages: coordinator.messages
        )
    }

    @ViewBuilder
    private var historyContent: some View {
        ScrollView {
            switch presentation {
            case .idle:
                centeredHistoryPlaceholder(systemName: "message", text: "Select a conversation")
            case .loading:
                centeredHistoryPlaceholder(systemName: nil, text: "Loading messages") {
                    ProgressView()
                }
            case let .empty(peerUsername):
                VStack(spacing: 6) {
                    Spacer()
                    Image(systemName: "bubble.left")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No messages yet")
                        .font(.headline)
                    Text("Send a message to start this conversation.")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .accessibilityLabel("No messages yet with \(peerUsername)")
            case let .failed(_, message):
                centeredHistoryPlaceholder(systemName: "exclamationmark.triangle", text: message)
            case .messages:
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(coordinator.messages) { message in
                        HStack {
                            if message.isMine {
                                Spacer(minLength: 48)
                            }
                            messageBubble(message)
                            if !message.isMine {
                                Spacer(minLength: 48)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func centeredHistoryPlaceholder<Accessory: View>(
        systemName: String?,
        text: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        VStack(spacing: 10) {
            Spacer()
            accessory()
            if let systemName {
                Image(systemName: systemName)
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            Text(text)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func centeredHistoryPlaceholder(systemName: String?, text: String) -> some View {
        centeredHistoryPlaceholder(systemName: systemName, text: text) {
            EmptyView()
        }
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

    @ViewBuilder
    private func messageBubble(_ message: DisplayMessage) -> some View {
        if let attachment = message.attachment {
            VStack(alignment: message.isMine ? .trailing : .leading, spacing: 6) {
                Text(attachment.filename)
                    .font(.body)
                Text(byteCount(attachment.size))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Download") {
                    saveAttachment(attachment)
                }
                .disabled(false)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .background(message.isMine ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Text(message.text)
                .padding(.vertical, 7)
                .padding(.horizontal, 10)
                .background(message.isMine ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func pickAttachment() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            let data = try Data(contentsOf: url)
            guard data.count <= maxAttachmentBytes else {
                coordinator.statusMessage = "Attachment must be 10 MB or smaller."
                return
            }
            let filename = url.lastPathComponent
            let mime = "application/octet-stream"
            Task {
                if let onSendAttachment {
                    await onSendAttachment(data, filename, mime)
                } else {
                    await coordinator.sendAttachment(data: data, filename: filename, mime: mime)
                }
            }
        } catch {
            coordinator.statusMessage = "Could not read attachment."
        }
    }

    private func saveAttachment(_ attachment: AttachmentInfo) {
        Task {
            guard let data = await coordinator.downloadAttachment(attachment) else {
                return
            }
            await MainActor.run {
                let panel = NSSavePanel()
                panel.nameFieldStringValue = attachment.filename
                guard panel.runModal() == .OK, let url = panel.url else {
                    return
                }
                do {
                    try data.write(to: url)
                    coordinator.statusMessage = ""
                } catch {
                    coordinator.statusMessage = "Could not save attachment."
                }
            }
        }
    }

    private func byteCount(_ size: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}
