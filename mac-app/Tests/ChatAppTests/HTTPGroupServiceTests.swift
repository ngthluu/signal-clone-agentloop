import Foundation
import XCTest
@testable import ChatApp

final class HTTPGroupServiceTests: XCTestCase {
    override func tearDown() {
        GroupCapturingURLProtocol.handler = nil
        super.tearDown()
    }

    func testCreateGroupPostsMembersWithBearerTokenAndDecodesResponse() async throws {
        GroupCapturingURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/groups")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-1")

            let object = try Self.jsonObject(from: request)
            XCTAssertEqual(Set(object.keys), ["name", "members"])
            XCTAssertEqual(object["name"] as? String, "Ops")
            let members = try XCTUnwrap(object["members"] as? [[String: Any]])
            XCTAssertEqual(members.count, 3)
            for member in members {
                XCTAssertEqual(Set(member.keys), ["username", "wrapped_key"])
            }
            XCTAssertEqual(members[0]["username"] as? String, "alice")
            XCTAssertEqual(members[0]["wrapped_key"] as? String, "wrap-a")
            XCTAssertEqual(members[1]["username"] as? String, "bob")
            XCTAssertEqual(members[1]["wrapped_key"] as? String, "wrap-b")
            XCTAssertEqual(members[2]["username"] as? String, "carol")
            XCTAssertEqual(members[2]["wrapped_key"] as? String, "wrap-c")

            return Self.response(
                url: request.url,
                statusCode: 201,
                body: #"{"group_id":"group-1","epoch":0,"members":[{"user_id":"user-a","username":"alice"},{"user_id":"user-b","username":"bob"},{"user_id":"user-c","username":"carol"}]}"#
            )
        }

        let response = await client().createGroup(
            token: "token-1",
            name: "Ops",
            members: [
                GroupMemberKeyDTO(username: "alice", wrappedKey: "wrap-a"),
                GroupMemberKeyDTO(username: "bob", wrappedKey: "wrap-b"),
                GroupMemberKeyDTO(username: "carol", wrappedKey: "wrap-c")
            ]
        )

        XCTAssertEqual(response?.groupId, "group-1")
        XCTAssertEqual(response?.epoch, 0)
        XCTAssertEqual(response?.members.map(\.username), ["alice", "bob", "carol"])
    }

    func testAddMemberPostsEpochKeysAndDecodesResponse() async throws {
        GroupCapturingURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/groups/group-1/members")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-1")

            let object = try Self.jsonObject(from: request)
            XCTAssertEqual(Set(object.keys), ["username", "epoch", "keys"])
            XCTAssertEqual(object["username"] as? String, "carol")
            XCTAssertEqual(object["epoch"] as? Int, 1)
            let keys = try XCTUnwrap(object["keys"] as? [[String: Any]])
            XCTAssertEqual(keys[0]["member_id"] as? String, "user-a")
            XCTAssertEqual(keys[0]["wrapped_key"] as? String, "wrap-a1")

            return Self.response(
                url: request.url,
                statusCode: 201,
                body: #"{"epoch":1,"member":{"user_id":"user-c","username":"carol"}}"#
            )
        }

        let response = await client().addMember(
            groupId: "group-1",
            token: "token-1",
            username: "carol",
            epoch: 1,
            keys: [WrappedKeyDTO(memberId: "user-a", wrappedKey: "wrap-a1")]
        )

        XCTAssertEqual(response, AddMemberResponse(epoch: 1, member: GroupMemberRefDTO(userId: "user-c", username: "carol")))
    }

    func testSendGroupMessagePostsCiphertextOnlyAndMapsStatuses() async throws {
        GroupCapturingURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/groups/group-1/messages")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-1")

            let object = try Self.jsonObject(from: request)
            XCTAssertEqual(Set(object.keys), ["epoch", "ciphertext"])
            XCTAssertEqual(object["epoch"] as? Int, 2)
            XCTAssertEqual(object["ciphertext"] as? String, "ciphertext-1")

            return Self.response(
                url: request.url,
                statusCode: 201,
                body: #"{"message_id":"msg-1","created_at":"2026-06-03T00:00:00Z","epoch":2}"#
            )
        }

        let success = await client().sendGroupMessage(groupId: "group-1", token: "token-1", epoch: 2, ciphertext: "ciphertext-1")
        XCTAssertEqual(success, .success(messageId: "msg-1", createdAt: "2026-06-03T00:00:00Z", epoch: 2))

        GroupCapturingURLProtocol.handler = { request in
            Self.response(url: request.url, statusCode: 403, body: #"{"error":"forbidden"}"#)
        }
        let notMember = await client().sendGroupMessage(groupId: "group-1", token: "token-1", epoch: 2, ciphertext: "ct")
        XCTAssertEqual(notMember, .notMember)

        GroupCapturingURLProtocol.handler = { request in
            Self.response(url: request.url, statusCode: 404, body: #"{"error":"missing"}"#)
        }
        let notFound = await client().sendGroupMessage(groupId: "group-1", token: "token-1", epoch: 2, ciphertext: "ct")
        XCTAssertEqual(notFound, .notFound)

        GroupCapturingURLProtocol.handler = { request in
            Self.response(url: request.url, statusCode: 409, body: #"{"error":"stale epoch"}"#)
        }
        let staleEpoch = await client().sendGroupMessage(groupId: "group-1", token: "token-1", epoch: 0, ciphertext: "ct")
        XCTAssertEqual(staleEpoch, .staleEpoch)

        GroupCapturingURLProtocol.handler = { request in
            Self.response(url: request.url, statusCode: 500, body: #"{"error":"server"}"#)
        }
        guard case .failure = await client().sendGroupMessage(groupId: "group-1", token: "token-1", epoch: 2, ciphertext: "ct") else {
            return XCTFail("Expected failure for 500")
        }
    }

    func testGetEndpointsDecodeGroupPayloads() async throws {
        GroupCapturingURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-1")
            switch request.url?.path {
            case "/groups":
                return Self.response(
                    url: request.url,
                    statusCode: 200,
                    body: #"[{"id":"group-1","name":"Ops","creator_id":"user-a","current_epoch":0,"joined_epoch":0,"created_at":"2026-06-03T00:00:00Z"}]"#
                )
            case "/groups/group-1":
                return Self.response(
                    url: request.url,
                    statusCode: 200,
                    body: #"{"id":"group-1","name":"Ops","creator_id":"user-a","current_epoch":1,"created_at":"2026-06-03T00:00:00Z","members":[{"user_id":"user-a","username":"alice","joined_epoch":0}]}"#
                )
            case "/groups/group-1/keys":
                return Self.response(url: request.url, statusCode: 200, body: #"[{"epoch":1,"wrapped_key":"wrap-1"}]"#)
            case "/groups/group-1/messages":
                XCTAssertEqual(request.url?.query, "since=cursor-1")
                return Self.response(
                    url: request.url,
                    statusCode: 200,
                    body: #"{"messages":[{"id":"msg-1","group_id":"group-1","sender_id":"user-a","epoch":1,"ciphertext":"ct","created_at":"2026-06-03T00:00:00Z"}]}"#
                )
            default:
                return Self.response(url: request.url, statusCode: 404, body: #"{}"#)
            }
        }

        let groups = await client().listGroups(token: "token-1")
        XCTAssertEqual(groups.map(\.id), ["group-1"])
        let detail = await client().fetchGroup(id: "group-1", token: "token-1")
        XCTAssertEqual(detail?.members.first?.username, "alice")
        let keys = await client().fetchKeys(groupId: "group-1", token: "token-1")
        XCTAssertEqual(keys, [GroupKeyRecord(epoch: 1, wrappedKey: "wrap-1")])
        let history = await client().groupHistory(groupId: "group-1", token: "token-1", since: "cursor-1")
        XCTAssertEqual(history.map(\.id), ["msg-1"])
    }

    func testParseGroupSSEEventDecodesDataLineAndIgnoresOtherLines() throws {
        let line = #"data: {"id":"msg-live","group_id":"group-1","sender_id":"user-b","epoch":1,"ciphertext":"ct-live","created_at":"2026-06-03T00:01:00Z"}"#

        let record = try XCTUnwrap(parseGroupSSEEvent(line))

        XCTAssertEqual(record, GroupMessageRecord(
            id: "msg-live",
            groupId: "group-1",
            senderId: "user-b",
            epoch: 1,
            ciphertext: "ct-live",
            createdAt: "2026-06-03T00:01:00Z"
        ))
        XCTAssertNil(parseGroupSSEEvent(": keep-alive"))
        XCTAssertNil(parseGroupSSEEvent("event: message"))
    }

    func testLiveGroupMessagesYieldsSSERecordsAndCompletes() async throws {
        GroupCapturingURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/groups/group-1/stream")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-1")
            return Self.response(
                url: request.url,
                statusCode: 200,
                contentType: "text/event-stream",
                body: #"data: {"id":"msg-live","group_id":"group-1","sender_id":"user-b","epoch":1,"ciphertext":"ct-live","created_at":"2026-06-03T00:01:00Z"}"#
                    + "\n\n"
            )
        }

        let service = client()
        let records = try await withThrowingTaskGroup(of: [GroupMessageRecord].self) { group in
            group.addTask {
                var records: [GroupMessageRecord] = []
                for try await record in service.liveGroupMessages(groupId: "group-1", token: "token-1") {
                    records.append(record)
                }
                return records
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                throw URLError(.timedOut)
            }
            let value = try await group.next()!
            group.cancelAll()
            return value
        }

        XCTAssertEqual(records, [
            GroupMessageRecord(
                id: "msg-live",
                groupId: "group-1",
                senderId: "user-b",
                epoch: 1,
                ciphertext: "ct-live",
                createdAt: "2026-06-03T00:01:00Z"
            )
        ])
    }

    func testLiveGroupMessagesSurfacesEpochEventsThroughHookWithoutYieldingRecord() async throws {
        GroupCapturingURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/groups/group-1/stream")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-1")
            return Self.response(
                url: request.url,
                statusCode: 200,
                contentType: "text/event-stream",
                body: #"event: epoch"#
                    + "\n"
                    + #"data: {"group_id":"group-1","epoch":2}"#
                    + "\n\n"
            )
        }

        let service = client()
        let epochEvents = EpochEventCollector()
        let records = try await withThrowingTaskGroup(of: [GroupMessageRecord].self) { group in
            group.addTask {
                var records: [GroupMessageRecord] = []
                for try await record in service.liveGroupMessages(
                    groupId: "group-1",
                    token: "token-1",
                    onEpochChange: { event in
                        epochEvents.append(event)
                    }
                ) {
                    records.append(record)
                }
                return records
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                throw URLError(.timedOut)
            }
            let value = try await group.next()!
            group.cancelAll()
            return value
        }

        XCTAssertEqual(records, [])
        let events = epochEvents.events
        XCTAssertEqual(events, [GroupEpochEvent(groupId: "group-1", epoch: 2)])
    }

    private func client() -> HTTPGroupService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GroupCapturingURLProtocol.self]
        return HTTPGroupService(
            session: URLSession(configuration: configuration),
            baseURL: URL(string: "http://127.0.0.1:3000")!
        )
    }

    private static func jsonObject(from request: URLRequest) throws -> [String: Any] {
        let body = try bodyData(from: request)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    private static func response(
        url: URL?,
        statusCode: Int,
        contentType: String = "application/json",
        body: String
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: url ?? URL(string: "http://127.0.0.1:3000")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": contentType]
        )!
        return (response, Data(body.utf8))
    }

    private static func bodyData(from request: URLRequest) throws -> Data {
        if let httpBody = request.httpBody {
            return httpBody
        }

        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 1_024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            if count < 0 {
                throw stream.streamError ?? URLError(.cannotDecodeContentData)
            }
            if count == 0 {
                break
            }
            data.append(buffer, count: count)
        }

        return data
    }
}

private final class GroupCapturingURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class EpochEventCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storedEvents: [GroupEpochEvent] = []

    var events: [GroupEpochEvent] {
        lock.withLock {
            storedEvents
        }
    }

    func append(_ event: GroupEpochEvent) {
        lock.withLock {
            storedEvents.append(event)
        }
    }
}
