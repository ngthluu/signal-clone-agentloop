import Foundation

protocol RegistrationService: Sendable {
    func register(username: String, publicKeyBase64: String) async -> RegistrationResult
}

enum RegistrationResult: Sendable {
    case success(userId: String)
    case usernameTaken
    case invalid
    case failure(String)
}

struct HTTPRegistrationClient: RegistrationService {
    private let session: URLSession
    private let baseURL: URL

    init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "http://127.0.0.1:3000")!
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    func register(username: String, publicKeyBase64: String) async -> RegistrationResult {
        let payload = RegisterPayload(username: username, identityPublicKey: publicKeyBase64)

        do {
            var request = URLRequest(url: baseURL.appendingPathComponent("register"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(payload)

            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure("Registration server returned an invalid response.")
            }

            switch httpResponse.statusCode {
            case 201:
                guard let userId = try decodeUserId(from: data) else {
                    return .failure("Registration server returned an invalid response.")
                }
                return .success(userId: userId)
            case 409:
                return .usernameTaken
            case 400:
                return .invalid
            default:
                return .failure("Registration failed with status \(httpResponse.statusCode).")
            }
        } catch {
            return .failure("Registration request failed.")
        }
    }

    private func decodeUserId(from data: Data) throws -> String? {
        let response = try JSONDecoder().decode(RegisterResponse.self, from: data)
        return response.userId
    }
}

private struct RegisterResponse: Decodable {
    let userId: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
    }
}
