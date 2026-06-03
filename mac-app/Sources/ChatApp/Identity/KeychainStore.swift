import Foundation
import Security

enum KeychainError: Error, Equatable {
    case unexpectedData
    case unhandledStatus(OSStatus)
}

struct KeychainStore {
    static let defaultService = "com.testchatapp.identity"
    static let defaultAccount = "primary-x25519"

    let service: String
    let account: String
    let usesDataProtectionKeychain: Bool

    init(
        service: String = KeychainStore.defaultService,
        account: String = KeychainStore.defaultAccount,
        usesDataProtectionKeychain: Bool = true
    ) {
        self.service = service
        self.account = account
        self.usesDataProtectionKeychain = usesDataProtectionKeychain
    }

    func save(_ data: Data) throws {
        var query = baseQuery()
        query[kSecValueData as String] = data

        let status = SecItemAdd(query as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            try delete()
            let retryStatus = SecItemAdd(query as CFDictionary, nil)
            guard retryStatus == errSecSuccess else {
                throw KeychainError.unhandledStatus(retryStatus)
            }
        default:
            throw KeychainError.unhandledStatus(status)
        }
    }

    func load() throws -> Data? {
        var query = baseQuery()
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw KeychainError.unexpectedData
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unhandledStatus(status)
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw KeychainError.unhandledStatus(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        if usesDataProtectionKeychain {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        return query
    }
}
