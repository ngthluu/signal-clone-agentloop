import Foundation
import XCTest
@testable import ChatApp

final class GroupEnvelopeTests: XCTestCase {
    func testCreateGroupRequestEncodesSnakeCaseKeys() throws {
        let payload = CreateGroupRequest(
            name: "team",
            members: [
                GroupMemberKeyDTO(username: "alice", wrappedKey: "wrapped-a"),
                GroupMemberKeyDTO(username: "bob", wrappedKey: "wrapped-b"),
                GroupMemberKeyDTO(username: "carol", wrappedKey: "wrapped-c")
            ]
        )
        let object = try encodedObject(payload)
        let members = try XCTUnwrap(object["members"] as? [[String: Any]])

        XCTAssertEqual(Set(object.keys), ["name", "members"])
        XCTAssertEqual(object["name"] as? String, "team")
        XCTAssertEqual(members.count, 3)
        for member in members {
            XCTAssertEqual(Set(member.keys), ["username", "wrapped_key"])
        }
        XCTAssertEqual(members.map { $0["username"] as? String }, ["alice", "bob", "carol"])
        XCTAssertEqual(members.map { $0["wrapped_key"] as? String }, ["wrapped-a", "wrapped-b", "wrapped-c"])
        assertNoPlaintextFields(in: payload)
    }

    func testCreateGroupResponseDecodesSnakeCaseFields() throws {
        let response = try JSONDecoder().decode(
            CreateGroupResponse.self,
            from: Data(#"{"group_id":"g1","epoch":0,"members":[{"user_id":"u1","username":"alice"}]}"#.utf8)
        )

        XCTAssertEqual(response.groupId, "g1")
        XCTAssertEqual(response.epoch, 0)
        XCTAssertEqual(response.members, [GroupMemberRefDTO(userId: "u1", username: "alice")])
    }

    func testGroupSummaryAndDetailDecodeSnakeCaseFields() throws {
        let summary = try JSONDecoder().decode(
            GroupSummary.self,
            from: Data(#"{"id":"g1","name":"team","creator_id":"u1","current_epoch":3,"joined_epoch":1,"created_at":"2026-06-03T00:00:00Z"}"#.utf8)
        )
        let detail = try JSONDecoder().decode(
            GroupDetail.self,
            from: Data(#"{"id":"g1","name":"team","creator_id":"u1","current_epoch":3,"created_at":"2026-06-03T00:00:00Z","members":[{"user_id":"u1","username":"alice","joined_epoch":0}]}"#.utf8)
        )

        XCTAssertEqual(summary.creatorId, "u1")
        XCTAssertEqual(summary.currentEpoch, 3)
        XCTAssertEqual(summary.joinedEpoch, 1)
        XCTAssertEqual(summary.createdAt, "2026-06-03T00:00:00Z")
        XCTAssertEqual(detail.creatorId, "u1")
        XCTAssertEqual(detail.currentEpoch, 3)
        XCTAssertEqual(detail.members, [GroupMemberDTO(userId: "u1", username: "alice", joinedEpoch: 0)])
    }

    func testAddMemberRequestAndResponseUseSnakeCaseKeys() throws {
        let request = AddMemberRequest(
            username: "carol",
            epoch: 2,
            keys: [WrappedKeyDTO(memberId: "u3", wrappedKey: "wrapped")]
        )
        let object = try encodedObject(request)
        let keys = try XCTUnwrap(object["keys"] as? [[String: Any]])
        let response = try JSONDecoder().decode(
            AddMemberResponse.self,
            from: Data(#"{"epoch":2,"member":{"user_id":"u3","username":"carol"}}"#.utf8)
        )

        XCTAssertEqual(Set(object.keys), ["username", "epoch", "keys"])
        XCTAssertEqual(Set(keys[0].keys), ["member_id", "wrapped_key"])
        XCTAssertEqual(keys[0]["member_id"] as? String, "u3")
        XCTAssertEqual(keys[0]["wrapped_key"] as? String, "wrapped")
        XCTAssertEqual(response.epoch, 2)
        XCTAssertEqual(response.member, GroupMemberRefDTO(userId: "u3", username: "carol"))
        assertNoPlaintextFields(in: request)
    }

    func testKeyRecordAndMessageResponsesDecodeSnakeCaseFields() throws {
        let key = try JSONDecoder().decode(
            GroupKeyRecord.self,
            from: Data(#"{"epoch":4,"wrapped_key":"wrapped"}"#.utf8)
        )
        let send = try JSONDecoder().decode(
            SendGroupMessageResponse.self,
            from: Data(#"{"message_id":"m1","created_at":"2026-06-03T00:00:00Z","epoch":4}"#.utf8)
        )
        let history = try JSONDecoder().decode(
            GroupHistoryResponse.self,
            from: Data(#"{"messages":[{"id":"m1","group_id":"g1","sender_id":"u1","epoch":4,"ciphertext":"opaque","created_at":"2026-06-03T00:00:00Z"}]}"#.utf8)
        )

        XCTAssertEqual(key, GroupKeyRecord(epoch: 4, wrappedKey: "wrapped"))
        XCTAssertEqual(send.messageId, "m1")
        XCTAssertEqual(send.createdAt, "2026-06-03T00:00:00Z")
        XCTAssertEqual(send.epoch, 4)
        XCTAssertEqual(history.messages, [
            GroupMessageRecord(
                id: "m1",
                groupId: "g1",
                senderId: "u1",
                epoch: 4,
                ciphertext: "opaque",
                createdAt: "2026-06-03T00:00:00Z"
            )
        ])
    }

    func testSendGroupMessageRequestEncodesExactlyEpochAndCiphertext() throws {
        let payload = SendGroupMessageRequest(epoch: 9, ciphertext: "opaque")
        let object = try encodedObject(payload)

        XCTAssertEqual(Set(object.keys), ["epoch", "ciphertext"])
        XCTAssertEqual(object["epoch"] as? Int, 9)
        XCTAssertEqual(object["ciphertext"] as? String, "opaque")
        assertNoPlaintextFields(in: payload)
    }

    func testEncodedPayloadsContainNoPlaintextBodyOrTextKeys() throws {
        let payloads: [any Encodable] = [
            CreateGroupRequest(name: "team", members: [GroupMemberKeyDTO(username: "alice", wrappedKey: "wrapped")]),
            AddMemberRequest(username: "bob", epoch: 1, keys: [WrappedKeyDTO(memberId: "u2", wrappedKey: "wrapped")]),
            SendGroupMessageRequest(epoch: 1, ciphertext: "opaque")
        ]

        for payload in payloads {
            assertNoPlaintextFields(in: payload)
        }
    }

    private func encodedObject<T: Encodable>(_ payload: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(payload)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func assertNoPlaintextFields<T: Encodable>(in payload: T, file: StaticString = #filePath, line: UInt = #line) {
        do {
            let data = try JSONEncoder().encode(payload)
            let json = String(decoding: data, as: UTF8.self)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

            XCTAssertFalse(json.contains(#""plaintext""#), file: file, line: line)
            XCTAssertFalse(json.contains(#""body""#), file: file, line: line)
            XCTAssertFalse(json.contains(#""text""#), file: file, line: line)
            XCTAssertFalse(object.keys.contains("plaintext"), file: file, line: line)
            XCTAssertFalse(object.keys.contains("body"), file: file, line: line)
            XCTAssertFalse(object.keys.contains("text"), file: file, line: line)
        } catch {
            XCTFail("Encoding failed: \(error)", file: file, line: line)
        }
    }
}
