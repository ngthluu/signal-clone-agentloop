enum AppRouter {
    static func resolve(for store: AccountStore) -> Screen {
        store.hasAccount ? .main : .registration
    }
}
