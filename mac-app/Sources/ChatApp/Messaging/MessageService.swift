import Foundation

protocol MessageService: Sendable {
    func publishPrekey(token: String, x25519PublicKey: String, signature: String) async -> Bool
    func fetchPrekey(username: String, token: String) async -> PrekeyResponse?
    func send(token: String, recipientUsername: String, ciphertext: String) async -> SendMessageResult
    func history(token: String, withUsername username: String, since: String?) async -> [MessageRecord]
}

enum SendMessageResult: Equatable, Sendable {
    case success(messageId: String, createdAt: String)
    case recipientNotFound
    case failure(String)
}

struct HTTPMessageService: MessageService {
    private let session: URLSession
    private let baseURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "http://127.0.0.1:3000")!
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    func publishPrekey(token: String, x25519PublicKey: String, signature: String) async -> Bool {
        let payload = PublishPrekeyRequest(x25519PublicKey: x25519PublicKey, keySignature: signature)

        do {
            var request = URLRequest(url: baseURL.appendingPathComponent("keys"))
            request.httpMethod = "PUT"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.httpBody = try encoder.encode(payload)

            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }
            return httpResponse.statusCode == 200 || httpResponse.statusCode == 201
        } catch {
            return false
        }
    }

    func fetchPrekey(username: String, token: String) async -> PrekeyResponse? {
        do {
            var request = URLRequest(url: baseURL.appendingPathComponent("keys").appendingPathComponent(username))
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            return try decoder.decode(PrekeyResponse.self, from: data)
        } catch {
            return nil
        }
    }

    func send(token: String, recipientUsername: String, ciphertext: String) async -> SendMessageResult {
        let payload = SendMessageRequest(recipientUsername: recipientUsername, ciphertext: ciphertext)

        do {
            var request = URLRequest(url: baseURL.appendingPathComponent("messages"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.httpBody = try encoder.encode(payload)

            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure("Message server returned an invalid response.")
            }

            switch httpResponse.statusCode {
            case 201, 200:
                let response = try decoder.decode(SendMessageResponse.self, from: data)
                return .success(messageId: response.messageId, createdAt: response.createdAt)
            case 404:
                return .recipientNotFound
            default:
                return .failure("Message send failed with status \(httpResponse.statusCode).")
            }
        } catch {
            return .failure("Message send failed.")
        }
    }

    func history(token: String, withUsername username: String, since: String?) async -> [MessageRecord] {
        do {
            var components = URLComponents(
                url: baseURL.appendingPathComponent("messages"),
                resolvingAgainstBaseURL: false
            )
            var queryItems = [URLQueryItem(name: "with", value: username)]
            if let since {
                queryItems.append(URLQueryItem(name: "since", value: since))
            }
            components?.queryItems = queryItems

            guard let url = components?.url else {
                return []
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return []
            }
            return try decoder.decode([MessageRecord].self, from: data)
        } catch {
            return []
        }
    }
}
