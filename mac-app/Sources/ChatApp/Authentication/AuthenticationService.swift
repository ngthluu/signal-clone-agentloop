import Foundation

protocol AuthenticationService: Sendable {
    func requestChallenge(username: String) async -> ChallengeResult
    func verify(challengeId: String, signatureBase64: String) async -> VerifyResult
    func validateSession(token: String) async -> Bool
}

enum ChallengeResult: Sendable {
    case challenge(challengeId: String, nonceBase64: String)
    case unknownAccount
    case failure(String)
}

enum VerifyResult: Sendable {
    case success(token: String, userId: String, username: String)
    case rejected
    case failure(String)
}

struct HTTPAuthClient: AuthenticationService {
    private let session: URLSession
    private let baseURL: URL

    init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "http://127.0.0.1:3000")!
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    func requestChallenge(username: String) async -> ChallengeResult {
        let payload = ChallengeRequest(username: username)

        do {
            var request = URLRequest(url: authURL("challenge"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(payload)

            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure("Authentication server returned an invalid response.")
            }

            switch httpResponse.statusCode {
            case 201:
                let response = try JSONDecoder().decode(ChallengeResponse.self, from: data)
                return .challenge(challengeId: response.challengeId, nonceBase64: response.nonce)
            case 404:
                return .unknownAccount
            default:
                return .failure("Challenge request failed with status \(httpResponse.statusCode).")
            }
        } catch {
            return .failure("Challenge request failed.")
        }
    }

    func verify(challengeId: String, signatureBase64: String) async -> VerifyResult {
        let payload = VerifyRequest(challengeId: challengeId, signature: signatureBase64)

        do {
            var request = URLRequest(url: authURL("verify"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(payload)

            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure("Authentication server returned an invalid response.")
            }

            switch httpResponse.statusCode {
            case 200:
                let response = try JSONDecoder().decode(VerifyResponse.self, from: data)
                return .success(token: response.token, userId: response.userId, username: response.username)
            case 401:
                return .rejected
            default:
                return .failure("Verification failed with status \(httpResponse.statusCode).")
            }
        } catch {
            return .failure("Verification request failed.")
        }
    }

    func validateSession(token: String) async -> Bool {
        do {
            var request = URLRequest(url: authURL("session"))
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }
            return httpResponse.statusCode == 200
        } catch {
            return false
        }
    }

    private func authURL(_ component: String) -> URL {
        baseURL
            .appendingPathComponent("auth")
            .appendingPathComponent(component)
    }
}
