import Foundation

struct SessionStore {
    private let keychainStore: KeychainStore

    init(
        keychainStore: KeychainStore = KeychainStore(account: "\(KeychainStore.defaultAccount).session")
    ) {
        self.keychainStore = keychainStore
    }

    func save(_ token: String) throws {
        try keychainStore.save(Data(token.utf8))
    }

    func load() -> String? {
        guard
            let data = try? keychainStore.load(),
            let token = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return token
    }

    func clear() throws {
        try keychainStore.delete()
    }
}
