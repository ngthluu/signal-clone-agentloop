import SwiftUI

struct MainView: View {
    let runtime: ChatAppRuntime
    var onSignOut: (() -> Void)? = nil

    init(runtime: ChatAppRuntime, onSignOut: (() -> Void)? = nil) {
        self.runtime = runtime
        self.onSignOut = onSignOut
    }

    var body: some View {
        AuthenticatedWorkspaceView(runtime: runtime, onSignOut: onSignOut)
    }
}
