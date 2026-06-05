import Foundation
import XCTest
@testable import ChatApp

final class HTTPAttachmentServiceTests: XCTestCase {
    override func tearDown() {
        AttachmentCapturingURLProtocol.handler = nil
        super.tearDown()
    }

    func testUploadPostsOctetStreamBlobWithBearerTokenAndParsesAttachmentId() async throws {
        let filenameSentinel = "DM_ATTACHMENT_FILENAME_SENTINEL_wire.bin"
        let contentSentinel = "DM_ATTACHMENT_CONTENT_SENTINEL_wire_payload"
        let blob = Data([0x00, 0x01, 0xFE, 0xFF, 0x42])

        AttachmentCapturingURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/attachments")
            XCTAssertFalse(request.url?.absoluteString.contains(filenameSentinel) ?? true)
            XCTAssertFalse(request.url?.absoluteString.contains(contentSentinel) ?? true)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/octet-stream")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-1")
            let body = try Self.bodyData(from: request)
            XCTAssertEqual(body, blob)
            XCTAssertNil(body.range(of: Data(filenameSentinel.utf8)))
            XCTAssertNil(body.range(of: Data(contentSentinel.utf8)))
            if let headers = request.allHTTPHeaderFields {
                for value in headers.values {
                    XCTAssertFalse(value.contains(filenameSentinel))
                    XCTAssertFalse(value.contains(contentSentinel))
                }
            }

            return Self.response(
                url: request.url,
                statusCode: 201,
                body: #"{"attachment_id":"att-1"}"#
            )
        }

        let attachmentId = await client().upload(token: "token-1", encryptedBlob: blob)

        XCTAssertEqual(attachmentId, "att-1")
    }

    func testUploadReturnsNilForNonSuccessStatusAndMalformedResponse() async {
        AttachmentCapturingURLProtocol.handler = { request in
            Self.response(url: request.url, statusCode: 413, body: #"{"error":"too large"}"#)
        }

        let rejected = await client().upload(token: "token-1", encryptedBlob: Data([0x01]))
        XCTAssertNil(rejected)

        AttachmentCapturingURLProtocol.handler = { request in
            Self.response(url: request.url, statusCode: 201, body: #"{"id":"wrong-field"}"#)
        }

        let malformed = await client().upload(token: "token-1", encryptedBlob: Data([0x02]))
        XCTAssertNil(malformed)
    }

    func testDownloadGetsAttachmentWithBearerTokenAndReturnsRawBytesOn200() async {
        let blob = Data([0x10, 0x20, 0x30, 0xFF])

        AttachmentCapturingURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/attachments/att-1")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-1")
            return Self.response(url: request.url, statusCode: 200, contentType: "application/octet-stream", body: blob)
        }

        let downloaded = await client().download(token: "token-1", attachmentId: "att-1")

        XCTAssertEqual(downloaded, blob)
    }

    func testDownloadReturnsNilFor404AndOtherErrors() async {
        AttachmentCapturingURLProtocol.handler = { request in
            Self.response(url: request.url, statusCode: 404, body: #"{"error":"missing"}"#)
        }

        let missing = await client().download(token: "token-1", attachmentId: "missing")
        XCTAssertNil(missing)

        AttachmentCapturingURLProtocol.handler = { _ in
            throw URLError(.badServerResponse)
        }

        let failed = await client().download(token: "token-1", attachmentId: "att-1")
        XCTAssertNil(failed)
    }

    private func client() -> HTTPAttachmentService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AttachmentCapturingURLProtocol.self]
        return HTTPAttachmentService(
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
        response(url: url, statusCode: statusCode, contentType: contentType, body: Data(body.utf8))
    }

    private static func response(
        url: URL?,
        statusCode: Int,
        contentType: String = "application/json",
        body: Data
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: url ?? URL(string: "http://127.0.0.1:3000")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": contentType]
        )!
        return (response, body)
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

private final class AttachmentCapturingURLProtocol: URLProtocol {
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
