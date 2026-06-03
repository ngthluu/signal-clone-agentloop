import SwiftUI

struct RootView: View {
    let store: any AccountStore

    var resolvedScreen: Screen {
        AppRouter.resolve(for: store)
    }

    var body: some View {
        switch resolvedScreen {
        case .registration:
            RegistrationView()
        case .main:
            MainView()
        }
    }
}
