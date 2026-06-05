import CryptoKit
import Foundation

struct DisplayGroupMessage: Identifiable, Equatable {
    let id: String
    let senderId: String
    let senderName: String
    let isMine: Bool
    let text: String
    let attachment: AttachmentInfo?
    let createdAt: String

    init(
        id: String,
        senderId: String,
        senderName: String? = nil,
        isMine: Bool,
        text: String,
        attachment: AttachmentInfo? = nil,
        createdAt: String
    ) {
        self.id = id
        self.senderId = senderId
        self.senderName = senderName ?? senderId
        self.isMine = isMine
        self.text = text
        self.attachment = attachment
        self.createdAt = createdAt
    }
}

@MainActor
final class GroupCoordinator: ObservableObject {
    @Published var groups: [GroupSummary] = []
    @Published var groupId: String?
    @Published var groupName: String = ""
    @Published var members: [GroupMemberDTO] = []
    @Published var messages: [DisplayGroupMessage] = []
    @Published var statusMessage: String = ""
    @Published var currentEpoch: UInt32 = 0

    private let identityProvider: IdentityProviding
    private let x25519KeyManager: X25519KeyManager
    private let sessionStore: SessionStore
    private let accountStore: LocalAccountStore
    private let messageService: MessageService
    private let groupService: GroupService
    private let crypto: GroupCrypto
    private let attachmentService: AttachmentService
    private let fileCrypto: FileCrypto
    private(set) var epochKeys: [UInt32: Data] = [:]
    private var liveTask: Task<Void, Never>?
    private static let maxAttachmentBytes = 10 * 1024 * 1024

    init(
        identityProvider: IdentityProviding,
        x25519KeyManager: X25519KeyManager,
        sessionStore: SessionStore,
        accountStore: LocalAccountStore,
        messageService: MessageService,
        groupService: GroupService,
        crypto: GroupCrypto,
        attachmentService: AttachmentService = HTTPAttachmentService(),
        fileCrypto: FileCrypto = FileCrypto()
    ) {
        self.identityProvider = identityProvider
        self.x25519KeyManager = x25519KeyManager
        self.sessionStore = sessionStore
        self.accountStore = accountStore
        self.messageService = messageService
        self.groupService = groupService
        self.crypto = crypto
        self.attachmentService = attachmentService
        self.fileCrypto = fileCrypto
    }

    deinit {
        liveTask?.cancel()
    }

    func refreshGroups() async {
        guard let token = sessionStore.load() else {
            groups = []
            statusMessage = "Sign in before loading groups."
            return
        }

        groups = await groupService.listGroups(token: token)
    }

    func createGroup(name: String, memberUsernames: [String]) async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            statusMessage = "Enter a group name."
            return
        }
        guard let token = sessionStore.load() else {
            statusMessage = "Sign in before creating a group."
            return
        }
        guard let account = accountStore.currentAccount() else {
            statusMessage = "No local account found."
            return
        }

        let usernames = normalizedUsernames(memberUsernames, including: account.username)
        let inviteeCount = usernames.filter { $0 != account.username }.count
        guard inviteeCount >= 2 else {
            statusMessage = "Add at least two other members."
            return
        }

        guard let prekeys = await fetchVerifiedPrekeys(usernames: usernames, token: token) else {
            return
        }

        do {
            _ = try identityProvider.loadOrCreate()
            let groupKey = crypto.newGroupKey()
            let memberKeys = try usernames.map { username in
                let prekey = prekeys[username]!
                return GroupMemberKeyDTO(
                    username: prekey.username,
                    wrappedKey: try crypto.wrapGroupKey(groupKey, toRecipientX25519: prekey.x25519PublicKey)
                )
            }

            guard let response = await groupService.createGroup(token: token, name: trimmedName, members: memberKeys) else {
                statusMessage = "Could not create group."
                return
            }

            groupId = response.groupId
            groupName = trimmedName
            currentEpoch = response.epoch
            epochKeys[response.epoch] = groupKey
            members = response.members.map { GroupMemberDTO(userId: $0.userId, username: $0.username, joinedEpoch: response.epoch) }
            messages = []
            await refreshGroups()
            statusMessage = ""
            subscribeLive(groupId: response.groupId, token: token)
        } catch {
            statusMessage = "Could not prepare group keys."
        }
    }

    func addMember(username: String) async {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusMessage = "Enter a username."
            return
        }
        guard let token = sessionStore.load() else {
            statusMessage = "Sign in before adding a member."
            return
        }
        guard let groupId else {
            statusMessage = "Open or create a group first."
            return
        }
        guard let detail = await groupService.fetchGroup(id: groupId, token: token) else {
            statusMessage = "Could not load group members."
            return
        }
        guard !detail.members.contains(where: { $0.username == trimmed }) else {
            statusMessage = "\(trimmed) is already in this group."
            return
        }

        let newEpoch = detail.currentEpoch + 1
        let usernames = normalizedUsernames(detail.members.map(\.username), including: trimmed)
        guard let prekeys = await fetchVerifiedPrekeys(usernames: usernames, token: token) else {
            return
        }

        do {
            let groupKey = crypto.newGroupKey()
            let keys = try usernames.map { username in
                let prekey = prekeys[username]!
                return WrappedKeyDTO(
                    memberId: prekey.userId,
                    wrappedKey: try crypto.wrapGroupKey(groupKey, toRecipientX25519: prekey.x25519PublicKey)
                )
            }

            guard let response = await groupService.addMember(
                groupId: groupId,
                token: token,
                username: trimmed,
                epoch: newEpoch,
                keys: keys
            ) else {
                statusMessage = "Could not add member."
                return
            }

            epochKeys[response.epoch] = groupKey
            currentEpoch = response.epoch
            members = detail.members + [
                GroupMemberDTO(userId: response.member.userId, username: response.member.username, joinedEpoch: response.epoch)
            ]
            groupName = detail.name
            statusMessage = ""
        } catch {
            statusMessage = "Could not prepare group keys."
        }
    }

    func openGroup(id: String) async {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusMessage = "Enter a group id."
            return
        }
        guard let token = sessionStore.load() else {
            statusMessage = "Sign in before opening a group."
            return
        }

        guard let detail = await groupService.fetchGroup(id: trimmed, token: token) else {
            clearOpenGroupState()
            statusMessage = "Group not found."
            return
        }

        do {
            try await reloadKeys(groupId: trimmed, token: token)
            groupId = detail.id
            groupName = detail.name
            members = detail.members
            currentEpoch = detail.currentEpoch
            await reloadHistory(groupId: trimmed, token: token)

            statusMessage = ""
            subscribeLive(groupId: detail.id, token: token)
        } catch {
            clearOpenGroupState()
            statusMessage = "Could not open group."
        }
    }

    func reconnectLive() async {
        guard let token = sessionStore.load(), let groupId else {
            return
        }

        do {
            try await reloadKeys(groupId: groupId, token: token)
            await refreshGroupDetail(groupId: groupId, token: token)
            await reloadHistory(groupId: groupId, token: token)
            subscribeLive(groupId: groupId, token: token)
        } catch {
            statusMessage = "Could not reconnect group."
        }
    }

    func send(text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        guard let token = sessionStore.load() else {
            statusMessage = "Sign in before sending a group message."
            return
        }
        guard let groupId else {
            statusMessage = "Open or create a group first."
            return
        }
        guard let prepared = await prepareLatestEpochKey(groupId: groupId, token: token) else {
            statusMessage = "Group key unavailable."
            return
        }

        do {
            let ciphertext = try crypto.encryptGroupMessage(Data(trimmed.utf8), epoch: prepared.epoch, groupKey: prepared.key)
            switch await groupService.sendGroupMessage(groupId: groupId, token: token, epoch: prepared.epoch, ciphertext: ciphertext) {
            case let .success(messageId, createdAt, _):
                messages.append(DisplayGroupMessage(
                    id: messageId,
                    senderId: accountStore.currentAccount()?.userId ?? "",
                    senderName: "You",
                    isMine: true,
                    text: trimmed,
                    createdAt: createdAt
                ))
                statusMessage = ""
            case .notMember:
                statusMessage = "You are not a member of this group."
            case .notFound:
                statusMessage = "Group not found."
            case let .failure(message):
                statusMessage = message.isEmpty ? "Could not send group message." : message
            }
        } catch {
            statusMessage = "Could not encrypt group message."
        }
    }

    func sendAttachment(data: Data, filename: String, mime: String) async {
        guard data.count <= Self.maxAttachmentBytes else {
            statusMessage = "Attachment must be 10 MB or smaller."
            return
        }
        guard let token = sessionStore.load() else {
            statusMessage = "Sign in before sending a group attachment."
            return
        }
        guard let groupId else {
            statusMessage = "Open or create a group first."
            return
        }
        guard let prepared = await prepareLatestEpochKey(groupId: groupId, token: token) else {
            statusMessage = "Group key unavailable."
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
            let ciphertext = try crypto.encryptGroupMessage(descriptor.encodedJSON(), epoch: prepared.epoch, groupKey: prepared.key)
            switch await groupService.sendGroupMessage(groupId: groupId, token: token, epoch: prepared.epoch, ciphertext: ciphertext) {
            case let .success(messageId, createdAt, _):
                messages.append(DisplayGroupMessage(
                    id: messageId,
                    senderId: accountStore.currentAccount()?.userId ?? "",
                    senderName: "You",
                    isMine: true,
                    text: filename,
                    attachment: AttachmentInfo(descriptor: descriptor),
                    createdAt: createdAt
                ))
                statusMessage = ""
            case .notMember:
                statusMessage = "You are not a member of this group."
            case .notFound:
                statusMessage = "Group not found."
            case let .failure(message):
                statusMessage = message.isEmpty ? "Could not send group attachment." : message
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

    func cancelLiveSubscription() {
        liveTask?.cancel()
        liveTask = nil
    }

    func clearOpenGroupState() {
        cancelLiveSubscription()
        groupId = nil
        groupName = ""
        members = []
        messages = []
        currentEpoch = 0
        epochKeys = [:]
    }

    private func subscribeLive(groupId: String, token: String) {
        cancelLiveSubscription()
        liveTask = Task { [weak self] in
            guard let self else {
                return
            }
            do {
                let stream = self.groupService.liveGroupMessages(
                    groupId: groupId,
                    token: token,
                    onEpochChange: { [weak self] event in
                        Task { @MainActor [weak self] in
                            await self?.handleEpochChange(event, groupId: groupId, token: token)
                        }
                    }
                )
                for try await record in stream {
                    if Task.isCancelled {
                        break
                    }
                    await self.appendLive(record, groupId: groupId, token: token)
                }
                if !Task.isCancelled {
                    self.statusMessage = "Live group connection closed."
                }
            } catch {
                if !Task.isCancelled {
                    self.statusMessage = "Live group connection closed."
                }
            }
        }
    }

    private func handleEpochChange(_ event: GroupEpochEvent, groupId: String, token: String) async {
        guard event.groupId == groupId, self.groupId == groupId else {
            return
        }

        await refreshGroupDetail(groupId: groupId, token: token)
        try? await reloadKeys(groupId: groupId, token: token)
        await refreshGroups()
    }

    private func reloadKeys(groupId: String, token: String) async throws {
        let localPrivate = try x25519KeyManager.loadOrCreate()
        var unwrapped: [UInt32: Data] = [:]
        for record in await groupService.fetchKeys(groupId: groupId, token: token) {
            if let key = try? crypto.unwrapGroupKey(record.wrappedKey, withLocalX25519: localPrivate) {
                unwrapped[record.epoch] = key
            }
        }
        epochKeys.merge(unwrapped) { _, new in new }
    }

    private func reloadHistory(groupId: String, token: String) async {
        var seen = Set<String>()
        var resolved: [DisplayGroupMessage] = []
        for record in await groupService.groupHistory(groupId: groupId, token: token, since: nil) {
            guard !seen.contains(record.id) else {
                continue
            }
            guard let display = await resolve(record: record, groupId: groupId, token: token) else {
                continue
            }
            seen.insert(record.id)
            resolved.append(display)
        }
        messages = resolved
    }

    private func appendLive(_ record: GroupMessageRecord, groupId: String, token: String) async {
        guard !messages.contains(where: { $0.id == record.id }) else {
            return
        }
        guard let display = await resolve(record: record, groupId: groupId, token: token) else {
            return
        }

        messages.append(display)
    }

    private func resolve(record: GroupMessageRecord, groupId: String, token: String) async -> DisplayGroupMessage? {
        guard let epoch = try? crypto.messageEpoch(of: record.ciphertext) else {
            return nil
        }

        if epochKeys[epoch] == nil {
            await refreshGroupDetail(groupId: groupId, token: token)
            try? await reloadKeys(groupId: groupId, token: token)
        }

        guard
            let groupKey = epochKeys[epoch],
            let plaintext = try? crypto.decryptGroupMessage(record.ciphertext, groupKey: groupKey)
        else {
            return nil
        }

        return Self.displayMessage(
            id: record.id,
            senderId: record.senderId,
            senderName: senderName(for: record.senderId),
            isMine: record.senderId == accountStore.currentAccount()?.userId,
            plaintext: plaintext,
            createdAt: record.createdAt
        )
    }

    private func prepareLatestEpochKey(groupId: String, token: String) async -> (epoch: UInt32, key: Data)? {
        await refreshGroupDetail(groupId: groupId, token: token)
        try? await reloadKeys(groupId: groupId, token: token)
        guard let key = epochKeys[currentEpoch] else {
            return nil
        }
        return (currentEpoch, key)
    }

    private func refreshGroupDetail(groupId: String, token: String) async {
        guard let detail = await groupService.fetchGroup(id: groupId, token: token) else {
            return
        }
        self.groupId = detail.id
        groupName = detail.name
        members = detail.members
        currentEpoch = detail.currentEpoch
    }

    private func fetchVerifiedPrekeys(usernames: [String], token: String) async -> [String: PrekeyResponse]? {
        var prekeys: [String: PrekeyResponse] = [:]
        for username in usernames {
            guard let prekey = await messageService.fetchPrekey(username: username, token: token) else {
                statusMessage = "User \(username) not found."
                return nil
            }
            guard Self.verify(prekey: prekey) else {
                statusMessage = "Could not verify \(prekey.username)'s keys."
                return nil
            }
            prekeys[username] = prekey
        }
        return prekeys
    }

    private func normalizedUsernames(_ usernames: [String], including first: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for username in [first] + usernames {
            let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else {
                continue
            }
            seen.insert(trimmed)
            result.append(trimmed)
        }
        return result
    }

    private static func verify(prekey: PrekeyResponse) -> Bool {
        MessageCrypto.verifyPrekey(
            x25519PublicKeyBase64: prekey.x25519PublicKey,
            signatureBase64: prekey.keySignature,
            identityPublicKeyBase64: prekey.identityPublicKey
        )
    }

    private static func displayMessage(
        id: String,
        senderId: String,
        senderName: String,
        isMine: Bool,
        plaintext: Data,
        createdAt: String
    ) -> DisplayGroupMessage? {
        if let descriptor = AttachmentDescriptor.decode(plaintext) {
            return DisplayGroupMessage(
                id: id,
                senderId: senderId,
                senderName: senderName,
                isMine: isMine,
                text: descriptor.filename,
                attachment: AttachmentInfo(descriptor: descriptor),
                createdAt: createdAt
            )
        }

        guard let text = String(data: plaintext, encoding: .utf8) else {
            return nil
        }
        return DisplayGroupMessage(id: id, senderId: senderId, senderName: senderName, isMine: isMine, text: text, createdAt: createdAt)
    }

    private func senderName(for senderId: String) -> String {
        if senderId == accountStore.currentAccount()?.userId {
            return "You"
        }
        return members.first { $0.userId == senderId }?.username ?? senderId
    }

    private static func base64(_ key: SymmetricKey) -> String {
        key.withUnsafeBytes { Data($0).base64EncodedString() }
    }
}
