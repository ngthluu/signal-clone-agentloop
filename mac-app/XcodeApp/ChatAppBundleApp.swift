import ChatApp
import SwiftUI

@main
struct ChatAppBundleApp: App {
    private let runtime = ChatAppRuntime()

    var body: some Scene {
        WindowGroup {
            AppRootView(runtime: runtime)
        }
    }
}
