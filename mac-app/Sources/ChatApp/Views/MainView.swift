import SwiftUI

struct MainView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Chat")
                .font(.title)
            Text("Main chat screen")
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(minWidth: 420, minHeight: 280)
    }
}
