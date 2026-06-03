import Foundation

protocol GroupService: Sendable {
    func createGroup(token: String, name: String, members: [GroupMemberKeyDTO]) async -> CreateGroupResponse?
    func listGroups(token: String) async -> [GroupSummary]
    func fetchGroup(id: String, token: String) async -> GroupDetail?
    func addMember(groupId: String, token: String, username: String, epoch: UInt32, keys: [WrappedKeyDTO]) async -> AddMemberResponse?
    func fetchKeys(groupId: String, token: String) async -> [GroupKeyRecord]
    func sendGroupMessage(groupId: String, token: String, epoch: UInt32, ciphertext: String) async -> SendGroupMessageResult
    func groupHistory(groupId: String, token: String, since: String?) async -> [GroupMessageRecord]
}

enum SendGroupMessageResult: Equatable, Sendable {
    case success(messageId: String, createdAt: String, epoch: UInt32)
    case notMember
    case notFound
    case failure(String)
}

struct HTTPGroupService: GroupService {
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

    func createGroup(token: String, name: String, members: [GroupMemberKeyDTO]) async -> CreateGroupResponse? {
        let payload = CreateGroupRequest(name: name, members: members)
        return await post(pathComponents: ["groups"], token: token, payload: payload, expected: [200, 201])
    }

    func listGroups(token: String) async -> [GroupSummary] {
        await get(pathComponents: ["groups"], token: token) ?? []
    }

    func fetchGroup(id: String, token: String) async -> GroupDetail? {
        await get(pathComponents: ["groups", id], token: token)
    }

    func addMember(
        groupId: String,
        token: String,
        username: String,
        epoch: UInt32,
        keys: [WrappedKeyDTO]
    ) async -> AddMemberResponse? {
        let payload = AddMemberRequest(username: username, epoch: epoch, keys: keys)
        return await post(pathComponents: ["groups", groupId, "members"], token: token, payload: payload, expected: [200, 201])
    }

    func fetchKeys(groupId: String, token: String) async -> [GroupKeyRecord] {
        await get(pathComponents: ["groups", groupId, "keys"], token: token) ?? []
    }

    func sendGroupMessage(groupId: String, token: String, epoch: UInt32, ciphertext: String) async -> SendGroupMessageResult {
        let payload = SendGroupMessageRequest(epoch: epoch, ciphertext: ciphertext)

        do {
            var request = URLRequest(url: url(pathComponents: ["groups", groupId, "messages"]))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.httpBody = try encoder.encode(payload)

            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure("Group message server returned an invalid response.")
            }

            switch httpResponse.statusCode {
            case 200, 201:
                let response = try decoder.decode(SendGroupMessageResponse.self, from: data)
                return .success(messageId: response.messageId, createdAt: response.createdAt, epoch: response.epoch)
            case 403:
                return .notMember
            case 404:
                return .notFound
            default:
                return .failure("Group message send failed with status \(httpResponse.statusCode).")
            }
        } catch {
            return .failure("Group message send failed.")
        }
    }

    func groupHistory(groupId: String, token: String, since: String?) async -> [GroupMessageRecord] {
        var components = URLComponents(
            url: url(pathComponents: ["groups", groupId, "messages"]),
            resolvingAgainstBaseURL: false
        )
        if let since {
            components?.queryItems = [URLQueryItem(name: "since", value: since)]
        }
        guard let url = components?.url else {
            return []
        }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return []
            }
            return try decoder.decode(GroupHistoryResponse.self, from: data).messages
        } catch {
            return []
        }
    }

    private func get<T: Decodable>(pathComponents: [String], token: String) async -> T? {
        do {
            var request = URLRequest(url: url(pathComponents: pathComponents))
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            return try decoder.decode(T.self, from: data)
        } catch {
            return nil
        }
    }

    private func post<T: Encodable, U: Decodable>(
        pathComponents: [String],
        token: String,
        payload: T,
        expected statusCodes: Set<Int>
    ) async -> U? {
        do {
            var request = URLRequest(url: url(pathComponents: pathComponents))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.httpBody = try encoder.encode(payload)

            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, statusCodes.contains(httpResponse.statusCode) else {
                return nil
            }
            return try decoder.decode(U.self, from: data)
        } catch {
            return nil
        }
    }

    private func url(pathComponents: [String]) -> URL {
        pathComponents.reduce(baseURL) { partial, component in
            partial.appendingPathComponent(component)
        }
    }
}
