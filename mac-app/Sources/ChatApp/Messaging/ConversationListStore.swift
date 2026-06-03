import Foundation

@MainActor
final class ConversationListStore: ObservableObject {
    @Published private(set) var conversations: [ConversationSummary] = []
    @Published var selectedPeerUsername: String?

    private let service: ConversationsService
    private let sessionStore: SessionStore
    private let accountStore: LocalAccountStore
    private let makeLiveStream: @Sendable (String) -> AsyncThrowingStream<MessageRecord, Error>
    private var liveTask: Task<Void, Never>?

    init(
        service: ConversationsService,
        sessionStore: SessionStore,
        accountStore: LocalAccountStore,
        makeLiveStream: @escaping @Sendable (String) -> AsyncThrowingStream<MessageRecord, Error>
    ) {
        self.service = service
        self.sessionStore = sessionStore
        self.accountStore = accountStore
        self.makeLiveStream = makeLiveStream
    }

    func refresh() async {
        guard let token = sessionStore.load() else {
            conversations = []
            return
        }

        let records = await service.conversations(token: token)
        let summaries = records.map { record in
            ConversationSummary(
                peerId: record.peerId,
                peerUsername: record.peerUsername,
                lastActivityAt: record.lastCreatedAt,
                lastMessageId: record.lastMessageId
            )
        }
        conversations = ConversationList.sorted(summaries)
    }

    func handleLiveRecord(_ record: MessageRecord) async {
        guard let myUserId = accountStore.currentAccount()?.userId else {
            return
        }

        let peerId = ConversationList.peerId(for: record, myUserId: myUserId)
        guard let existing = conversations.first(where: { $0.peerId == peerId }) else {
            await refresh()
            return
        }

        conversations = ConversationList.upsert(
            conversations,
            peerId: peerId,
            peerUsername: existing.peerUsername,
            activityAt: record.createdAt,
            lastMessageId: record.id
        )
    }

    func subscribe() {
        guard let token = sessionStore.load() else {
            return
        }

        cancelSubscription()
        liveTask = Task { [weak self, makeLiveStream] in
            do {
                for try await record in makeLiveStream(token) {
                    if Task.isCancelled {
                        break
                    }
                    await self?.handleLiveRecord(record)
                }
            } catch {
                if !Task.isCancelled {
                    await self?.refresh()
                }
            }
        }
    }

    func cancelSubscription() {
        liveTask?.cancel()
        liveTask = nil
    }

    func noteLocalActivity(peerId: String, peerUsername: String, at activityAt: String, lastMessageId: String? = nil) {
        conversations = ConversationList.upsert(
            conversations,
            peerId: peerId,
            peerUsername: peerUsername,
            activityAt: activityAt,
            lastMessageId: lastMessageId
        )
    }

    func summary(forPeerUsername username: String) -> ConversationSummary? {
        conversations.first { $0.peerUsername == username }
    }

    deinit {
        liveTask?.cancel()
    }
}
