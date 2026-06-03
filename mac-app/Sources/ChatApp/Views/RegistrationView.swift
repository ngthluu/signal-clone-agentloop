import SwiftUI

struct RegistrationView: View {
    var onRegister: ((String) async -> String)? = nil

    @State private var username = ""
    @State private var statusMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Register")
                .font(.title)

            TextField("Username", text: $username)
                .textFieldStyle(.roundedBorder)

            Button("Register") {
                Task {
                    if let onRegister {
                        statusMessage = await onRegister(username)
                    }
                }
            }

            Text(statusMessage)
                .foregroundStyle(.secondary)
                .frame(minHeight: 20, alignment: .leading)
        }
        .padding(24)
        .frame(minWidth: 420, minHeight: 280)
    }
}
