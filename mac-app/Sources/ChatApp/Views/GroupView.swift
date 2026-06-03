import SwiftUI

struct GroupView: View {
    @ObservedObject var coordinator: GroupCoordinator
    var onCreateGroup: ((String, [String]) async -> Void)? = nil
    var onOpenGroup: ((String) async -> Void)? = nil
    var onAddMember: ((String) async -> Void)? = nil
    var onSend: ((String) async -> Void)? = nil

    @State private var groupName = ""
    @State private var memberUsernames = ""
    @State private var groupId = ""
    @State private var newMemberUsername = ""
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                TextField("Group name", text: $groupName)
                    .textFieldStyle(.roundedBorder)
                TextField("Members", text: $memberUsernames)
                    .textFieldStyle(.roundedBorder)
                Button("Create") {
                    let usernames = parsedUsernames(memberUsernames)
                    Task {
                        if let onCreateGroup {
                            await onCreateGroup(groupName, usernames)
                        } else {
                            await coordinator.createGroup(name: groupName, memberUsernames: usernames)
                        }
                    }
                }
                .disabled(groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            HStack(spacing: 8) {
                TextField("Group id", text: $groupId)
                    .textFieldStyle(.roundedBorder)
                Button("Open") {
                    Task {
                        if let onOpenGroup {
                            await onOpenGroup(groupId)
                        } else {
                            await coordinator.openGroup(id: groupId)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Text(coordinator.groupName.isEmpty ? "No group open" : coordinator.groupName)
                    .font(.headline)
                Text("Epoch \(coordinator.currentEpoch)")
                    .foregroundStyle(.secondary)
                Spacer()
                TextField("Add username", text: $newMemberUsername)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 180)
                Button("Add") {
                    let username = newMemberUsername
                    newMemberUsername = ""
                    Task {
                        if let onAddMember {
                            await onAddMember(username)
                        } else {
                            await coordinator.addMember(username: username)
                        }
                    }
                }
                .disabled(coordinator.groupId == nil || newMemberUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !coordinator.members.isEmpty {
                Text(coordinator.members.map(\.username).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(coordinator.messages) { message in
                        HStack {
                            if message.isMine {
                                Spacer(minLength: 48)
                            }
                            VStack(alignment: message.isMine ? .trailing : .leading, spacing: 3) {
                                Text(message.text)
                                    .padding(.vertical, 7)
                                    .padding(.horizontal, 10)
                                    .background(message.isMine ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                Text(message.senderId)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if !message.isMine {
                                Spacer(minLength: 48)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 220)

            HStack(spacing: 8) {
                TextField("Message", text: $draft)
                    .textFieldStyle(.roundedBorder)
                Button("Send") {
                    let text = draft
                    draft = ""
                    Task {
                        if let onSend {
                            await onSend(text)
                        } else {
                            await coordinator.send(text: text)
                        }
                    }
                }
                .disabled(coordinator.groupId == nil || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Text(coordinator.statusMessage)
                .foregroundStyle(.secondary)
                .frame(minHeight: 20, alignment: .leading)
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 460)
    }

    private func parsedUsernames(_ value: String) -> [String] {
        value
            .split { character in
                character == "," || character == " " || character == "\n" || character == "\t"
            }
            .map { String($0) }
    }
}
