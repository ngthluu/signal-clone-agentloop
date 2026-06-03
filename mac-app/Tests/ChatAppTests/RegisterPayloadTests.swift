import Foundation
import XCTest
@testable import ChatApp

final class RegisterPayloadTests: XCTestCase {
    func testEncodesExactlyUsernameAndIdentityPublicKey() throws {
        let payload = RegisterPayload(username: "alice", identityPublicKey: "public-key")
        let data = try JSONEncoder().encode(payload)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(Set(object.keys), ["username", "identity_public_key"])
        XCTAssertEqual(object["username"] as? String, "alice")
        XCTAssertEqual(object["identity_public_key"] as? String, "public-key")

        let serialized = String(decoding: data, as: UTF8.self).lowercased()
        XCTAssertFalse(serialized.contains("private"))
        XCTAssertFalse(serialized.contains("secret"))
    }
}
