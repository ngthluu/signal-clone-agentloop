import Foundation
import XCTest
@testable import ChatApp

final class HTTPAuthClientCaptureTests: XCTestCase {
    override func tearDown() {
        AuthCapturingURLProtocol.handler = nil
        super.tearDown()
    }

    func testRequestChallengeTransmitsExactlyUsernameAndMapsCreated() async throws {
        AuthCapturingURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/auth/challenge")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

            let body = try Self.bodyData(from: request)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(Set(object.keys), ["username"])
            XCTAssertEqual(object["username"] as? String, "alice")

            return Self.response(url: request.url, statusCode: 201, body: #"{"challenge_id":"challenge-1","nonce":"nonce"}"#)
        }

        let result = await client().requestChallenge(username: "alice")

        guard case .challenge(let challengeId, let nonceBase64) = result else {
            return XCTFail("Expected challenge, got \(result)")
        }
        XCTAssertEqual(challengeId, "challenge-1")
        XCTAssertEqual(nonceBase64, "nonce")
    }

    func testRequestChallengeMapsUnknownAccount() async {
        AuthCapturingURLProtocol.handler = { request in
            Self.response(url: request.url, statusCode: 404, body: #"{"error":"unknown account"}"#)
        }

        let result = await client().requestChallenge(username: "missing")

        guard case .unknownAccount = result else {
            return XCTFail("Expected unknownAccount, got \(result)")
        }
    }

    func testVerifyTransmitsExactlyChallengeIdAndSignatureAndMapsSuccess() async throws {
        AuthCapturingURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/auth/verify")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

            let body = try Self.bodyData(from: request)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(Set(object.keys), ["challenge_id", "signature"])
            XCTAssertEqual(object["challenge_id"] as? String, "challenge-1")
            XCTAssertEqual(object["signature"] as? String, "signature")

            return Self.response(url: request.url, statusCode: 200, body: #"{"token":"token","user_id":"user-1","username":"alice"}"#)
        }

        let result = await client().verify(challengeId: "challenge-1", signatureBase64: "signature")

        guard case .success(let token, let userId, let username) = result else {
            return XCTFail("Expected success, got \(result)")
        }
        XCTAssertEqual(token, "token")
        XCTAssertEqual(userId, "user-1")
        XCTAssertEqual(username, "alice")
    }

    func testVerifyMapsUnauthorizedToRejected() async {
        AuthCapturingURLProtocol.handler = { request in
            Self.response(url: request.url, statusCode: 401, body: #"{"error":"rejected"}"#)
        }

        let result = await client().verify(challengeId: "challenge-1", signatureBase64: "bad")

        guard case .rejected = result else {
            return XCTFail("Expected rejected, got \(result)")
        }
    }

    func testValidateSessionSendsBearerTokenAndMapsStatus() async {
        AuthCapturingURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/auth/session")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token")
            return Self.response(url: request.url, statusCode: 200, body: #"{"user_id":"user-1","username":"alice"}"#)
        }

        let validSession = await client().validateSession(token: "token")
        XCTAssertTrue(validSession)

        AuthCapturingURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token")
            return Self.response(url: request.url, statusCode: 401, body: #"{"error":"invalid"}"#)
        }

        let invalidSession = await client().validateSession(token: "token")
        XCTAssertFalse(invalidSession)
    }

    private func client() -> HTTPAuthClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthCapturingURLProtocol.self]
        return HTTPAuthClient(
            session: URLSession(configuration: configuration),
            baseURL: URL(string: "http://127.0.0.1:3000")!
        )
    }

    private static func response(url: URL?, statusCode: Int, body: String) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: url ?? URL(string: "http://127.0.0.1:3000")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
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

private final class AuthCapturingURLProtocol: URLProtocol {
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
