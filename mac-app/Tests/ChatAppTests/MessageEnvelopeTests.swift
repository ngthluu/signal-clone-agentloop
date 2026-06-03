import Foundation
import XCTest
@testable import ChatApp

final class MessageEnvelopeTests: XCTestCase {
    func testSendMessageRequestEncodesExactCiphertextKeys() throws {
        let payload = SendMessageRequest(recipientUsername: "bob", ciphertext: "opaque")
        let object = try encodedObject(payload)

        XCTAssertEqual(Set(object.keys), ["recipient_username", "ciphertext"])
        XCTAssertEqual(object["recipient_username"] as? String, "bob")
        XCTAssertEqual(object["ciphertext"] as? String, "opaque")
        assertNoPlaintextFields(in: payload)
    }

    func testPublishPrekeyRequestEncodesExactSnakeCaseKeys() throws {
        let payload = PublishPrekeyRequest(x25519PublicKey: "pub", keySignature: "sig")
        let object = try encodedObject(payload)

        XCTAssertEqual(Set(object.keys), ["x25519_public_key", "key_signature"])
        XCTAssertEqual(object["x25519_public_key"] as? String, "pub")
        XCTAssertEqual(object["key_signature"] as? String, "sig")
        assertNoPlaintextFields(in: payload)
    }

    func testPrekeyResponseDecodesSnakeCaseFields() throws {
        let response = try JSONDecoder().decode(
            PrekeyResponse.self,
            from: Data(#"{"user_id":"u1","username":"alice","identity_public_key":"id","x25519_public_key":"xpub","key_signature":"sig"}"#.utf8)
        )

        XCTAssertEqual(response.userId, "u1")
        XCTAssertEqual(response.username, "alice")
        XCTAssertEqual(response.identityPublicKey, "id")
        XCTAssertEqual(response.x25519PublicKey, "xpub")
        XCTAssertEqual(response.keySignature, "sig")
    }

    func testSendMessageResponseDecodesSnakeCaseFields() throws {
        let response = try JSONDecoder().decode(
            SendMessageResponse.self,
            from: Data(#"{"message_id":"m1","created_at":"2026-06-03T00:00:00Z"}"#.utf8)
        )

        XCTAssertEqual(response.messageId, "m1")
        XCTAssertEqual(response.createdAt, "2026-06-03T00:00:00Z")
    }

    func testMessageRecordDecodesSnakeCaseFields() throws {
        let record = try JSONDecoder().decode(
            MessageRecord.self,
            from: Data(#"{"id":"m1","sender_id":"u1","recipient_id":"u2","ciphertext":"opaque","created_at":"2026-06-03T00:00:00Z"}"#.utf8)
        )

        XCTAssertEqual(record.id, "m1")
        XCTAssertEqual(record.senderId, "u1")
        XCTAssertEqual(record.recipientId, "u2")
        XCTAssertEqual(record.ciphertext, "opaque")
        XCTAssertEqual(record.createdAt, "2026-06-03T00:00:00Z")
    }

    func testEncodedPayloadsContainNoPlaintextBodyOrTextFields() throws {
        let payloads: [any Encodable] = [
            PublishPrekeyRequest(x25519PublicKey: "pub", keySignature: "sig"),
            SendMessageRequest(recipientUsername: "bob", ciphertext: "opaque")
        ]

        for payload in payloads {
            let data = try JSONEncoder().encode(AnyEncodable(payload))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertFalse(object.keys.contains("plaintext"))
            XCTAssertFalse(object.keys.contains("body"))
            XCTAssertFalse(object.keys.contains("text"))
        }
    }

    private func encodedObject<T: Encodable>(_ payload: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(payload)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func assertNoPlaintextFields<T: Encodable>(in payload: T, file: StaticString = #filePath, line: UInt = #line) {
        do {
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: try JSONEncoder().encode(payload)) as? [String: Any])
            XCTAssertFalse(object.keys.contains("plaintext"), file: file, line: line)
            XCTAssertFalse(object.keys.contains("body"), file: file, line: line)
            XCTAssertFalse(object.keys.contains("text"), file: file, line: line)
        } catch {
            XCTFail("Encoding failed: \(error)", file: file, line: line)
        }
    }
}

private struct AnyEncodable: Encodable {
    private let encodeValue: (Encoder) throws -> Void

    init(_ value: any Encodable) {
        encodeValue = value.encode(to:)
    }

    func encode(to encoder: Encoder) throws {
        try encodeValue(encoder)
    }
}
