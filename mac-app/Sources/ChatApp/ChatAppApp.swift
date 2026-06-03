import SwiftUI

@main
struct ChatAppApp: App {
    var body: some Scene {
        WindowGroup {
            PlaceholderRootView()
        }
    }
}

private struct PlaceholderRootView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Chat App")
                .font(.title)
            Text("App scaffold is ready.")
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 420, minHeight: 280)
        .padding()
    }
}
