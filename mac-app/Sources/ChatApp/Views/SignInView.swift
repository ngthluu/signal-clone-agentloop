import SwiftUI

struct SignInView: View {
    let username: String
    var onSignIn: (() async -> String)? = nil

    @State private var statusMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sign In")
                .font(.title)

            Text(username)
                .foregroundStyle(.secondary)

            Button("Sign In") {
                Task {
                    if let onSignIn {
                        statusMessage = await onSignIn()
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
