import Foundation
import XCTest
@testable import ChatApp

final class HTTPMessageServiceTests: XCTestCase {
    override func tearDown() {
        MessageCapturingURLProtocol.handler = nil
        super.tearDown()
    }

    func testSendPostsCiphertextOnlyWithBearerToken() async throws {
        MessageCapturingURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/messages")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-1")

            let body = try Self.bodyData(from: request)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(Set(object.keys), ["recipient_username", "ciphertext"])
            XCTAssertEqual(object["recipient_username"] as? String, "bob")
            XCTAssertEqual(object["ciphertext"] as? String, "ciphertext-1")

            return Self.response(url: request.url, statusCode: 201, body: #"{"message_id":"msg-1","created_at":"2026-06-03T00:00:00Z"}"#)
        }

        let result = await client().send(token: "token-1", recipientUsername: "bob", ciphertext: "ciphertext-1")

        guard case let .success(messageId, createdAt) = result else {
            return XCTFail("Expected success, got \(result)")
        }
        XCTAssertEqual(messageId, "msg-1")
        XCTAssertEqual(createdAt, "2026-06-03T00:00:00Z")
    }

    func testSendMapsRecipientNotFoundAndFailure() async {
        MessageCapturingURLProtocol.handler = { request in
            Self.response(url: request.url, statusCode: 404, body: #"{"error":"missing"}"#)
        }

        let missing = await client().send(token: "token-1", recipientUsername: "missing", ciphertext: "ct")
        guard case .recipientNotFound = missing else {
            return XCTFail("Expected recipientNotFound, got \(missing)")
        }

        MessageCapturingURLProtocol.handler = { request in
            Self.response(url: request.url, statusCode: 500, body: #"{"error":"server"}"#)
        }

        let failure = await client().send(token: "token-1", recipientUsername: "bob", ciphertext: "ct")
        guard case .failure = failure else {
            return XCTFail("Expected failure, got \(failure)")
        }
    }

    func testPublishPrekeyPutsSignedPrekeyWithBearerToken() async throws {
        MessageCapturingURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.url?.path, "/keys")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-1")

            let body = try Self.bodyData(from: request)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(Set(object.keys), ["x25519_public_key", "key_signature"])
            XCTAssertEqual(object["x25519_public_key"] as? String, "xpub")
            XCTAssertEqual(object["key_signature"] as? String, "sig")

            return Self.response(url: request.url, statusCode: 200, body: #"{}"#)
        }

        let published = await client().publishPrekey(token: "token-1", x25519PublicKey: "xpub", signature: "sig")
        XCTAssertTrue(published)
    }

    func testFetchPrekeyDecodesResponseAndMaps404ToNil() async throws {
        MessageCapturingURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/keys/bob")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-1")
            return Self.response(
                url: request.url,
                statusCode: 200,
                body: #"{"user_id":"user-b","username":"bob","identity_public_key":"id-pub","x25519_public_key":"xpub","key_signature":"sig"}"#
            )
        }

        let fetchedPrekey = await client().fetchPrekey(username: "bob", token: "token-1")
        let prekey = try XCTUnwrap(fetchedPrekey)
        XCTAssertEqual(prekey.userId, "user-b")
        XCTAssertEqual(prekey.username, "bob")
        XCTAssertEqual(prekey.identityPublicKey, "id-pub")
        XCTAssertEqual(prekey.x25519PublicKey, "xpub")
        XCTAssertEqual(prekey.keySignature, "sig")

        MessageCapturingURLProtocol.handler = { request in
            Self.response(url: request.url, statusCode: 404, body: #"{"error":"missing"}"#)
        }

        let missingPrekey = await client().fetchPrekey(username: "missing", token: "token-1")
        XCTAssertNil(missingPrekey)
    }

    func testHistoryDecodesMessageRecords() async throws {
        MessageCapturingURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/messages")
            XCTAssertEqual(request.url?.query, "with=bob&since=cursor-1")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-1")
            return Self.response(
                url: request.url,
                statusCode: 200,
                body: #"[{"id":"msg-1","sender_id":"user-a","recipient_id":"user-b","ciphertext":"ct","created_at":"2026-06-03T00:00:00Z"}]"#
            )
        }

        let records = await client().history(token: "token-1", withUsername: "bob", since: "cursor-1")

        XCTAssertEqual(records, [
            MessageRecord(
                id: "msg-1",
                senderId: "user-a",
                recipientId: "user-b",
                ciphertext: "ct",
                createdAt: "2026-06-03T00:00:00Z"
            )
        ])
    }

    func testParseSSEEventDecodesDataLineAndIgnoresOtherLines() throws {
        let line = #"data: {"id":"msg-1","sender_id":"user-a","recipient_id":"user-b","ciphertext":"ct","created_at":"2026-06-03T00:00:00Z"}"#

        let record = try XCTUnwrap(parseSSEEvent(line))

        XCTAssertEqual(record.id, "msg-1")
        XCTAssertEqual(record.senderId, "user-a")
        XCTAssertEqual(record.recipientId, "user-b")
        XCTAssertEqual(record.ciphertext, "ct")
        XCTAssertEqual(record.createdAt, "2026-06-03T00:00:00Z")
        XCTAssertNil(parseSSEEvent(": keep-alive"))
        XCTAssertNil(parseSSEEvent("event: message"))
    }

    func testLiveMessagesYieldsSSERecordsAndCompletes() async throws {
        MessageCapturingURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/messages/stream")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-1")
            return Self.response(
                url: request.url,
                statusCode: 200,
                contentType: "text/event-stream",
                body: #"data: {"id":"msg-live","sender_id":"user-a","recipient_id":"user-b","ciphertext":"ct-live","created_at":"2026-06-03T00:00:00Z"}"#
                    + "\n\n"
            )
        }

        let service = client()
        let records = try await withThrowingTaskGroup(of: [MessageRecord].self) { group in
            group.addTask {
                var records: [MessageRecord] = []
                for try await record in service.liveMessages(token: "token-1") {
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
            MessageRecord(
            id: "msg-live",
            senderId: "user-a",
            recipientId: "user-b",
            ciphertext: "ct-live",
            createdAt: "2026-06-03T00:00:00Z"
            )
        ])
    }

    private func client() -> HTTPMessageService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MessageCapturingURLProtocol.self]
        return HTTPMessageService(
            session: URLSession(configuration: configuration),
            baseURL: URL(string: "http://127.0.0.1:3000")!
        )
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

private final class MessageCapturingURLProtocol: URLProtocol {
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
