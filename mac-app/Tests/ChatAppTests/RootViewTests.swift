import XCTest
@testable import ChatApp

final class RootViewTests: XCTestCase {
    @MainActor
    func testResolvedScreenIsRegistrationWhenNoAccountExists() {
        let view = RootView(store: StubAccountStore(hasAccount: false))

        XCTAssertEqual(view.resolvedScreen, .registration)
    }

    @MainActor
    func testResolvedScreenIsMainWhenAccountExists() {
        let view = RootView(store: StubAccountStore(hasAccount: true))

        XCTAssertEqual(view.resolvedScreen, .main)
    }

    @MainActor
    func testMainRouteBuildsAuthenticatedWorkspaceSurface() {
        let view = RootView(store: StubAccountStore(hasAccount: true))

        XCTAssertEqual(view.mainRouteSurface, .authenticatedWorkspace)
    }
}

private struct StubAccountStore: AccountStore {
    let hasAccount: Bool
}
