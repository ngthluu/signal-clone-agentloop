import SwiftUI

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
        accountStore: LocalAccountStore
    ) {
        _coordinator = StateObject(wrappedValue: coordinator)
        _authCoordinator = StateObject(wrappedValue: authCoordinator)
        _dmCoordinator = StateObject(wrappedValue: dmCoordinator)
        _groupCoordinator = StateObject(wrappedValue: groupCoordinator)
        _conversationListStore = StateObject(wrappedValue: conversationListStore)
        _chatListStore = StateObject(wrappedValue: ChatListStore(
            conversationListStore: conversationListStore,
            groupCoordinator: groupCoordinator
        ))
        self.accountStore = accountStore
    }

    var body: some View {
        if coordinator.isRegistered {
            if authCoordinator.isAuthenticated {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Chat")
                            .font(.title)
                        Spacer()
                        Button("Sign Out") {
                            autoSignInAttempted = true
                            authCoordinator.signOut()
                        }
                    }
                    ConversationsView(
                        chatListStore: chatListStore,
                        listStore: conversationListStore,
                        dmCoordinator: dmCoordinator,
                        groupCoordinator: groupCoordinator
                    )
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
