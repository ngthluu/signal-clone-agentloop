import Foundation
import XCTest
@testable import ChatApp

final class HTTPConversationsServiceTests: XCTestCase {
    override func tearDown() {
        ConversationsCapturingURLProtocol.handler = nil
        super.tearDown()
    }

    func testConversationsGetsBearerTokenAndDecodesSummaries() async {
        ConversationsCapturingURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/conversations")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-1")
            return Self.response(
                url: request.url,
                statusCode: 200,
                body: """
                {"conversations":[{"peer_user_id":"peer-a","peer_username":"alice","last_activity":"2026-06-03T00:00:01Z","last_seq":7},{"peer_user_id":"peer-b","peer_username":"bob","last_activity":"2026-06-03T00:00:02Z","last_seq":8}]}
                """
            )
        }

        let records = await client().conversations(token: "token-1")

        XCTAssertEqual(records, [
            ConversationSummary(
                peerUserId: "peer-a",
                peerUsername: "alice",
                lastActivity: "2026-06-03T00:00:01Z",
                lastSeq: 7
            ),
            ConversationSummary(
                peerUserId: "peer-b",
                peerUsername: "bob",
                lastActivity: "2026-06-03T00:00:02Z",
                lastSeq: 8
            )
        ])
    }

    func testConversationsGetsBearerTokenAndDecodesResponse() async {
        await assertConversationsDecodesTaskFourSummaryShape()
    }

    func testConversationsDecodesBackendConversationRecordShape() async {
        ConversationsCapturingURLProtocol.handler = { request in
            Self.response(
                url: request.url,
                statusCode: 200,
                body: """
                {"conversations":[{"peer_id":"peer-a","peer_username":"alice","last_message_id":"msg-a","last_ciphertext":"cipher-a","last_created_at":"2026-06-03T00:00:01Z"},{"peer_id":"peer-b","peer_username":"bob","last_message_id":"msg-b","last_ciphertext":"cipher-b","last_created_at":"2026-06-03T00:00:02Z"}]}
                """
            )
        }

        let records = await client().conversations(token: "token-1")

        XCTAssertEqual(records, [
            ConversationSummary(
                peerId: "peer-a",
                peerUsername: "alice",
                lastActivityAt: "2026-06-03T00:00:01Z",
                lastMessageId: "msg-a"
            ),
            ConversationSummary(
                peerId: "peer-b",
                peerUsername: "bob",
                lastActivityAt: "2026-06-03T00:00:02Z",
                lastMessageId: "msg-b"
            )
        ])
    }

    func testConversationsMapsNon200ToEmptyArray() async {
        ConversationsCapturingURLProtocol.handler = { request in
            Self.response(url: request.url, statusCode: 500, body: #"{"error":"server"}"#)
        }

        let records = await client().conversations(token: "token-1")

        XCTAssertEqual(records, [])
    }

    private func client() -> HTTPMessageService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ConversationsCapturingURLProtocol.self]
        return HTTPMessageService(
            session: URLSession(configuration: configuration),
            baseURL: URL(string: "http://127.0.0.1:3000")!
        )
    }

    private func assertConversationsDecodesTaskFourSummaryShape() async {
        ConversationsCapturingURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/conversations")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-1")
            return Self.response(
                url: request.url,
                statusCode: 200,
                body: """
                {"conversations":[{"peer_user_id":"peer-a","peer_username":"alice","last_activity":"2026-06-03T00:00:01Z","last_seq":7},{"peer_user_id":"peer-b","peer_username":"bob","last_activity":"2026-06-03T00:00:02Z","last_seq":8}]}
                """
            )
        }

        let records = await client().conversations(token: "token-1")

        XCTAssertEqual(records, [
            ConversationSummary(
                peerUserId: "peer-a",
                peerUsername: "alice",
                lastActivity: "2026-06-03T00:00:01Z",
                lastSeq: 7
            ),
            ConversationSummary(
                peerUserId: "peer-b",
                peerUsername: "bob",
                lastActivity: "2026-06-03T00:00:02Z",
                lastSeq: 8
            )
        ])
    }

    private static func response(
        url: URL?,
        statusCode: Int,
        body: String
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: url ?? URL(string: "http://127.0.0.1:3000")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data(body.utf8))
    }
}

private final class ConversationsCapturingURLProtocol: URLProtocol {
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
