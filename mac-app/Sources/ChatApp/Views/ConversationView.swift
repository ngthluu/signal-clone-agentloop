import AppKit
import SwiftUI

struct ConversationView: View {
    @ObservedObject var coordinator: DMCoordinator
    var onStartConversation: ((String) async -> Void)? = nil
    var onSend: ((String) async -> Void)? = nil
    var onSendAttachment: ((Data, String, String) async -> Void)? = nil

    @State private var username = ""
    @State private var draft = ""
    private let maxAttachmentBytes = 10 * 1024 * 1024

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
                            messageBubble(message)
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
                Button {
                    pickAttachment()
                } label: {
                    Image(systemName: "paperclip")
                }
                .help("Attach file")
                .disabled(coordinator.peerUsername == nil)
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
