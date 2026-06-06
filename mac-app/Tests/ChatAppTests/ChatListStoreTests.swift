import CryptoKit
import Foundation
import XCTest
@testable import ChatApp

final class ChatListStoreTests: XCTestCase {
    private var cleanupURLs: [URL] = []
    private var keychainStores: [KeychainStore] = []

    override func tearDownWithError() throws {
        for store in keychainStores {
            try? store.delete()
        }
        for url in cleanupURLs {
            try? FileManager.default.removeItem(at: url)
        }
        try super.tearDownWithError()
    }

    @MainActor
    func testSidebarStateIsLoadingBeforeInitialRowsLoad() {
        XCTAssertEqual(
            ChatListSidebarState.resolve(rows: [], isLoading: false, hasLoaded: false),
            .loading
        )
        XCTAssertEqual(
            ChatListSidebarState.resolve(rows: [], isLoading: true, hasLoaded: false),
            .loading
        )
    }

    @MainActor
    func testSidebarStateIsEmptyAfterLoadingCompletesWithNoRows() {
        XCTAssertEqual(
            ChatListSidebarState.resolve(rows: [], isLoading: false, hasLoaded: true),
            .empty
        )
    }

    @MainActor
    func testSidebarStateIsPopulatedWheneverRowsExist() {
        let row = ChatListItem(
            id: "direct:peer-a",
            kind: .direct,
            title: "alice",
            activityAt: "2026-06-03T10:00:00Z",
            peerUsername: "alice",
            groupId: nil,
            detail: "Direct message"
        )

        XCTAssertEqual(
            ChatListSidebarState.resolve(rows: [row], isLoading: true, hasLoaded: false),
            .populated
        )
        XCTAssertEqual(
            ChatListSidebarState.resolve(rows: [row], isLoading: false, hasLoaded: true),
            .populated
        )
    }

    @MainActor
    func testRefreshCombinesDirectAndGroupRowsSortedByTimestampThenName() async throws {
        let harness = try makeHarness()
        harness.conversations.records = [
            conversation(peerId: "peer-old", username: "zoe", messageId: "msg-old", createdAt: "2026-06-03T09:00:00Z"),
            conversation(peerId: "peer-tie", username: "amy", messageId: "msg-tie", createdAt: "2026-06-03T11:00:00Z")
        ]
        harness.groups.listedGroups = [
            group(id: "group-new", name: "Ops", createdAt: "2026-06-03T12:00:00Z"),
            group(id: "group-tie", name: "Design", createdAt: "2026-06-03T11:00:00Z")
        ]

        await harness.chatList.refresh()

        XCTAssertEqual(harness.conversations.fetchCount, 1)
        XCTAssertEqual(harness.groups.listTokens, ["token-1"])
        XCTAssertEqual(harness.chatList.rows.map(\.id), [
            "group:group-new",
            "direct:peer-tie",
            "group:group-tie",
            "direct:peer-old"
        ])
        XCTAssertEqual(harness.chatList.rows.map(\.title), ["Ops", "amy", "Design", "zoe"])
        XCTAssertEqual(harness.chatList.rows.map(\.kind), [.group, .direct, .group, .direct])
    }

    @MainActor
    func testSelectingDirectRowSelectsExistingDirectConversationFlow() async throws {
        let harness = try makeHarness()
        harness.conversations.records = [
            conversation(peerId: "peer-bob", username: "bob", messageId: "msg-1", createdAt: "2026-06-03T10:00:00Z")
        ]
        await harness.chatList.refresh()

        let row = try XCTUnwrap(harness.chatList.rows.first)
        await harness.chatList.select(row)

        XCTAssertEqual(harness.chatList.selectedRow?.id, "direct:peer-bob")
        XCTAssertEqual(
            harness.chatList.selectedDirectConversation,
            DirectConversationSelection(rowId: "direct:peer-bob", requestedUsername: "bob", knownPeerUserId: "peer-bob")
        )
        XCTAssertEqual(harness.conversationListStore.selectedPeerUsername, "bob")
        XCTAssertNil(harness.groupCoordinator.groupId)
    }

    @MainActor
    func testIsSelectedTracksDirectSelectionByResolvedConversation() async throws {
        let harness = try makeHarness()
        harness.conversations.records = [
            conversation(peerId: "peer-bob", username: "bob", messageId: "msg-1", createdAt: "2026-06-03T10:00:00Z"),
            conversation(peerId: "peer-cora", username: "cora", messageId: "msg-2", createdAt: "2026-06-03T11:00:00Z")
        ]
        await harness.chatList.refresh()

        let bob = try XCTUnwrap(harness.chatList.rows.first { $0.peerUsername == "bob" })
        let cora = try XCTUnwrap(harness.chatList.rows.first { $0.peerUsername == "cora" })
        await harness.chatList.select(bob)

        XCTAssertTrue(harness.chatList.isSelected(bob))
        XCTAssertFalse(harness.chatList.isSelected(cora))
    }

    @MainActor
    func testRefreshRemapsTemporaryDirectSelectionToBackendConversationRow() async throws {
        let harness = try makeHarness()

        await harness.chatList.selectDirect(username: "bob")
        XCTAssertEqual(harness.chatList.selectedRow?.id, "direct:new:bob")

        harness.conversations.records = [
            conversation(peerId: "peer-bob", username: "bob", messageId: "msg-1", createdAt: "2026-06-03T10:00:00Z")
        ]
        await harness.chatList.refresh()

        XCTAssertEqual(harness.chatList.selectedRow?.id, "direct:peer-bob")
        XCTAssertEqual(harness.chatList.selectedDirectConversation?.id, "direct:peer-bob")
        XCTAssertEqual(harness.conversationListStore.selectedPeerUsername, "bob")
    }

    @MainActor
    func testRouteResolverReturnsIdleDirectAndGroupRoutes() async throws {
        let harness = try makeHarness()
        XCTAssertEqual(harness.chatList.route, .none)

        await harness.chatList.selectDirect(username: "bob")
        XCTAssertEqual(
            harness.chatList.route,
            .direct(DirectConversationSelection(rowId: "direct:new:bob", requestedUsername: "bob", knownPeerUserId: nil))
        )

        let wrappedKey = try wrappedLocalGroupKey(in: harness)
        harness.groups.keysByGroup["group-1"] = [GroupKeyRecord(epoch: 0, wrappedKey: wrappedKey)]
        harness.groups.listedGroups = [
            group(id: "group-1", name: "Ops", createdAt: "2026-06-03T10:00:00Z")
        ]
        await harness.chatList.refresh()
        await harness.chatList.select(try XCTUnwrap(harness.chatList.rows.first { $0.groupId == "group-1" }))

        XCTAssertEqual(harness.chatList.route, .group)
        XCTAssertNil(harness.chatList.selectedDirectConversation)
    }

    @MainActor
    func testSelectingGroupRowOpensGroupWithoutManualGroupIdEntry() async throws {
        let harness = try makeHarness()
        let wrappedKey = try wrappedLocalGroupKey(in: harness)
        harness.groups.keysByGroup["group-1"] = [GroupKeyRecord(epoch: 0, wrappedKey: wrappedKey)]
        harness.groups.listedGroups = [
            group(id: "group-1", name: "Ops", createdAt: "2026-06-03T10:00:00Z")
        ]

        await harness.chatList.refresh()
        let row = try XCTUnwrap(harness.chatList.rows.first)
        await harness.chatList.select(row)

        XCTAssertEqual(harness.chatList.selectedRow?.id, "group:group-1")
        XCTAssertNil(harness.conversationListStore.selectedPeerUsername)
        XCTAssertEqual(harness.groupCoordinator.groupId, "group-1")
        XCTAssertEqual(harness.groupCoordinator.groupName, "Ops")
        XCTAssertEqual(harness.groups.fetchGroupCalls, ["group-1"])
    }

    @MainActor
    func testCreateGroupRefreshesRowsAndSelectsNewGroup() async throws {
        let harness = try makeHarness()
        try harness.addVerifiedPrekey(username: "bob", userId: "user-b", key: Curve25519.KeyAgreement.PrivateKey())
        try harness.addVerifiedPrekey(username: "carol", userId: "user-c", key: Curve25519.KeyAgreement.PrivateKey())
        harness.groups.listedGroups = []

        let created = await harness.chatList.createGroup(name: " Ops ", memberUsernames: ["bob", "carol"])

        XCTAssertTrue(created)
        XCTAssertEqual(harness.groups.createRequests.map(\.name), ["Ops"])
        XCTAssertEqual(harness.groups.listTokens.count, 2)
        XCTAssertEqual(harness.chatList.selectedRow?.id, "group:group-1")
        XCTAssertEqual(harness.chatList.rows.map(\.id), ["group:group-1"])
        XCTAssertEqual(harness.groupCoordinator.groupId, "group-1")
        XCTAssertEqual(harness.groupCoordinator.groupName, "Ops")
    }

    @MainActor
    func testCreateGroupFailureDoesNotReportSuccessWhenPreviousGroupIsOpen() async throws {
        let harness = try makeHarness()
        let wrappedKey = try wrappedLocalGroupKey(in: harness)
        harness.groups.keysByGroup["group-1"] = [GroupKeyRecord(epoch: 0, wrappedKey: wrappedKey)]
        harness.groups.listedGroups = [
            group(id: "group-1", name: "Already open", createdAt: "2026-06-03T10:00:00Z")
        ]
        await harness.chatList.refresh()
        await harness.chatList.select(try XCTUnwrap(harness.chatList.rows.first))

        let created = await harness.chatList.createGroup(name: "Nope", memberUsernames: ["bob"])

        XCTAssertFalse(created)
        XCTAssertTrue(harness.groups.createRequests.isEmpty)
        XCTAssertEqual(harness.chatList.selectedRow?.id, "group:group-1")
        XCTAssertEqual(harness.groupCoordinator.groupId, "group-1")
        XCTAssertEqual(harness.groupCoordinator.statusMessage, "Add at least two other members.")
    }

    @MainActor
    private func makeHarness() throws -> Harness {
        let sessionKeychain = KeychainStore(
            service: "\(KeychainStore.defaultService).chat-list.tests.\(UUID().uuidString)",
            account: "\(KeychainStore.defaultAccount).session.tests",
            usesDataProtectionKeychain: false
        )
        let x25519Keychain = KeychainStore(
            service: "\(KeychainStore.defaultService).chat-list.tests.\(UUID().uuidString)",
            account: "\(KeychainStore.defaultAccount).x25519.tests",
            usesDataProtectionKeychain: false
        )
        keychainStores.append(sessionKeychain)
        keychainStores.append(x25519Keychain)

        let sessionStore = SessionStore(keychainStore: sessionKeychain)
        try sessionStore.save("token-1")

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat-list-store-\(UUID().uuidString)", isDirectory: true)
        cleanupURLs.append(directory)
        let accountStore = LocalAccountStore(directory: directory)
        let identity = CryptoIdentity(privateKey: Curve25519.Signing.PrivateKey())
        try accountStore.save(LocalAccount(username: "alice", publicKeyBase64: identity.publicKeyBase64, userId: "user-a"))

        let conversations = FakeChatListConversationsService()
        let conversationListStore = ConversationListStore(
            service: conversations,
            sessionStore: sessionStore,
            accountStore: accountStore,
            makeLiveStream: { _ in AsyncThrowingStream { $0.finish() } }
        )

        let x25519 = X25519KeyManager(keychainStore: x25519Keychain)
        _ = try x25519.loadOrCreate()
        let messageService = FakeChatListMessageService()
        let localX25519Public = try x25519.publicKeyBase64()
        let localSignature = MessageCrypto().signPrekey(x25519PublicKeyBase64: localX25519Public, with: identity)
        messageService.prekeys["alice"] = PrekeyResponse(
            userId: "user-a",
            username: "alice",
            identityPublicKey: identity.publicKeyBase64,
            x25519PublicKey: localX25519Public,
            keySignature: localSignature
        )

        let groups = FakeChatListGroupService()
        let groupCoordinator = GroupCoordinator(
            identityProvider: StubChatListIdentityProvider(identity: identity),
            x25519KeyManager: x25519,
            sessionStore: sessionStore,
            accountStore: accountStore,
            messageService: messageService,
            groupService: groups,
            crypto: GroupCrypto(),
            attachmentService: FakeChatListAttachmentService(),
            fileCrypto: FileCrypto()
        )
        let chatList = ChatListStore(
            conversationListStore: conversationListStore,
            groupCoordinator: groupCoordinator
        )

        return Harness(
            chatList: chatList,
            conversationListStore: conversationListStore,
            groupCoordinator: groupCoordinator,
            conversations: conversations,
            groups: groups,
            messageService: messageService,
            x25519: x25519
        )
    }

    private func conversation(peerId: String, username: String, messageId: String, createdAt: String) -> ConversationSummary {
        ConversationSummary(peerId: peerId, peerUsername: username, lastActivityAt: createdAt, lastMessageId: messageId)
    }

    private func group(id: String, name: String, createdAt: String) -> GroupSummary {
        GroupSummary(id: id, name: name, creatorId: "user-a", currentEpoch: 0, joinedEpoch: 0, createdAt: createdAt)
    }

    @MainActor
    private func wrappedLocalGroupKey(in harness: Harness) throws -> String {
        try GroupCrypto().wrapGroupKey(
            GroupCrypto().newGroupKey(),
            toRecipientX25519: harness.x25519.publicKeyBase64()
        )
    }
}

private struct Harness {
    let chatList: ChatListStore
    let conversationListStore: ConversationListStore
    let groupCoordinator: GroupCoordinator
    let conversations: FakeChatListConversationsService
    let groups: FakeChatListGroupService
    let messageService: FakeChatListMessageService
    let x25519: X25519KeyManager

    func addVerifiedPrekey(username: String, userId: String, key: Curve25519.KeyAgreement.PrivateKey) throws {
        let identity = CryptoIdentity(privateKey: Curve25519.Signing.PrivateKey())
        let x25519Public = key.publicKey.rawRepresentation.base64EncodedString()
        let signature = MessageCrypto().signPrekey(x25519PublicKeyBase64: x25519Public, with: identity)
        messageService.prekeys[username] = PrekeyResponse(
            userId: userId,
            username: username,
            identityPublicKey: identity.publicKeyBase64,
            x25519PublicKey: x25519Public,
            keySignature: signature
        )
    }
}

private struct StubChatListIdentityProvider: IdentityProviding {
    let identity: CryptoIdentity

    func loadOrCreate() throws -> CryptoIdentity {
        identity
    }
}

private final class FakeChatListConversationsService: ConversationsService, @unchecked Sendable {
    var records: [ConversationSummary] = []
    private(set) var fetchCount = 0

    func conversations(token: String) async -> [ConversationSummary] {
        fetchCount += 1
        return records
    }
}

private final class FakeChatListMessageService: MessageService, @unchecked Sendable {
    var prekeys: [String: PrekeyResponse] = [:]

    func publishPrekey(token: String, x25519PublicKey: String, signature: String) async -> Bool {
        true
    }

    func fetchPrekey(username: String, token: String) async -> PrekeyResponse? {
        prekeys[username]
    }

    func send(token: String, recipientUsername: String, ciphertext: String) async -> SendMessageResult {
        .failure("unused")
    }

    func history(token: String, withUsername username: String, since: String?) async -> [MessageRecord] {
        []
    }

    func inbox(token: String, since: Int) async -> InboxPage {
        InboxPage(messages: [], nextCursor: nil)
    }

    func conversations(token: String) async -> [ConversationSummary] {
        []
    }

    func liveMessages(token: String) -> AsyncThrowingStream<MessageRecord, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

private final class FakeChatListGroupService: GroupService, @unchecked Sendable {
    var createRequests: [(name: String, members: [GroupMemberKeyDTO])] = []
    var listedGroups: [GroupSummary] = []
    var listTokens: [String] = []
    var fetchGroupCalls: [String] = []
    var keysByGroup: [String: [GroupKeyRecord]] = [:]
    private var details: [String: GroupDetail] = [
        "group-1": GroupDetail(
            id: "group-1",
            name: "Ops",
            creatorId: "user-a",
            currentEpoch: 0,
            createdAt: "2026-06-03T00:00:00Z",
            members: [
                GroupMemberDTO(userId: "user-a", username: "alice", joinedEpoch: 0),
                GroupMemberDTO(userId: "user-b", username: "bob", joinedEpoch: 0)
            ]
        )
    ]

    func createGroup(token: String, name: String, members: [GroupMemberKeyDTO]) async -> CreateGroupResponse? {
        createRequests.append((name, members))
        let refs = members.map { GroupMemberRefDTO(userId: "user-\($0.username)", username: $0.username) }
        details["group-1"] = GroupDetail(
            id: "group-1",
            name: name,
            creatorId: "user-a",
            currentEpoch: 0,
            createdAt: "2026-06-03T00:00:00Z",
            members: refs.map { GroupMemberDTO(userId: $0.userId, username: $0.username, joinedEpoch: 0) }
        )
        listedGroups = [
            GroupSummary(id: "group-1", name: name, creatorId: "user-a", currentEpoch: 0, joinedEpoch: 0, createdAt: "2026-06-03T00:00:00Z")
        ]
        return CreateGroupResponse(groupId: "group-1", epoch: 0, members: refs)
    }

    func listGroups(token: String) async -> [GroupSummary] {
        listTokens.append(token)
        return listedGroups
    }

    func fetchGroup(id: String, token: String) async -> GroupDetail? {
        fetchGroupCalls.append(id)
        return details[id]
    }

    func addMember(groupId: String, token: String, username: String, epoch: UInt32, keys: [WrappedKeyDTO]) async -> AddMemberResponse? {
        nil
    }

    func fetchKeys(groupId: String, token: String) async -> [GroupKeyRecord] {
        keysByGroup[groupId] ?? []
    }

    func sendGroupMessage(groupId: String, token: String, epoch: UInt32, ciphertext: String) async -> SendGroupMessageResult {
        .failure("unused")
    }

    func groupHistory(groupId: String, token: String, since: String?) async -> [GroupMessageRecord] {
        []
    }

    func liveGroupMessages(
        groupId: String,
        token: String,
        onEpochChange: (@Sendable (GroupEpochEvent) -> Void)?
    ) -> AsyncThrowingStream<GroupMessageRecord, Error> {
        AsyncThrowingStream { _ in }
    }
}

private final class FakeChatListAttachmentService: AttachmentService, @unchecked Sendable {
    func upload(token: String, encryptedBlob: Data) async -> String? {
        nil
    }

    func download(token: String, attachmentId: String) async -> Data? {
        nil
    }
}
