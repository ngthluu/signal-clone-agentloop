import SwiftUI

enum ChatListSidebarState: Equatable {
    case loading
    case empty
    case populated

    static func resolve(rows: [ChatListItem], isLoading: Bool, hasLoaded: Bool) -> ChatListSidebarState {
        if !rows.isEmpty {
            return .populated
        }
        if isLoading || !hasLoaded {
            return .loading
        }
        return .empty
    }
}

struct ChatListView: View {
    @ObservedObject var store: ChatListStore
    @State private var newUsername = ""
    @State private var isShowingNewGroup = false

    private var sidebarState: ChatListSidebarState {
        ChatListSidebarState.resolve(
            rows: store.rows,
            isLoading: store.isLoading,
            hasLoaded: store.hasLoaded
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Chats")
                    .font(.headline)
                Spacer()
                Button {
                    isShowingNewGroup = true
                } label: {
                    Image(systemName: "person.3.fill")
                }
                .help("New group")
            }
            .padding([.horizontal, .top], 12)

            sidebarContent

            HStack(spacing: 8) {
                TextField("Username", text: $newUsername)
                    .textFieldStyle(.roundedBorder)
                Button {
                    selectNewConversation()
                } label: {
                    Image(systemName: "plus")
                }
                .help("New direct message")
                .disabled(newUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding([.horizontal, .bottom], 12)
        }
        .navigationTitle("Messages")
        .frame(minWidth: 240)
        .sheet(isPresented: $isShowingNewGroup) {
            CreateGroupView(store: store)
        }
    }

    @ViewBuilder
    private var sidebarContent: some View {
        switch sidebarState {
        case .loading:
            sidebarPlaceholder {
                ProgressView()
                Text("Loading chats")
                    .foregroundStyle(.secondary)
            }
        case .empty:
            sidebarPlaceholder {
                Text("No chats yet")
                    .foregroundStyle(.secondary)
            }
        case .populated:
            List(store.rows) { row in
                Button {
                    Task {
                        await store.select(row)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: row.kind == .group ? "person.3" : "person")
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.title)
                                .font(.body)
                                .lineLimit(1)
                            Text(row.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(store.selectedRow?.id == row.id ? Color.accentColor.opacity(0.14) : Color.clear)
            }
        }
    }

    private func sidebarPlaceholder<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 10) {
            Spacer()
            content()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func selectNewConversation() {
        let username = newUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty else {
            return
        }
        newUsername = ""
        Task {
            await store.selectDirect(username: username)
        }
    }
}
