import SwiftUI

@main
struct ChatAppApp: App {
    private let runtime = ChatAppRuntime()

    var body: some Scene {
        WindowGroup {
            AppRootView(runtime: runtime)
        }
    }
}
