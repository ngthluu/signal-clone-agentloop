import Foundation

struct LocalAccountStore: AccountStore {
    private let directory: URL
    private let fileManager: FileManager

    private var accountFile: URL {
        directory.appendingPathComponent("account.json", isDirectory: false)
    }

    var hasAccount: Bool {
        currentAccount() != nil
    }

    init(directory: URL = LocalAccountStore.defaultDirectory(), fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func currentAccount() -> LocalAccount? {
        guard let data = try? Data(contentsOf: accountFile) else {
            return nil
        }

        return try? JSONDecoder().decode(LocalAccount.self, from: data)
    }

    func save(_ account: LocalAccount) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(account)
        try data.write(to: accountFile, options: [.atomic])
    }

    func clear() throws {
        guard fileManager.fileExists(atPath: accountFile.path) else {
            return
        }

        try fileManager.removeItem(at: accountFile)
    }

    private static func defaultDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ChatApp", isDirectory: true)
    }
}
