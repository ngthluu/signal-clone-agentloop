import Foundation

struct SyncedMessage: Identifiable, Equatable, Sendable {
    let id: String
    let senderId: String
    let recipientId: String
    let peerUserId: String
    let peerUsername: String?
    let isMine: Bool
    let text: String
    let createdAt: String
    let seq: Int?
}

@MainActor
final class LocalMessageStore: ObservableObject {
    @Published private(set) var messages: [SyncedMessage] = []

    func append(_ message: SyncedMessage) {
        guard !messages.contains(where: { $0.id == message.id }) else {
            return
        }
        messages.append(message)
    }

    func conversationMessages(peerUsername: String) -> [SyncedMessage] {
        messages.filter { $0.peerUsername == peerUsername }
    }
}
