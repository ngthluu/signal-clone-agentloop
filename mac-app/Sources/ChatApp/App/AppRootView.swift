import SwiftUI

enum AppRootContentRoute: Equatable {
    case registration
    case signIn(username: String)
    case authenticatedWorkspace
}

struct AppRootView: View {
    @StateObject var coordinator: RegistrationCoordinator
    @StateObject var authCoordinator: AuthCoordinator
    @StateObject var dmCoordinator: DMCoordinator
    @StateObject var groupCoordinator: GroupCoordinator
    @StateObject var conversationListStore: ConversationListStore
    @StateObject var chatListStore: ChatListStore
    let accountStore: LocalAccountStore

    @State private var autoSignInAttempted = false

    init(
        coordinator: RegistrationCoordinator,
        authCoordinator: AuthCoordinator,
        dmCoordinator: DMCoordinator,
        groupCoordinator: GroupCoordinator,
        conversationListStore: ConversationListStore,
        accountStore: LocalAccountStore,
        chatListStore: ChatListStore? = nil
    ) {
        _coordinator = StateObject(wrappedValue: coordinator)
        _authCoordinator = StateObject(wrappedValue: authCoordinator)
        _dmCoordinator = StateObject(wrappedValue: dmCoordinator)
        _groupCoordinator = StateObject(wrappedValue: groupCoordinator)
        _conversationListStore = StateObject(wrappedValue: conversationListStore)
        _chatListStore = StateObject(wrappedValue: chatListStore ?? ChatListStore(
            conversationListStore: conversationListStore,
            groupCoordinator: groupCoordinator
        ))
        self.accountStore = accountStore
    }

    init(runtime: ChatAppRuntime) {
        self.init(
            coordinator: runtime.coordinator,
            authCoordinator: runtime.authCoordinator,
            dmCoordinator: runtime.dmCoordinator,
            groupCoordinator: runtime.groupCoordinator,
            conversationListStore: runtime.conversationListStore,
            accountStore: runtime.accountStore,
            chatListStore: runtime.chatListStore
        )
    }

    var contentRoute: AppRootContentRoute {
        if !coordinator.isRegistered {
            return .registration
        }
        if authCoordinator.isAuthenticated {
            return .authenticatedWorkspace
        }
        return .signIn(username: accountStore.currentAccount()?.username ?? "Unknown account")
    }

    var body: some View {
        switch contentRoute {
        case .registration:
            RegistrationView { username in
                await coordinator.register(username: username)
                return coordinator.statusMessage
            }
        case let .signIn(username):
            SignInView(username: username) {
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
        case .authenticatedWorkspace:
            AuthenticatedWorkspaceView(
                chatListStore: chatListStore,
                listStore: conversationListStore,
                dmCoordinator: dmCoordinator,
                groupCoordinator: groupCoordinator,
                onSignOut: {
                    autoSignInAttempted = true
                    authCoordinator.signOut()
                }
            )
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
