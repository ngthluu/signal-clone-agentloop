import Foundation
import XCTest
@testable import ChatApp

final class AuthPayloadsTests: XCTestCase {
    func testChallengeRequestEncodesExactlyUsername() throws {
        let payload = ChallengeRequest(username: "alice")
        let object = try encodedObject(payload)

        XCTAssertEqual(Set(object.keys), ["username"])
        XCTAssertEqual(object["username"] as? String, "alice")
        assertNoPrivateOrSecretFields(in: payload)
    }

    func testVerifyRequestEncodesExactlyChallengeIdAndSignature() throws {
        let payload = VerifyRequest(challengeId: "challenge-1", signature: "signature")
        let object = try encodedObject(payload)

        XCTAssertEqual(Set(object.keys), ["challenge_id", "signature"])
        XCTAssertEqual(object["challenge_id"] as? String, "challenge-1")
        XCTAssertEqual(object["signature"] as? String, "signature")
        assertNoPrivateOrSecretFields(in: payload)
    }

    func testResponsesDecodeSnakeCaseFields() throws {
        let challenge = try JSONDecoder().decode(
            ChallengeResponse.self,
            from: Data(#"{"challenge_id":"challenge-1","nonce":"nonce"}"#.utf8)
        )
        XCTAssertEqual(challenge.challengeId, "challenge-1")
        XCTAssertEqual(challenge.nonce, "nonce")

        let verify = try JSONDecoder().decode(
            VerifyResponse.self,
            from: Data(#"{"token":"token","user_id":"user-1","username":"alice"}"#.utf8)
        )
        XCTAssertEqual(verify.token, "token")
        XCTAssertEqual(verify.userId, "user-1")
        XCTAssertEqual(verify.username, "alice")

        let session = try JSONDecoder().decode(
            SessionResponse.self,
            from: Data(#"{"user_id":"user-1","username":"alice"}"#.utf8)
        )
        XCTAssertEqual(session.userId, "user-1")
        XCTAssertEqual(session.username, "alice")
    }

    private func encodedObject<T: Encodable>(_ payload: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(payload)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func assertNoPrivateOrSecretFields<T: Encodable>(in payload: T, file: StaticString = #filePath, line: UInt = #line) {
        do {
            let serialized = String(decoding: try JSONEncoder().encode(payload), as: UTF8.self).lowercased()
            XCTAssertFalse(serialized.contains("private"), file: file, line: line)
            XCTAssertFalse(serialized.contains("secret"), file: file, line: line)
        } catch {
            XCTFail("Encoding failed: \(error)", file: file, line: line)
        }
    }
}
