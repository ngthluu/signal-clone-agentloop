import SwiftUI

enum MainRouteSurface: Equatable {
    case authenticatedWorkspace
}

struct RootView: View {
    let store: any AccountStore
    let runtime: ChatAppRuntime

    init(store: any AccountStore, runtime: ChatAppRuntime = ChatAppRuntime()) {
        self.store = store
        self.runtime = runtime
    }

    var resolvedScreen: Screen {
        AppRouter.resolve(for: store)
    }

    var mainRouteSurface: MainRouteSurface {
        .authenticatedWorkspace
    }

    var body: some View {
        switch resolvedScreen {
        case .registration:
            RegistrationView()
        case .main:
            MainView(runtime: runtime)
        }
    }
}
