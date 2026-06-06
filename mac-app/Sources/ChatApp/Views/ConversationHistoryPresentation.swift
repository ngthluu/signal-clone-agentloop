import Foundation

enum ConversationHistoryPresentationState: Equatable {
    case idle
    case loading(peerUsername: String)
    case empty(peerUsername: String)
    case failed(peerUsername: String, message: String)
    case messages

    static func resolve(
        detailState: DMDetailState,
        messages: [DisplayMessage]
    ) -> ConversationHistoryPresentationState {
        if !messages.isEmpty {
            return .messages
        }

        switch detailState {
        case .idle:
            return .idle
        case let .loading(peerUsername):
            return .loading(peerUsername: peerUsername)
        case let .loaded(peerUsername, isEmpty):
            return isEmpty ? .empty(peerUsername: peerUsername) : .idle
        case let .failed(peerUsername, message):
            return .failed(peerUsername: peerUsername, message: message)
        }
    }
}
