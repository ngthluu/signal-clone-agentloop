import SwiftUI

struct AuthenticatedWorkspaceView: View {
    @ObservedObject var chatListStore: ChatListStore
    @ObservedObject var listStore: ConversationListStore
    @ObservedObject var dmCoordinator: DMCoordinator
    @ObservedObject var groupCoordinator: GroupCoordinator
    var onSignOut: (() -> Void)?

    init(
        chatListStore: ChatListStore,
        listStore: ConversationListStore,
        dmCoordinator: DMCoordinator,
        groupCoordinator: GroupCoordinator,
        onSignOut: (() -> Void)? = nil
    ) {
        self.chatListStore = chatListStore
        self.listStore = listStore
        self.dmCoordinator = dmCoordinator
        self.groupCoordinator = groupCoordinator
        self.onSignOut = onSignOut
    }

    init(runtime: ChatAppRuntime, onSignOut: (() -> Void)? = nil) {
        self.init(
            chatListStore: runtime.chatListStore,
            listStore: runtime.conversationListStore,
            dmCoordinator: runtime.dmCoordinator,
            groupCoordinator: runtime.groupCoordinator,
            onSignOut: onSignOut
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Chat")
                    .font(.title)
                Spacer()
                if let onSignOut {
                    Button("Sign Out", action: onSignOut)
                }
            }
            ConversationsView(
                chatListStore: chatListStore,
                listStore: listStore,
                dmCoordinator: dmCoordinator,
                groupCoordinator: groupCoordinator
            )
        }
        .padding(24)
        .frame(minWidth: 760, minHeight: 520)
    }
}
