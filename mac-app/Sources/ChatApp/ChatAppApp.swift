import SwiftUI

@main
struct ChatAppApp: App {
    private let identityManager = IdentityManager()
    private let accountStore = LocalAccountStore()
    private let sessionStore = SessionStore()
    private let coordinator: RegistrationCoordinator
    private let authCoordinator: AuthCoordinator
    private let dmCoordinator: DMCoordinator

    init() {
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
            service: HTTPMessageService(),
            crypto: MessageCrypto()
        )
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(
                coordinator: coordinator,
                authCoordinator: authCoordinator,
                dmCoordinator: dmCoordinator,
                accountStore: accountStore
            )
        }
    }
}
