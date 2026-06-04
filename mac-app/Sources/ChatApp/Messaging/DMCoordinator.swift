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

@MainActor
final class DMCoordinator: ObservableObject {
    @Published var messages: [DisplayMessage] = []
    @Published var peerUsername: String?
    @Published var statusMessage: String = ""

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
            statusMessage = "Enter a username."
            return
        }
        guard let token = sessionStore.load() else {
            statusMessage = "Sign in before starting a DM."
            return
        }

        guard let prekey = await service.fetchPrekey(username: trimmed, token: token) else {
            peerUsername = nil
            peerPrekey = nil
            messages = []
            statusMessage = "User not found."
            return
        }

        guard Self.verify(prekey: prekey) else {
            peerUsername = nil
            peerPrekey = nil
            messages = []
            statusMessage = "Could not verify \(prekey.username)'s keys."
            return
        }

        peerUsername = prekey.username
        peerPrekey = prekey
        statusMessage = ""
        await loadHistory()
        await subscribeLive()
    }

    func loadHistory() async {
        guard let token = sessionStore.load(), let peerUsername else {
            return
        }

        do {
            let localPrivate = try x25519KeyManager.loadOrCreate()
            let localUserId = accountStore.currentAccount()?.userId
            let records = await service.history(token: token, withUsername: peerUsername, since: nil)
            messages = records.compactMap { record in
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
        } catch {
            statusMessage = "Could not load messages."
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
        guard let token = sessionStore.load(), accountStore.currentAccount() != nil else {
            return
        }

        cancelLiveSubscription()
        await loadHistory()

        liveTask = Task { [weak self, service, crypto, x25519KeyManager, accountStore] in
            do {
                let localPrivate = try x25519KeyManager.loadOrCreate()
                let localUserId = accountStore.currentAccount()?.userId
                for try await record in service.liveMessages(token: token) {
                    if Task.isCancelled {
                        break
                    }
                    guard record.recipientId == localUserId else {
                        continue
                    }
                    let plaintext = try crypto.decrypt(record.ciphertext, withLocalX25519: localPrivate)
                    guard let display = DMCoordinator.displayMessage(
                        id: record.id,
                        isMine: false,
                        plaintext: plaintext,
                        createdAt: record.createdAt
                    ) else {
                        continue
                    }
                    await MainActor.run {
                        guard let self, !self.messages.contains(where: { $0.id == record.id }) else {
                            return
                        }
                        self.messages.append(display)
                    }
                }
            } catch {
                await MainActor.run {
                    guard let self, !Task.isCancelled else {
                        return
                    }
                    self.statusMessage = "Live message stream disconnected."
                }
            }
        }
        await Task.yield()
    }

    func cancelLiveSubscription() {
        liveTask?.cancel()
        liveTask = nil
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

    deinit {
        liveTask?.cancel()
    }
}
