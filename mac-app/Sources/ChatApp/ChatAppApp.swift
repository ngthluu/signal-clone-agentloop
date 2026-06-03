import SwiftUI

@main
struct ChatAppApp: App {
    private let identityManager = IdentityManager()
    private let accountStore = LocalAccountStore()
    private let sessionStore = SessionStore()
    private let coordinator: RegistrationCoordinator
    private let authCoordinator: AuthCoordinator

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
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(
                coordinator: coordinator,
                authCoordinator: authCoordinator,
                accountStore: accountStore
            )
        }
    }
}
