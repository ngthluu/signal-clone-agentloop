import CryptoKit
import Foundation
import XCTest
@testable import ChatApp

final class AppRootViewTests: XCTestCase {
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
    func testContentRouteIsRegistrationWhenNoAccountExists() throws {
        let harness = try makeHarness(hasAccount: false, hasSession: false)
        let view = harness.makeView()

        XCTAssertEqual(view.contentRoute, .registration)
    }

    @MainActor
    func testContentRouteIsSignInWhenRegisteredButUnauthenticated() throws {
        let harness = try makeHarness(hasAccount: true, hasSession: false)
        let view = harness.makeView()

        XCTAssertEqual(view.contentRoute, .signIn(username: "alice"))
    }

    @MainActor
    func testContentRouteIsAuthenticatedWorkspaceWhenRegisteredWithSession() throws {
        let harness = try makeHarness(hasAccount: true, hasSession: true)
        let view = harness.makeView()

        XCTAssertEqual(view.contentRoute, .authenticatedWorkspace)
    }

    @MainActor
    func testSigningOutReturnsRouteToSignIn() throws {
        let harness = try makeHarness(hasAccount: true, hasSession: true)
        harness.authCoordinator.signOut()
        let view = harness.makeView()

        XCTAssertEqual(view.contentRoute, .signIn(username: "alice"))
    }

    @MainActor
    private func makeHarness(hasAccount: Bool, hasSession: Bool) throws -> Harness {
        let identity = CryptoIdentity(privateKey: Curve25519.Signing.PrivateKey())
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("app-root-view-\(UUID().uuidString)", isDirectory: true)
        cleanupURLs.append(directory)
        let accountStore = LocalAccountStore(directory: directory)
        if hasAccount {
            try accountStore.save(LocalAccount(
                username: "alice",
                publicKeyBase64: identity.publicKeyBase64,
                userId: "user-a"
            ))
        }

        let sessionKeychain = KeychainStore(
            service: "\(KeychainStore.defaultService).app-root.tests.\(UUID().uuidString)",
            account: "\(KeychainStore.defaultAccount).session.tests",
            usesDataProtectionKeychain: false
        )
        let x25519Keychain = KeychainStore(
            service: "\(KeychainStore.defaultService).app-root.tests.\(UUID().uuidString)",
            account: "\(KeychainStore.defaultAccount).x25519.tests",
            usesDataProtectionKeychain: false
        )
        keychainStores.append(sessionKeychain)
        keychainStores.append(x25519Keychain)
        let sessionStore = SessionStore(keychainStore: sessionKeychain)
        if hasSession {
            try sessionStore.save("token-1")
        }

        let identityProvider = StubAppRootIdentityProvider(identity: identity)
        let messageService = FakeAppRootMessageService()
        let attachmentService = FakeAppRootAttachmentService()
        let x25519KeyManager = X25519KeyManager(keychainStore: x25519Keychain)
        _ = try x25519KeyManager.loadOrCreate()

        let registrationCoordinator = RegistrationCoordinator(
            identityProvider: identityProvider,
            service: FakeAppRootRegistrationService(),
            accountStore: accountStore
        )
        let authCoordinator = AuthCoordinator(
            identityProvider: identityProvider,
            service: FakeAppRootAuthenticationService(),
            sessionStore: sessionStore,
            accountStore: accountStore
        )
        let dmCoordinator = DMCoordinator(
            identityProvider: identityProvider,
            x25519KeyManager: x25519KeyManager,
            sessionStore: sessionStore,
            accountStore: accountStore,
            service: messageService,
            crypto: MessageCrypto(),
            attachmentService: attachmentService,
            fileCrypto: FileCrypto()
        )
        let groupCoordinator = GroupCoordinator(
            identityProvider: identityProvider,
            x25519KeyManager: x25519KeyManager,
            sessionStore: sessionStore,
            accountStore: accountStore,
            messageService: messageService,
            groupService: FakeAppRootGroupService(),
            crypto: GroupCrypto(),
            attachmentService: attachmentService,
            fileCrypto: FileCrypto()
        )
        let conversationListStore = ConversationListStore(
            service: messageService,
            sessionStore: sessionStore,
            accountStore: accountStore,
            makeLiveStream: { _ in AsyncThrowingStream { $0.finish() } }
        )

        return Harness(
            registrationCoordinator: registrationCoordinator,
            authCoordinator: authCoordinator,
            dmCoordinator: dmCoordinator,
            groupCoordinator: groupCoordinator,
            conversationListStore: conversationListStore,
            accountStore: accountStore
        )
    }
}

private struct Harness {
    let registrationCoordinator: RegistrationCoordinator
    let authCoordinator: AuthCoordinator
    let dmCoordinator: DMCoordinator
    let groupCoordinator: GroupCoordinator
    let conversationListStore: ConversationListStore
    let accountStore: LocalAccountStore

    @MainActor
    func makeView() -> AppRootView {
        AppRootView(
            coordinator: registrationCoordinator,
            authCoordinator: authCoordinator,
            dmCoordinator: dmCoordinator,
            groupCoordinator: groupCoordinator,
            conversationListStore: conversationListStore,
            accountStore: accountStore
        )
    }
}

private struct StubAppRootIdentityProvider: IdentityProviding {
    let identity: CryptoIdentity

    func loadOrCreate() throws -> CryptoIdentity {
        identity
    }
}

private struct FakeAppRootRegistrationService: RegistrationService {
    func register(username: String, publicKeyBase64: String) async -> RegistrationResult {
        .success(userId: "user-a")
    }
}

private struct FakeAppRootAuthenticationService: AuthenticationService {
    func requestChallenge(username: String) async -> ChallengeResult {
        .failure("unused")
    }

    func verify(challengeId: String, signatureBase64: String) async -> VerifyResult {
        .failure("unused")
    }

    func validateSession(token: String) async -> Bool {
        true
    }
}

private struct FakeAppRootMessageService: MessageService, ConversationsService {
    func publishPrekey(token: String, x25519PublicKey: String, signature: String) async -> Bool {
        true
    }

    func fetchPrekey(username: String, token: String) async -> PrekeyResponse? {
        nil
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

private struct FakeAppRootAttachmentService: AttachmentService {
    func upload(token: String, encryptedBlob: Data) async -> String? {
        nil
    }

    func download(token: String, attachmentId: String) async -> Data? {
        nil
    }
}

private struct FakeAppRootGroupService: GroupService {
    func createGroup(token: String, name: String, members: [GroupMemberKeyDTO]) async -> CreateGroupResponse? {
        nil
    }

    func listGroups(token: String) async -> [GroupSummary] {
        []
    }

    func fetchGroup(id: String, token: String) async -> GroupDetail? {
        nil
    }

    func addMember(groupId: String, token: String, username: String, epoch: UInt32, keys: [WrappedKeyDTO]) async -> AddMemberResponse? {
        nil
    }

    func fetchKeys(groupId: String, token: String) async -> [GroupKeyRecord] {
        []
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
        AsyncThrowingStream { $0.finish() }
    }
}
