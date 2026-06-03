import XCTest
@testable import ChatApp

final class AppRouterTests: XCTestCase {
    func testResolveReturnsRegistrationWhenNoAccountExists() {
        let store = StubAccountStore(hasAccount: false)

        let screen = AppRouter.resolve(for: store)

        XCTAssertEqual(screen, .registration)
    }

    func testResolveReturnsMainWhenAccountExists() {
        let store = StubAccountStore(hasAccount: true)

        let screen = AppRouter.resolve(for: store)

        XCTAssertEqual(screen, .main)
    }
}

private struct StubAccountStore: AccountStore {
    let hasAccount: Bool
}
