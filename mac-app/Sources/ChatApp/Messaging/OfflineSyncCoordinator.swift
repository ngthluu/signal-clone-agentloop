import CryptoKit
import Foundation

@MainActor
final class OfflineSyncCoordinator: ObservableObject {
    private let service: MessageService
    private let crypto: MessageCrypto
    private let x25519KeyManager: X25519KeyManager
    private let sessionStore: SessionStore
    private let accountStore: LocalAccountStore
    private let cursorStore: SyncCursorStore
    let messageStore: LocalMessageStore

    private var peerUsernamesById: [String: String] = [:]
    private var liveTask: Task<Void, Never>?

    init(
        service: MessageService,
        crypto: MessageCrypto,
        x25519KeyManager: X25519KeyManager,
        sessionStore: SessionStore,
        accountStore: LocalAccountStore,
        cursorStore: SyncCursorStore,
        messageStore: LocalMessageStore
    ) {
        self.service = service
        self.crypto = crypto
        self.x25519KeyManager = x25519KeyManager
        self.sessionStore = sessionStore
        self.accountStore = accountStore
        self.cursorStore = cursorStore
        self.messageStore = messageStore
    }

    func syncOnLaunch() async {
        guard let token = sessionStore.load(), accountStore.currentAccount() != nil else {
            return
        }

        let conversations = await service.conversations(token: token)
        peerUsernamesById = Dictionary(
            uniqueKeysWithValues: conversations.map { ($0.peerUserId, $0.peerUsername) }
        )

        for conversation in conversations {
            let records = await service.history(token: token, withUsername: conversation.peerUsername, since: nil)
            await apply(records: records, peerUsername: conversation.peerUsername, seq: nil)
        }

        await syncInbox(token: token)
        subscribeLive(token: token)
    }

    func reconnect() async {
        guard let token = sessionStore.load() else {
            return
        }

        await syncInbox(token: token)
        subscribeLive(token: token)
    }

    func cancelLiveSubscription() {
        liveTask?.cancel()
        liveTask = nil
    }

    private func syncInbox(token: String) async {
        guard let account = accountStore.currentAccount() else {
            return
        }

        var cursor = cursorStore.load(userId: account.userId)
        while true {
            let page = await service.inbox(token: token, since: cursor)
            for inboxRecord in page.messages.sorted(by: { $0.seq < $1.seq }) {
                await apply(record: inboxRecord.messageRecord, peerUsername: peerUsernamesById[inboxRecord.senderId], seq: inboxRecord.seq)
            }

            guard let nextCursor = page.nextCursor else {
                break
            }

            cursor = nextCursor
            try? cursorStore.save(userId: account.userId, seq: nextCursor)
        }
    }

    private func subscribeLive(token: String) {
        cancelLiveSubscription()
        liveTask = Task { [weak self, service] in
            do {
                for try await record in service.liveMessages(token: token) {
                    if Task.isCancelled {
                        break
                    }
                    await self?.apply(record: record, peerUsername: nil, seq: nil)
                }
            } catch {
                return
            }
        }
    }

    private func apply(records: [MessageRecord], peerUsername: String?, seq: Int?) async {
        for record in records {
            await apply(record: record, peerUsername: peerUsername, seq: seq)
        }
    }

    private func apply(record: MessageRecord, peerUsername: String?, seq: Int?) async {
        guard let account = accountStore.currentAccount() else {
            return
        }

        do {
            let localPrivate = try x25519KeyManager.loadOrCreate()
            let plaintext = try crypto.decrypt(record.ciphertext, withLocalX25519: localPrivate)
            guard let text = String(data: plaintext, encoding: .utf8) else {
                return
            }

            let peerUserId = record.senderId == account.userId ? record.recipientId : record.senderId
            let knownPeerUsername = peerUsername ?? peerUsernamesById[peerUserId]
            if let knownPeerUsername {
                peerUsernamesById[peerUserId] = knownPeerUsername
            }

            messageStore.append(SyncedMessage(
                id: record.id,
                senderId: record.senderId,
                recipientId: record.recipientId,
                peerUserId: peerUserId,
                peerUsername: knownPeerUsername,
                isMine: record.senderId == account.userId,
                text: text,
                createdAt: record.createdAt,
                seq: seq
            ))
        } catch {
            return
        }
    }

    deinit {
        liveTask?.cancel()
    }
}
