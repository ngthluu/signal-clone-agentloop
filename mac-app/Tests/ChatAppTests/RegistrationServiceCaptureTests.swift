import Foundation
import XCTest
@testable import ChatApp

final class RegistrationServiceCaptureTests: XCTestCase {
    override func tearDown() {
        CapturingURLProtocol.handler = nil
        super.tearDown()
    }

    func testHTTPClientTransmitsExactlyTwoFieldRegisterPayload() async throws {
        CapturingURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/register")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

            let body = try Self.bodyData(from: request)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(Set(object.keys), ["username", "identity_public_key"])
            XCTAssertEqual(object["username"] as? String, "alice")
            XCTAssertEqual(object["identity_public_key"] as? String, "public-key")

            let serialized = String(decoding: body, as: UTF8.self).lowercased()
            XCTAssertFalse(serialized.contains("private"))
            XCTAssertFalse(serialized.contains("secret"))

            return Self.response(statusCode: 201, body: #"{"user_id":"user-123"}"#)
        }

        let result = await client().register(username: "alice", publicKeyBase64: "public-key")

        guard case .success(let userId) = result else {
            return XCTFail("Expected success, got \(result)")
        }
        XCTAssertEqual(userId, "user-123")
    }

    func testHTTPClientMapsConflictToUsernameTaken() async {
        CapturingURLProtocol.handler = { _ in
            Self.response(statusCode: 409, body: #"{"error":"username taken"}"#)
        }

        let result = await client().register(username: "alice", publicKeyBase64: "public-key")

        guard case .usernameTaken = result else {
            return XCTFail("Expected usernameTaken, got \(result)")
        }
    }

    func testHTTPClientMapsBadRequestToInvalid() async {
        CapturingURLProtocol.handler = { _ in
            Self.response(statusCode: 400, body: #"{"error":"invalid username"}"#)
        }

        let result = await client().register(username: "bad name", publicKeyBase64: "public-key")

        guard case .invalid = result else {
            return XCTFail("Expected invalid, got \(result)")
        }
    }

    private func client() -> HTTPRegistrationClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CapturingURLProtocol.self]
        return HTTPRegistrationClient(
            session: URLSession(configuration: configuration),
            baseURL: URL(string: "http://127.0.0.1:3000")!
        )
    }

    private static func response(statusCode: Int, body: String) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: URL(string: "http://127.0.0.1:3000/register")!,
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

private final class CapturingURLProtocol: URLProtocol {
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
