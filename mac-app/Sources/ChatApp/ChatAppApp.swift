import SwiftUI

@main
struct ChatAppApp: App {
    private let coordinator = RegistrationCoordinator(
        identityProvider: IdentityManager(),
        service: HTTPRegistrationClient(),
        accountStore: LocalAccountStore()
    )

    var body: some Scene {
        WindowGroup {
            AppRootView(coordinator: coordinator)
        }
    }
}
