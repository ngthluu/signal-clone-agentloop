import SwiftUI

@main
struct ChatAppApp: App {
    private let identityManager = IdentityManager()
    private let accountStore = LocalAccountStore()
    private let sessionStore = SessionStore()
    private let coordinator: RegistrationCoordinator
    private let authCoordinator: AuthCoordinator
    private let dmCoordinator: DMCoordinator
    private let conversationListStore: ConversationListStore

    init() {
        let messageService = HTTPMessageService()
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
            x25519KeyManager: X25519KeyManager(),
            sessionStore: sessionStore,
            accountStore: accountStore,
            service: messageService,
            crypto: MessageCrypto()
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
                conversationListStore: conversationListStore,
                accountStore: accountStore
            )
        }
    }
}
