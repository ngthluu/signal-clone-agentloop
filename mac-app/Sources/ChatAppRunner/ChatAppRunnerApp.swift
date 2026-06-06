import ChatApp
import SwiftUI

@main
struct ChatAppRunnerApp: App {
    private let runtime = ChatAppRuntime()

    var body: some Scene {
        WindowGroup {
            AppRootView(runtime: runtime)
        }
    }
}
