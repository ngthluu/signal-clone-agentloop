import CryptoKit
import Foundation

struct DisplayMessage: Identifiable, Equatable {
    let id: String
    let isMine: Bool
    let text: String
    let attachment: AttachmentInfo?
    let createdAt: String

    init(id: String, isMine: Bool, text: String, attachment: AttachmentInfo? = nil, createdAt: String) {
        self.id = id
        self.isMine = isMine
        self.text = text
        self.attachment = attachment
        self.createdAt = createdAt
    }
}

enum DMDetailState: Equatable {
    case idle
    case loading(peerUsername: String)
    case loaded(peerUsername: String, isEmpty: Bool)
    case failed(peerUsername: String, message: String)
}

private struct DMSelectedSession: Equatable {
    let generation: Int
    let selection: DirectConversationSelection
    let peerUserId: String
    let verifiedUsername: String
}

@MainActor
final class DMCoordinator: ObservableObject {
    @Published var messages: [DisplayMessage] = []
    @Published var peerUsername: String?
    @Published var statusMessage: String = ""
    @Published private(set) var detailState: DMDetailState = .idle

    private let identityProvider: IdentityProviding
    private let x25519KeyManager: X25519KeyManager
    private let sessionStore: SessionStore
    private let accountStore: LocalAccountStore
    private let service: MessageService
    private let crypto: MessageCrypto
    private let attachmentService: AttachmentService
    private let fileCrypto: FileCrypto
    private var peerPrekey: PrekeyResponse?
    private var liveTask: Task<Void, Never>?
    private var selectedGeneration = 0
    private var selectedSession: DMSelectedSession?
    private static let maxAttachmentBytes = 10 * 1024 * 1024

    init(
        identityProvider: IdentityProviding,
        x25519KeyManager: X25519KeyManager,
        sessionStore: SessionStore,
        accountStore: LocalAccountStore,
        service: MessageService,
        crypto: MessageCrypto,
        attachmentService: AttachmentService = HTTPAttachmentService(),
        fileCrypto: FileCrypto = FileCrypto()
    ) {
        self.identityProvider = identityProvider
        self.x25519KeyManager = x25519KeyManager
        self.sessionStore = sessionStore
        self.accountStore = accountStore
        self.service = service
        self.crypto = crypto
        self.attachmentService = attachmentService
        self.fileCrypto = fileCrypto
    }

    func publishOwnPrekey() async {
        guard let token = sessionStore.load() else {
            statusMessage = "Sign in before publishing message keys."
            return
        }

        do {
            let identity = try identityProvider.loadOrCreate()
            let privateKey = try x25519KeyManager.loadOrCreate()
            let publicKey = privateKey.publicKey.rawRepresentation.base64EncodedString()
            let signature = crypto.signPrekey(x25519PublicKeyBase64: publicKey, with: identity)
            if await service.publishPrekey(token: token, x25519PublicKey: publicKey, signature: signature) {
                statusMessage = ""
            } else {
                statusMessage = "Could not publish message keys."
            }
        } catch {
            statusMessage = "Could not publish message keys."
        }
    }

    func startConversation(withUsername username: String) async {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            closeSelectedConversation()
            statusMessage = "Enter a username."
            return
        }

        await open(DirectConversationSelection(peerUserId: nil, peerUsername: trimmed))
    }

    func open(_ selection: DirectConversationSelection) async {
        let trimmed = selection.requestedUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            closeSelectedConversation()
            statusMessage = "Enter a username."
            return
        }

        selectedGeneration += 1
        let generation = selectedGeneration
        selectedSession = nil
        self.peerUsername = nil
        peerPrekey = nil
        messages = []
        statusMessage = ""
        cancelLiveSubscription()
        detailState = .loading(peerUsername: trimmed)

        guard let token = sessionStore.load() else {
            failOpen(generation: generation, peerUsername: trimmed, message: "Sign in before starting a DM.")
            return
        }

        guard let prekey = await service.fetchPrekey(username: trimmed, token: token) else {
            failOpen(generation: generation, peerUsername: trimmed, message: "User not found.")
            return
        }

        guard Self.verify(prekey: prekey),
              selection.knownPeerUserId == nil || prekey.userId == selection.knownPeerUserId else {
            failOpen(generation: generation, peerUsername: trimmed, message: "Could not verify \(prekey.username)'s keys.")
            return
        }

        guard selectedGeneration == generation else {
            return
        }

        let session = DMSelectedSession(
            generation: generation,
            selection: selection,
            peerUserId: prekey.userId,
            verifiedUsername: prekey.username
        )
        selectedSession = session
        peerUsername = prekey.username
        peerPrekey = prekey
        statusMessage = ""
        await loadHistory(session: session, token: token, replace: true)
        guard isCurrent(session) else {
            return
        }
        subscribeLive(session: session, token: token, catchUpBeforeStream: false)
    }

    func loadHistory() async {
        guard let token = sessionStore.load(), let session = selectedSession else {
            return
        }

        await loadHistory(session: session, token: token, replace: true)
    }

    private func loadHistory(session: DMSelectedSession, token: String, replace: Bool) async {
        let username = session.verifiedUsername

        do {
            let localPrivate = try x25519KeyManager.loadOrCreate()
            let localUserId = accountStore.currentAccount()?.userId
            let records = await service.history(token: token, withUsername: username, since: nil)
            let displayMessages = records.compactMap { record in
                do {
                    let plaintext = try crypto.decrypt(record.ciphertext, withLocalX25519: localPrivate)
                    return Self.displayMessage(
                        id: record.id,
                        isMine: record.senderId == localUserId,
                        plaintext: plaintext,
                        createdAt: record.createdAt
                    )
                } catch {
                    print("Skipping undecryptable DM \(record.id).")
                    return nil
                }
            }

            guard isCurrent(session) else {
                return
            }

            if replace {
                messages = displayMessages
            } else {
                merge(displayMessages)
            }
            detailState = .loaded(peerUsername: session.verifiedUsername, isEmpty: messages.isEmpty)
            statusMessage = ""
        } catch {
            guard isCurrent(session) else {
                return
            }
            statusMessage = "Could not load messages."
            detailState = .failed(peerUsername: session.verifiedUsername, message: statusMessage)
        }
    }

    func sendAttachment(data: Data, filename: String, mime: String) async {
        guard data.count <= Self.maxAttachmentBytes else {
            statusMessage = "Attachment must be 10 MB or smaller."
            return
        }
        guard let token = sessionStore.load() else {
            statusMessage = "Sign in before sending an attachment."
            return
        }
        guard let username = peerUsername else {
            statusMessage = "Start a DM first."
            return
        }
        guard let prekey = await verifiedPeerPrekey(username: username, token: token) else {
            return
        }

        do {
            let fileKey = fileCrypto.newFileKey()
            let encryptedBlob = try fileCrypto.encrypt(data, using: fileKey)
            guard let attachmentId = await attachmentService.upload(token: token, encryptedBlob: encryptedBlob) else {
                statusMessage = "Could not upload attachment."
                return
            }
            let descriptor = AttachmentDescriptor(
                attachmentId: attachmentId,
                fileKey: Self.base64(fileKey),
                filename: filename,
                mime: mime,
                size: data.count
            )
            let ciphertext = try crypto.encrypt(descriptor.encodedJSON(), toRecipientX25519: prekey.x25519PublicKey)
            switch await service.send(token: token, recipientUsername: username, ciphertext: ciphertext) {
            case let .success(messageId, createdAt):
                messages.append(DisplayMessage(
                    id: messageId,
                    isMine: true,
                    text: filename,
                    attachment: AttachmentInfo(descriptor: descriptor),
                    createdAt: createdAt
                ))
                statusMessage = ""
                detailState = .loaded(peerUsername: username, isEmpty: false)
            case .recipientNotFound:
                statusMessage = "User not found."
            case let .failure(message):
                statusMessage = message.isEmpty ? "Could not send attachment." : message
            }
        } catch {
            statusMessage = "Could not encrypt attachment."
        }
    }

    func downloadAttachment(_ info: AttachmentInfo) async -> Data? {
        guard let token = sessionStore.load() else {
            statusMessage = "Sign in before downloading an attachment."
            return nil
        }
        guard
            let encryptedBlob = await attachmentService.download(token: token, attachmentId: info.attachmentId),
            let keyBytes = Data(base64Encoded: info.fileKey)
        else {
            statusMessage = "Could not download attachment."
            return nil
        }

        do {
            statusMessage = ""
            return try fileCrypto.decrypt(encryptedBlob, using: SymmetricKey(data: keyBytes))
        } catch {
            statusMessage = "Could not decrypt attachment."
            return nil
        }
    }

    func send(text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        guard let token = sessionStore.load() else {
            statusMessage = "Sign in before sending a message."
            return
        }
        guard let username = peerUsername else {
            statusMessage = "Start a DM first."
            return
        }

        guard let prekey = await verifiedPeerPrekey(username: username, token: token) else {
            return
        }

        do {
            let ciphertext = try crypto.encrypt(Data(trimmed.utf8), toRecipientX25519: prekey.x25519PublicKey)
            switch await service.send(token: token, recipientUsername: username, ciphertext: ciphertext) {
            case let .success(messageId, createdAt):
                messages.append(DisplayMessage(id: messageId, isMine: true, text: trimmed, createdAt: createdAt))
                statusMessage = ""
                detailState = .loaded(peerUsername: username, isEmpty: false)
            case .recipientNotFound:
                statusMessage = "User not found."
            case let .failure(message):
                statusMessage = message.isEmpty ? "Could not send message." : message
            }
        } catch {
            statusMessage = "Could not encrypt message."
        }
    }

    func subscribeLive() async {
        guard let token = sessionStore.load(),
              accountStore.currentAccount() != nil,
              let session = selectedSession else {
            return
        }

        await loadHistory(session: session, token: token, replace: false)
        guard isCurrent(session) else {
            return
        }
        subscribeLive(session: session, token: token, catchUpBeforeStream: false)
        await Task.yield()
    }

    private func subscribeLive(session: DMSelectedSession, token: String, catchUpBeforeStream: Bool) {
        cancelLiveSubscription()
        liveTask = Task { [weak self, service, crypto, x25519KeyManager, accountStore] in
            do {
                if catchUpBeforeStream {
                    await self?.loadHistory(session: session, token: token, replace: false)
                }
                let localPrivate = try x25519KeyManager.loadOrCreate()
                guard let localUserId = accountStore.currentAccount()?.userId else {
                    return
                }
                for try await record in service.liveMessages(token: token) {
                    if Task.isCancelled {
                        break
                    }
                    guard record.recipientId == localUserId,
                          record.senderId == session.peerUserId else {
                        continue
                    }
                    let plaintext: Data
                    do {
                        plaintext = try crypto.decrypt(record.ciphertext, withLocalX25519: localPrivate)
                    } catch {
                        print("Skipping undecryptable live DM \(record.id).")
                        continue
                    }
                    guard let display = DMCoordinator.displayMessage(
                        id: record.id,
                        isMine: false,
                        plaintext: plaintext,
                        createdAt: record.createdAt
                    ) else {
                        continue
                    }
                    await MainActor.run {
                        guard let self,
                              self.isCurrent(session),
                              !self.messages.contains(where: { $0.id == record.id }) else {
                            return
                        }
                        self.messages.append(display)
                        self.detailState = .loaded(peerUsername: session.verifiedUsername, isEmpty: false)
                        self.statusMessage = ""
                    }
                }
            } catch {
                await MainActor.run {
                    guard let self, !Task.isCancelled, self.isCurrent(session) else {
                        return
                    }
                    self.statusMessage = "Live message stream disconnected."
                    self.detailState = .failed(peerUsername: session.verifiedUsername, message: self.statusMessage)
                }
            }
        }
    }

    func cancelLiveSubscription() {
        liveTask?.cancel()
        liveTask = nil
    }

    func closeSelectedConversation() {
        selectedGeneration += 1
        selectedSession = nil
        cancelLiveSubscription()
        self.peerUsername = nil
        peerPrekey = nil
        messages = []
        statusMessage = ""
        detailState = .idle
    }

    func close() {
        closeSelectedConversation()
    }

    private func verifiedPeerPrekey(username: String, token: String) async -> PrekeyResponse? {
        if let peerPrekey, peerPrekey.username == username, Self.verify(prekey: peerPrekey) {
            return peerPrekey
        }

        guard let prekey = await service.fetchPrekey(username: username, token: token) else {
            statusMessage = "User not found."
            return nil
        }
        guard Self.verify(prekey: prekey) else {
            statusMessage = "Could not verify \(prekey.username)'s keys."
            return nil
        }

        peerPrekey = prekey
        return prekey
    }

    private static func verify(prekey: PrekeyResponse) -> Bool {
        MessageCrypto.verifyPrekey(
            x25519PublicKeyBase64: prekey.x25519PublicKey,
            signatureBase64: prekey.keySignature,
            identityPublicKeyBase64: prekey.identityPublicKey
        )
    }

    private static func displayMessage(id: String, isMine: Bool, plaintext: Data, createdAt: String) -> DisplayMessage? {
        if let descriptor = AttachmentDescriptor.decode(plaintext) {
            return DisplayMessage(
                id: id,
                isMine: isMine,
                text: descriptor.filename,
                attachment: AttachmentInfo(descriptor: descriptor),
                createdAt: createdAt
            )
        }

        guard let text = String(data: plaintext, encoding: .utf8) else {
            return nil
        }
        return DisplayMessage(id: id, isMine: isMine, text: text, createdAt: createdAt)
    }

    private static func base64(_ key: SymmetricKey) -> String {
        key.withUnsafeBytes { Data($0).base64EncodedString() }
    }

    private func failOpen(generation: Int, peerUsername: String, message: String) {
        guard selectedGeneration == generation else {
            return
        }
        self.peerUsername = nil
        peerPrekey = nil
        messages = []
        statusMessage = message
        detailState = .failed(peerUsername: peerUsername, message: message)
    }

    private func isCurrent(_ session: DMSelectedSession) -> Bool {
        selectedSession == session
    }

    private func merge(_ incoming: [DisplayMessage]) {
        for message in incoming where !messages.contains(where: { $0.id == message.id }) {
            messages.append(message)
        }
    }

    deinit {
        liveTask?.cancel()
    }
}
