import Foundation

struct DisplayMessage: Identifiable, Equatable {
    let id: String
    let isMine: Bool
    let text: String
    let createdAt: String
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
    private var peerPrekey: PrekeyResponse?

    init(
        identityProvider: IdentityProviding,
        x25519KeyManager: X25519KeyManager,
        sessionStore: SessionStore,
        accountStore: LocalAccountStore,
        service: MessageService,
        crypto: MessageCrypto
    ) {
        self.identityProvider = identityProvider
        self.x25519KeyManager = x25519KeyManager
        self.sessionStore = sessionStore
        self.accountStore = accountStore
        self.service = service
        self.crypto = crypto
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
                    guard let text = String(data: plaintext, encoding: .utf8) else {
                        return nil
                    }
                    return DisplayMessage(
                        id: record.id,
                        isMine: record.senderId == localUserId,
                        text: text,
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
}
