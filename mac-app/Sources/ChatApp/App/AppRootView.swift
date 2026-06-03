import SwiftUI

struct AppRootView: View {
    @StateObject var coordinator: RegistrationCoordinator

    var body: some View {
        if coordinator.isRegistered {
            MainView()
        } else {
            RegistrationView { username in
                await coordinator.register(username: username)
                return coordinator.statusMessage
            }
        }
    }
}
