import SwiftUI

@main
struct ChatAppApp: App {
    private let identityManager = IdentityManager()
    private let accountStore = LocalAccountStore()
    private let sessionStore = SessionStore()
    private let x25519KeyManager = X25519KeyManager()
    private let coordinator: RegistrationCoordinator
    private let authCoordinator: AuthCoordinator
    private let dmCoordinator: DMCoordinator
    private let groupCoordinator: GroupCoordinator
    private let conversationListStore: ConversationListStore

    init() {
        let messageService = HTTPMessageService()
        let groupService = HTTPGroupService()
        let attachmentService = HTTPAttachmentService()
        coordinator = RegistrationCoordinator(
            identityProvider: identityManager,
            service: HTTPRegistrationClient(),
            accountStore: accountStore
        )
        authCoordinator = AuthCoordinator(
            identityProvider: identityManager,
            service: HTTPAuthClient(),
            sessionStore: sessionStore,
            accountStore: accountStore
        )
        dmCoordinator = DMCoordinator(
            identityProvider: identityManager,
            x25519KeyManager: x25519KeyManager,
            sessionStore: sessionStore,
            accountStore: accountStore,
            service: messageService,
            crypto: MessageCrypto(),
            attachmentService: attachmentService,
            fileCrypto: FileCrypto()
        )
        groupCoordinator = GroupCoordinator(
            identityProvider: identityManager,
            x25519KeyManager: x25519KeyManager,
            sessionStore: sessionStore,
            accountStore: accountStore,
            messageService: messageService,
            groupService: groupService,
            crypto: GroupCrypto(),
            attachmentService: attachmentService,
            fileCrypto: FileCrypto()
        )
        conversationListStore = ConversationListStore(
            service: messageService,
            sessionStore: sessionStore,
            accountStore: accountStore,
            makeLiveStream: { token in
                messageService.liveMessages(token: token)
            }
        )
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(
                coordinator: coordinator,
                authCoordinator: authCoordinator,
                dmCoordinator: dmCoordinator,
                groupCoordinator: groupCoordinator,
                conversationListStore: conversationListStore,
                accountStore: accountStore
            )
        }
    }
}
