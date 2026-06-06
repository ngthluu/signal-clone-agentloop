import XCTest
@testable import ChatApp

final class ConversationHistoryPresentationTests: XCTestCase {
    func testResolverMapsIdle() {
        XCTAssertEqual(
            ConversationHistoryPresentationState.resolve(
                detailState: .idle,
                messages: []
            ),
            .idle
        )
    }

    func testResolverMapsLoading() {
        XCTAssertEqual(
            ConversationHistoryPresentationState.resolve(
                detailState: .loading(peerUsername: "bob"),
                messages: []
            ),
            .loading(peerUsername: "bob")
        )
    }

    func testResolverMapsFailed() {
        XCTAssertEqual(
            ConversationHistoryPresentationState.resolve(
                detailState: .failed(peerUsername: "bob", message: "User not found."),
                messages: []
            ),
            .failed(peerUsername: "bob", message: "User not found.")
        )
    }

    func testResolverMapsLoadedEmpty() {
        XCTAssertEqual(
            ConversationHistoryPresentationState.resolve(
                detailState: .loaded(peerUsername: "bob", isEmpty: true),
                messages: []
            ),
            .empty(peerUsername: "bob")
        )
    }

    func testResolverMapsNonEmptyMessages() {
        let messages = [
            DisplayMessage(id: "msg-1", isMine: false, text: "hello", createdAt: "2026-06-03T10:00:00Z")
        ]

        XCTAssertEqual(
            ConversationHistoryPresentationState.resolve(
                detailState: .idle,
                messages: messages
            ),
            .messages
        )
    }

    func testResolverFallsBackToIdleForInconsistentLoadedNonEmptyState() {
        XCTAssertEqual(
            ConversationHistoryPresentationState.resolve(
                detailState: .loaded(peerUsername: "bob", isEmpty: false),
                messages: []
            ),
            .idle
        )
    }
}
