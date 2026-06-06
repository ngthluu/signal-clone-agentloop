import Foundation

@MainActor
public final class ChatAppRuntime {
    let accountStore: LocalAccountStore
    let coordinator: RegistrationCoordinator
    let authCoordinator: AuthCoordinator
    let dmCoordinator: DMCoordinator
    let groupCoordinator: GroupCoordinator
    let conversationListStore: ConversationListStore
    let chatListStore: ChatListStore

    public convenience init() {
        self.init(
            identityManager: IdentityManager(),
            accountStore: LocalAccountStore(),
            sessionStore: SessionStore(),
            x25519KeyManager: X25519KeyManager()
        )
    }

    init(
        identityManager: IdentityManager,
        accountStore: LocalAccountStore,
        sessionStore: SessionStore,
        x25519KeyManager: X25519KeyManager
    ) {
        self.accountStore = accountStore

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
        chatListStore = ChatListStore(
            conversationListStore: conversationListStore,
            groupCoordinator: groupCoordinator
        )
    }
}
