protocol AccountStore {
    var hasAccount: Bool { get }
}

struct InMemoryAccountStore: AccountStore {
    var hasAccount: Bool

    init(hasAccount: Bool = false) {
        self.hasAccount = hasAccount
    }
}
