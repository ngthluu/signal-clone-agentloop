import Foundation

@MainActor
final class AuthCoordinator: ObservableObject {
    @Published var isAuthenticated: Bool
    @Published var statusMessage: String = ""

    private let identityProvider: IdentityProviding
    private let service: AuthenticationService
    private let sessionStore: SessionStore
    private let accountStore: LocalAccountStore

    init(
        identityProvider: IdentityProviding,
        service: AuthenticationService,
        sessionStore: SessionStore,
        accountStore: LocalAccountStore
    ) {
        self.identityProvider = identityProvider
        self.service = service
        self.sessionStore = sessionStore
        self.accountStore = accountStore
        self.isAuthenticated = sessionStore.load() != nil
    }

    func signIn() async {
        guard let account = accountStore.currentAccount() else {
            isAuthenticated = false
            statusMessage = "No registered account found."
            return
        }

        do {
            let identity = try identityProvider.loadOrCreate()

            switch await service.requestChallenge(username: account.username) {
            case let .challenge(challengeId, nonceBase64):
                guard let nonceData = Data(base64Encoded: nonceBase64) else {
                    isAuthenticated = false
                    statusMessage = "Authentication challenge was invalid."
                    return
                }

                let signatureBase64 = identity.sign(nonceData).base64EncodedString()
                switch await service.verify(
                    challengeId: challengeId,
                    signatureBase64: signatureBase64
                ) {
                case let .success(token, _, _):
                    try sessionStore.save(token)
                    isAuthenticated = true
                    statusMessage = ""
                case .rejected:
                    isAuthenticated = false
                    statusMessage = "Authentication proof was rejected."
                case let .failure(message):
                    isAuthenticated = false
                    statusMessage = message.isEmpty ? "Authentication verification failed." : message
                }
            case .unknownAccount:
                isAuthenticated = false
                statusMessage = "Registered account was not found on the server."
            case let .failure(message):
                isAuthenticated = false
                statusMessage = message.isEmpty ? "Authentication challenge failed." : message
            }
        } catch {
            isAuthenticated = false
            statusMessage = "Authentication failed."
        }
    }

    func signOut() {
        try? sessionStore.clear()
        isAuthenticated = false
    }
}
