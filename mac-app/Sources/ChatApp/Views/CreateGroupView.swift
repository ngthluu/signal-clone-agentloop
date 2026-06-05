import SwiftUI

struct CreateGroupView: View {
    @ObservedObject var store: ChatListStore
    @Environment(\.dismiss) private var dismiss
    @State private var groupName = ""
    @State private var memberUsernames = ""
    @State private var isCreating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Group")
                .font(.headline)

            TextField("Group name", text: $groupName)
                .textFieldStyle(.roundedBorder)

            TextField("Members", text: $memberUsernames)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button(isCreating ? "Creating" : "Create") {
                    createGroup()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate || isCreating)
            }

            if !store.groupCoordinator.statusMessage.isEmpty {
                Text(store.groupCoordinator.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(16)
        .frame(width: 360)
    }

    private var canCreate: Bool {
        !groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && Set(parsedUsernames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }).count >= 2
    }

    private var parsedUsernames: [String] {
        memberUsernames
            .split { character in
                character == "," || character == " " || character == "\n" || character == "\t"
            }
            .map { String($0) }
    }

    private func createGroup() {
        isCreating = true
        Task {
            let created = await store.createGroup(name: groupName, memberUsernames: parsedUsernames)
            isCreating = false
            if created {
                dismiss()
            }
        }
    }
}
