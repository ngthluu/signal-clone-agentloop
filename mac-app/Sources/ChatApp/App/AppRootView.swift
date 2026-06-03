import SwiftUI

struct AppRootView: View {
    @StateObject var coordinator: RegistrationCoordinator
    @StateObject var authCoordinator: AuthCoordinator
    let accountStore: LocalAccountStore

    @State private var autoSignInAttempted = false

    var body: some View {
        if coordinator.isRegistered {
            if authCoordinator.isAuthenticated {
                MainView {
                    autoSignInAttempted = true
                    authCoordinator.signOut()
                }
            } else {
                SignInView(username: accountStore.currentAccount()?.username ?? "Unknown account") {
                    await authCoordinator.signIn()
                    return authCoordinator.statusMessage
                }
                .task {
                    await autoSignInIfNeeded()
                }
                .onChange(of: coordinator.isRegistered) { _ in
                    Task {
                        await autoSignInIfNeeded()
                    }
                }
            }
        } else {
            RegistrationView { username in
                await coordinator.register(username: username)
                return coordinator.statusMessage
            }
        }
    }

    private func autoSignInIfNeeded() async {
        guard coordinator.isRegistered, !authCoordinator.isAuthenticated, !autoSignInAttempted else {
            return
        }
        autoSignInAttempted = true
        await authCoordinator.signIn()
    }
}
