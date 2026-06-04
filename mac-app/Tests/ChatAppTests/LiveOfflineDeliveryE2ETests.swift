import CryptoKit
import Foundation
import XCTest
@testable import ChatApp

final class LiveOfflineDeliveryE2ETests: XCTestCase {
    private var cleanupURLs: [URL] = []
    private var keychainStores: [KeychainStore] = []

    override func tearDownWithError() throws {
        for store in keychainStores {
            try store.delete()
        }
        for url in cleanupURLs {
            try? FileManager.default.removeItem(at: url)
        }
        try super.tearDownWithError()
    }

    @MainActor
    func testOfflineRecipientReceivesQueuedMessagesInOrderAndRestartReloadsHistory() async throws {
        let backendURLString = ProcessInfo.processInfo.environment["CHATAPP_LIVE_BACKEND_URL"]
        try XCTSkipUnless(backendURLString != nil, "CHATAPP_LIVE_BACKEND_URL is not set")
        let backendURL = try XCTUnwrap(URL(string: try XCTUnwrap(backendURLString)))

        let registrationClient = HTTPRegistrationClient(baseURL: backendURL)
        let authClient = HTTPAuthClient(baseURL: backendURL)
        let messageService = HTTPMessageService(baseURL: backendURL)
        let groupService = HTTPGroupService(baseURL: backendURL)
        let messageCrypto = MessageCrypto()
        let groupCrypto = GroupCrypto()

        let alice = try await makeLiveUser(
            prefix: "off_a",
            registrationClient: registrationClient,
            authClient: authClient,
            messageService: messageService,
            crypto: messageCrypto
        )
        let bob = try await makeLiveUser(
            prefix: "off_b",
            registrationClient: registrationClient,
            authClient: authClient,
            messageService: messageService,
            crypto: messageCrypto
        )

        let dmPlaintexts = (1...6).map { "offline dm \($0) \(UUID().uuidString)" }
        let dmMessageIds = try await sendOfflineDMs(
            plaintexts: dmPlaintexts,
            from: alice,
            to: bob,
            service: messageService,
            crypto: messageCrypto
        )

        let reconnectingBobDM = makeDMCoordinator(for: bob, service: messageService, crypto: messageCrypto)
        await reconnectingBobDM.startConversation(withUsername: alice.username)
        try await waitForMessages({ reconnectingBobDM.messages }, count: dmPlaintexts.count)
        XCTAssertEqual(reconnectingBobDM.messages.map(\.id), dmMessageIds)
        XCTAssertEqual(reconnectingBobDM.messages.map(\.text), dmPlaintexts)
        XCTAssertTrue(reconnectingBobDM.messages.allSatisfy { !$0.isMine })

        let groupName = "Offline Group \(UUID().uuidString)"
        let groupKey = groupCrypto.newGroupKey()
        let createResponse = try await createGroup(
            name: groupName,
            groupKey: groupKey,
            creator: alice,
            members: [alice, bob],
            messageService: messageService,
            groupService: groupService,
            groupCrypto: groupCrypto
        )
        let groupPlaintexts = (1...4).map { "offline group \($0) \(UUID().uuidString)" }
        let groupMessageIds = try await sendOfflineGroupMessages(
            groupId: createResponse.groupId,
            groupKey: groupKey,
            plaintexts: groupPlaintexts,
            sender: alice,
            groupService: groupService,
            groupCrypto: groupCrypto
        )

        let restartedConversationList = makeConversationListStore(for: bob, messageService: messageService)
        await restartedConversationList.refresh()
        XCTAssertTrue(
            restartedConversationList.conversations.contains { $0.peerUsername == alice.username },
            "Restarted DM list did not include inbound-only peer \(alice.username): \(restartedConversationList.conversations)"
        )

        let restartedBobDM = makeDMCoordinator(for: bob, service: messageService, crypto: messageCrypto)
        await restartedBobDM.startConversation(withUsername: alice.username)
        try await waitForMessages({ restartedBobDM.messages }, count: dmPlaintexts.count)
        XCTAssertEqual(restartedBobDM.messages.map(\.id), dmMessageIds)
        XCTAssertEqual(restartedBobDM.messages.map(\.text), dmPlaintexts)

        let restartedBobGroups = makeGroupCoordinator(
            for: bob,
            messageService: messageService,
            groupService: groupService,
            crypto: groupCrypto
        )
        await restartedBobGroups.refreshGroups()
        XCTAssertTrue(
            restartedBobGroups.groups.contains { $0.id == createResponse.groupId && $0.name == groupName },
            "Restarted group list did not include \(createResponse.groupId): \(restartedBobGroups.groups)"
        )

        await restartedBobGroups.openGroup(id: createResponse.groupId)
        try await waitForGroupMessages({ restartedBobGroups.messages }, count: groupPlaintexts.count)
        XCTAssertEqual(restartedBobGroups.messages.map(\.id), groupMessageIds)
        XCTAssertEqual(restartedBobGroups.messages.map(\.text), groupPlaintexts)
        XCTAssertTrue(restartedBobGroups.messages.allSatisfy { $0.senderId == alice.userId })

        try writeProofArtifacts(messageIds: dmMessageIds, plaintexts: dmPlaintexts)
    }

    @MainActor
    private func makeLiveUser(
        prefix: String,
        registrationClient: HTTPRegistrationClient,
        authClient: HTTPAuthClient,
        messageService: HTTPMessageService,
        crypto: MessageCrypto
    ) async throws -> OfflineLiveUser {
        let usernameSuffix = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(20))
        let username = "\(prefix)_\(usernameSuffix)"
        let identity = CryptoIdentity(privateKey: Curve25519.Signing.PrivateKey())
        let sessionKeychain = keychainStore(kind: "session", username: username)
        let x25519Keychain = keychainStore(kind: "x25519", username: username)
        keychainStores.append(sessionKeychain)
        keychainStores.append(x25519Keychain)

        let accountDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("live-offline-\(username)-\(UUID().uuidString)", isDirectory: true)
        cleanupURLs.append(accountDirectory)
        let accountStore = LocalAccountStore(directory: accountDirectory)
        let sessionStore = SessionStore(keychainStore: sessionKeychain)
        let x25519KeyManager = X25519KeyManager(keychainStore: x25519Keychain)
        let x25519PrivateKey = try x25519KeyManager.loadOrCreate()
        let x25519PublicKey = x25519PrivateKey.publicKey.rawRepresentation.base64EncodedString()

        let registration = await registrationClient.register(username: username, publicKeyBase64: identity.publicKeyBase64)
        let userId: String
        switch registration {
        case let .success(registeredUserId):
            userId = registeredUserId
        default:
            throw LiveOfflineError.registrationFailed(username, "\(registration)")
        }

        let token = try await signIn(username: username, identity: identity, authClient: authClient)
        try sessionStore.save(token)
        try accountStore.save(LocalAccount(username: username, publicKeyBase64: identity.publicKeyBase64, userId: userId))

        let signature = crypto.signPrekey(x25519PublicKeyBase64: x25519PublicKey, with: identity)
        let published = await messageService.publishPrekey(
            token: token,
            x25519PublicKey: x25519PublicKey,
            signature: signature
        )
        XCTAssertTrue(published, "Expected signed prekey publish to succeed for \(username)")

        return OfflineLiveUser(
            username: username,
            userId: userId,
            token: token,
            identity: identity,
            sessionStore: sessionStore,
            accountStore: accountStore,
            x25519KeyManager: x25519KeyManager,
            x25519PrivateKey: x25519PrivateKey,
            x25519PublicKey: x25519PublicKey
        )
    }

    @MainActor
    private func signIn(username: String, identity: CryptoIdentity, authClient: HTTPAuthClient) async throws -> String {
        let challenge = await authClient.requestChallenge(username: username)
        let challengeId: String
        let nonceBase64: String
        switch challenge {
        case let .challenge(returnedChallengeId, returnedNonceBase64):
            challengeId = returnedChallengeId
            nonceBase64 = returnedNonceBase64
        default:
            throw LiveOfflineError.challengeFailed(username, "\(challenge)")
        }

        let nonce = try XCTUnwrap(Data(base64Encoded: nonceBase64))
        let verification = await authClient.verify(
            challengeId: challengeId,
            signatureBase64: identity.sign(nonce).base64EncodedString()
        )
        switch verification {
        case let .success(token, _, returnedUsername):
            XCTAssertEqual(returnedUsername, username)
            return token
        default:
            throw LiveOfflineError.verifyFailed(username, "\(verification)")
        }
    }

    @MainActor
    private func sendOfflineDMs(
        plaintexts: [String],
        from sender: OfflineLiveUser,
        to recipient: OfflineLiveUser,
        service: HTTPMessageService,
        crypto: MessageCrypto
    ) async throws -> [String] {
        let fetchedPrekey = await service.fetchPrekey(username: recipient.username, token: sender.token)
        let prekey = try XCTUnwrap(fetchedPrekey)
        var ids: [String] = []
        for plaintext in plaintexts {
            let ciphertext = try crypto.encrypt(Data(plaintext.utf8), toRecipientX25519: prekey.x25519PublicKey)
            switch await service.send(token: sender.token, recipientUsername: recipient.username, ciphertext: ciphertext) {
            case let .success(messageId, _):
                ids.append(messageId)
            default:
                XCTFail("Expected offline DM send to succeed")
            }
        }
        return ids
    }

    @MainActor
    private func createGroup(
        name: String,
        groupKey: Data,
        creator: OfflineLiveUser,
        members: [OfflineLiveUser],
        messageService: HTTPMessageService,
        groupService: HTTPGroupService,
        groupCrypto: GroupCrypto
    ) async throws -> CreateGroupResponse {
        var wrappedMembers: [GroupMemberKeyDTO] = []
        wrappedMembers.reserveCapacity(members.count)
        for member in members {
            let fetchedPrekey = await messageService.fetchPrekey(username: member.username, token: creator.token)
            let prekey = try XCTUnwrap(fetchedPrekey)
            wrappedMembers.append(GroupMemberKeyDTO(
                username: member.username,
                wrappedKey: try groupCrypto.wrapGroupKey(groupKey, toRecipientX25519: prekey.x25519PublicKey)
            ))
        }

        let response = await groupService.createGroup(token: creator.token, name: name, members: wrappedMembers)
        return try XCTUnwrap(response)
    }

    @MainActor
    private func sendOfflineGroupMessages(
        groupId: String,
        groupKey: Data,
        plaintexts: [String],
        sender: OfflineLiveUser,
        groupService: HTTPGroupService,
        groupCrypto: GroupCrypto
    ) async throws -> [String] {
        var ids: [String] = []
        for plaintext in plaintexts {
            let ciphertext = try groupCrypto.encryptGroupMessage(Data(plaintext.utf8), epoch: 0, groupKey: groupKey)
            switch await groupService.sendGroupMessage(groupId: groupId, token: sender.token, epoch: 0, ciphertext: ciphertext) {
            case let .success(messageId, _, returnedEpoch):
                XCTAssertEqual(returnedEpoch, 0)
                ids.append(messageId)
            default:
                XCTFail("Expected offline group message send to succeed")
            }
        }
        return ids
    }

    @MainActor
    private func makeDMCoordinator(
        for user: OfflineLiveUser,
        service: HTTPMessageService,
        crypto: MessageCrypto
    ) -> DMCoordinator {
        DMCoordinator(
            identityProvider: OfflineIdentityProvider(identity: user.identity),
            x25519KeyManager: user.x25519KeyManager,
            sessionStore: user.sessionStore,
            accountStore: user.accountStore,
            service: service,
            crypto: crypto
        )
    }

    @MainActor
    private func makeConversationListStore(
        for user: OfflineLiveUser,
        messageService: HTTPMessageService
    ) -> ConversationListStore {
        ConversationListStore(
            service: messageService,
            sessionStore: user.sessionStore,
            accountStore: user.accountStore,
            makeLiveStream: { token in messageService.liveMessages(token: token) }
        )
    }

    @MainActor
    private func makeGroupCoordinator(
        for user: OfflineLiveUser,
        messageService: HTTPMessageService,
        groupService: HTTPGroupService,
        crypto: GroupCrypto
    ) -> GroupCoordinator {
        GroupCoordinator(
            identityProvider: OfflineIdentityProvider(identity: user.identity),
            x25519KeyManager: user.x25519KeyManager,
            sessionStore: user.sessionStore,
            accountStore: user.accountStore,
            messageService: messageService,
            groupService: groupService,
            crypto: crypto
        )
    }

    @MainActor
    private func waitForMessages(_ messages: () -> [DisplayMessage], count: Int) async throws {
        for _ in 0..<50 {
            if messages().count == count {
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTFail("Expected \(count) rendered DM messages, got \(messages())")
    }

    @MainActor
    private func waitForGroupMessages(_ messages: () -> [DisplayGroupMessage], count: Int) async throws {
        for _ in 0..<50 {
            if messages().count == count {
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTFail("Expected \(count) rendered group messages, got \(messages())")
    }

    private func keychainStore(kind: String, username: String) -> KeychainStore {
        KeychainStore(
            service: "\(KeychainStore.defaultService).live-offline.\(kind).\(username)",
            account: "\(KeychainStore.defaultAccount).live-offline.\(kind)",
            usesDataProtectionKeychain: false
        )
    }

    private func writeProofArtifacts(messageIds: [String], plaintexts: [String]) throws {
        let environment = ProcessInfo.processInfo.environment
        try writeIfRequested(messageIds.joined(separator: "\n"), path: environment["CHATAPP_OFFLINE_MESSAGE_IDS_OUT"])
        try writeIfRequested(plaintexts.joined(separator: "\n"), path: environment["CHATAPP_OFFLINE_PLAINTEXTS_OUT"])
    }

    private func writeIfRequested(_ value: String, path: String?) throws {
        guard let path else {
            return
        }
        try value.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
    }
}

private struct OfflineLiveUser {
    let username: String
    let userId: String
    let token: String
    let identity: CryptoIdentity
    let sessionStore: SessionStore
    let accountStore: LocalAccountStore
    let x25519KeyManager: X25519KeyManager
    let x25519PrivateKey: Curve25519.KeyAgreement.PrivateKey
    let x25519PublicKey: String
}

private struct OfflineIdentityProvider: IdentityProviding {
    let identity: CryptoIdentity

    func loadOrCreate() throws -> CryptoIdentity {
        identity
    }
}

private enum LiveOfflineError: Error, CustomStringConvertible {
    case registrationFailed(String, String)
    case challengeFailed(String, String)
    case verifyFailed(String, String)

    var description: String {
        switch self {
        case let .registrationFailed(username, result):
            return "Registration failed for \(username): \(result)"
        case let .challengeFailed(username, result):
            return "Challenge failed for \(username): \(result)"
        case let .verifyFailed(username, result):
            return "Verify failed for \(username): \(result)"
        }
    }
}
