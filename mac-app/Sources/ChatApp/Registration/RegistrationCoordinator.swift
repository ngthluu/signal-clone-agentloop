import Combine
import Foundation

@MainActor
final class RegistrationCoordinator: ObservableObject {
    @Published var isRegistered: Bool
    @Published var statusMessage: String = ""

    private let identityProvider: IdentityProviding
    private let service: RegistrationService
    private let accountStore: LocalAccountStore

    init(
        identityProvider: IdentityProviding,
        service: RegistrationService,
        accountStore: LocalAccountStore
    ) {
        self.identityProvider = identityProvider
        self.service = service
        self.accountStore = accountStore
        self.isRegistered = accountStore.hasAccount
    }

    func register(username: String) async {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty else {
            statusMessage = "Please enter a username."
            return
        }

        let identity: CryptoIdentity
        do {
            identity = try identityProvider.loadOrCreate()
        } catch {
            statusMessage = "Couldn't reach the server. Please try again."
            return
        }

        let result = await service.register(
            username: trimmedUsername,
            publicKeyBase64: identity.publicKeyBase64
        )

        switch result {
        case .success(let userId):
            do {
                try accountStore.save(LocalAccount(
                    username: trimmedUsername,
                    publicKeyBase64: identity.publicKeyBase64,
                    userId: userId
                ))
                isRegistered = true
                statusMessage = ""
            } catch {
                statusMessage = "Couldn't reach the server. Please try again."
            }
        case .usernameTaken:
            statusMessage = "That username is already taken. Pick another."
        case .invalid:
            statusMessage = "Please choose a valid username."
        case .failure:
            statusMessage = "Couldn't reach the server. Please try again."
        }
    }
}
