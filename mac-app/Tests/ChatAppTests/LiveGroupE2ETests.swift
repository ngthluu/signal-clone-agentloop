import CryptoKit
import Foundation
import XCTest
@testable import ChatApp

final class LiveGroupE2ETests: XCTestCase {
    private var coordinatorSupport: LiveGroupCoordinatorTestSupport?

    override func tearDownWithError() throws {
        coordinatorSupport?.cleanup()
        coordinatorSupport = nil
        try super.tearDownWithError()
    }

    @MainActor
    func testLiveCoordinatorCreatesGroupAndPeerReceivesDecryptedMessage() async throws {
        let backendURLString = ProcessInfo.processInfo.environment["CHATAPP_LIVE_BACKEND_URL"]
        try XCTSkipUnless(backendURLString != nil, "CHATAPP_LIVE_BACKEND_URL is not set")

        guard let backendURLString, let backendURL = URL(string: backendURLString) else {
            XCTFail("CHATAPP_LIVE_BACKEND_URL is not a valid URL")
            return
        }

        let support = LiveGroupCoordinatorTestSupport(backendURL: backendURL)
        coordinatorSupport = support
        let alice = try await support.makeUser(prefix: "coord_a")
        let bob = try await support.makeUser(prefix: "coord_b")

        await alice.coordinator.createGroup(
            name: "Live Coordinators \(UUID().uuidString)",
            memberUsernames: [bob.username]
        )
        let groupId = try XCTUnwrap(alice.coordinator.groupId)
        XCTAssertEqual(alice.coordinator.currentEpoch, 0)
        XCTAssertNotNil(alice.coordinator.epochKeys[0])

        await bob.coordinator.openGroup(id: groupId)
        XCTAssertEqual(bob.coordinator.groupName, alice.coordinator.groupName)
        XCTAssertEqual(bob.coordinator.members.map(\.username).sorted(), [alice.username, bob.username].sorted())
        XCTAssertNotNil(bob.coordinator.epochKeys[0])

        let messageText = "hello"
        await alice.coordinator.send(text: messageText)

        let aliceMessage = try await waitForCoordinatorMessage(
            in: alice.coordinator,
            text: messageText,
            timeout: 5
        )
        XCTAssertEqual(aliceMessage.senderName, "You")
        XCTAssertTrue(aliceMessage.isMine)
        XCTAssertEqual(aliceMessage.senderId, alice.userId)

        let bobMessage = try await waitForCoordinatorMessageWithCatchup(
            in: bob.coordinator,
            text: messageText,
            timeout: 5
        )
        XCTAssertEqual(bobMessage.senderName, alice.username)
        XCTAssertFalse(bobMessage.isMine)
        XCTAssertEqual(bobMessage.senderId, alice.userId)
    }

    func testLiveEncryptedGroupMessageRoundTripAndLateMemberCannotReadPriorMessages() async throws {
        let backendURLString = ProcessInfo.processInfo.environment["CHATAPP_LIVE_BACKEND_URL"]
        try XCTSkipUnless(backendURLString != nil, "CHATAPP_LIVE_BACKEND_URL is not set")

        guard let backendURLString, let backendURL = URL(string: backendURLString) else {
            XCTFail("CHATAPP_LIVE_BACKEND_URL is not a valid URL")
            return
        }

        let registrationClient = HTTPRegistrationClient(baseURL: backendURL)
        let authClient = HTTPAuthClient(baseURL: backendURL)
        let messageService = HTTPMessageService(baseURL: backendURL)
        let groupService = HTTPGroupService(baseURL: backendURL)
        let messageCrypto = MessageCrypto()
        let groupCrypto = GroupCrypto()

        let alice = try await makeLiveUser(prefix: "grp_a", registrationClient: registrationClient, authClient: authClient, messageService: messageService, crypto: messageCrypto)
        let bob = try await makeLiveUser(prefix: "grp_b", registrationClient: registrationClient, authClient: authClient, messageService: messageService, crypto: messageCrypto)
        let carol = try await makeLiveUser(prefix: "grp_c", registrationClient: registrationClient, authClient: authClient, messageService: messageService, crypto: messageCrypto)
        let dave = try await makeLiveUser(prefix: "grp_d", registrationClient: registrationClient, authClient: authClient, messageService: messageService, crypto: messageCrypto)

        let initialMembers = [alice, bob, carol]
        let groupKey0 = groupCrypto.newGroupKey()
        let createMembers = try await wrappedCreateMembers(
            users: initialMembers,
            groupKey: groupKey0,
            requesterToken: alice.token,
            messageService: messageService,
            groupCrypto: groupCrypto
        )

        guard let createResponse = await groupService.createGroup(
            token: alice.token,
            name: "Live Group \(UUID().uuidString)",
            members: createMembers
        ) else {
            XCTFail("Expected live group creation to succeed")
            return
        }
        XCTAssertEqual(createResponse.epoch, 0)
        let groupId = createResponse.groupId

        let sentinel = "GROUP_PLAINTEXT_SENTINEL_\(UUID().uuidString)"
        let sentinelCiphertext = try groupCrypto.encryptGroupMessage(Data(sentinel.utf8), epoch: 0, groupKey: groupKey0)
        let wireBodyData = try JSONEncoder().encode(SendGroupMessageRequest(epoch: 0, ciphertext: sentinelCiphertext))
        let wireBody = try XCTUnwrap(String(data: wireBodyData, encoding: .utf8))
        XCTAssertFalse(wireBody.contains(sentinel))

        async let liveRecord = Self.firstLiveGroupMessage(
            groupId: groupId,
            token: bob.token,
            service: groupService,
            timeoutNanoseconds: 5_000_000_000
        )
        try await Task.sleep(nanoseconds: 150_000_000)

        let sendResult = await groupService.sendGroupMessage(
            groupId: groupId,
            token: alice.token,
            epoch: 0,
            ciphertext: sentinelCiphertext
        )
        let messageId: String
        switch sendResult {
        case let .success(returnedMessageId, _, returnedEpoch):
            XCTAssertEqual(returnedEpoch, 0)
            messageId = returnedMessageId
        default:
            XCTFail("Expected encrypted group message send to succeed, got \(sendResult)")
            return
        }

        let bobSentinelRecord = try await waitForGroupHistoryMessage(
            id: messageId,
            groupId: groupId,
            token: bob.token,
            service: groupService
        )
        XCTAssertEqual(bobSentinelRecord.ciphertext, sentinelCiphertext)

        let bobKey0 = try await unwrappedKey(
            epoch: 0,
            groupId: groupId,
            user: bob,
            service: groupService,
            crypto: groupCrypto
        )
        let carolKey0 = try await unwrappedKey(
            epoch: 0,
            groupId: groupId,
            user: carol,
            service: groupService,
            crypto: groupCrypto
        )
        XCTAssertEqual(try groupCrypto.decryptGroupMessage(bobSentinelRecord.ciphertext, groupKey: bobKey0), Data(sentinel.utf8))
        XCTAssertEqual(
            try groupCrypto.decryptGroupMessage(bobSentinelRecord.ciphertext, groupKey: carolKey0),
            Data(sentinel.utf8)
        )

        let streamedRecord = try await liveRecord
        XCTAssertEqual(streamedRecord.id, messageId)
        XCTAssertEqual(streamedRecord.ciphertext, sentinelCiphertext)
        XCTAssertEqual(try groupCrypto.decryptGroupMessage(streamedRecord.ciphertext, groupKey: bobKey0), Data(sentinel.utf8))

        let fetchedDetailBeforeAdd = await groupService.fetchGroup(id: groupId, token: alice.token)
        let detailBeforeAdd = try XCTUnwrap(fetchedDetailBeforeAdd)
        XCTAssertEqual(detailBeforeAdd.currentEpoch, 0)
        let groupKey1 = groupCrypto.newGroupKey()
        let addKeys = try await wrappedKeys(
            members: detailBeforeAdd.members + [GroupMemberDTO(userId: dave.userId, username: dave.username, joinedEpoch: 1)],
            groupKey: groupKey1,
            requesterToken: alice.token,
            messageService: messageService,
            groupCrypto: groupCrypto
        )
        guard let addResponse = await groupService.addMember(
            groupId: groupId,
            token: alice.token,
            username: dave.username,
            epoch: 1,
            keys: addKeys
        ) else {
            XCTFail("Expected adding late group member to succeed")
            return
        }
        XCTAssertEqual(addResponse.epoch, 1)
        XCTAssertEqual(addResponse.member.username, dave.username)

        let secondPlaintext = "GROUP_EPOCH_ONE_\(UUID().uuidString)"
        let secondCiphertext = try groupCrypto.encryptGroupMessage(Data(secondPlaintext.utf8), epoch: 1, groupKey: groupKey1)
        let secondSend = await groupService.sendGroupMessage(
            groupId: groupId,
            token: alice.token,
            epoch: 1,
            ciphertext: secondCiphertext
        )
        let secondMessageId: String
        switch secondSend {
        case let .success(returnedMessageId, _, returnedEpoch):
            XCTAssertEqual(returnedEpoch, 1)
            secondMessageId = returnedMessageId
        default:
            XCTFail("Expected epoch-1 group message send to succeed, got \(secondSend)")
            return
        }

        let daveKeys = await groupService.fetchKeys(groupId: groupId, token: dave.token)
        XCTAssertFalse(daveKeys.contains(where: { $0.epoch == 0 }))
        XCTAssertTrue(daveKeys.contains(where: { $0.epoch == 1 }))
        let daveGroupKeys = try daveKeys.map { record in
            try groupCrypto.unwrapGroupKey(record.wrappedKey, withLocalX25519: dave.x25519PrivateKey)
        }
        XCTAssertFalse(daveGroupKeys.isEmpty)
        for key in daveGroupKeys {
            XCTAssertThrowsError(try groupCrypto.decryptGroupMessage(sentinelCiphertext, groupKey: key))
        }

        let daveSecondRecord = try await waitForGroupHistoryMessage(
            id: secondMessageId,
            groupId: groupId,
            token: dave.token,
            service: groupService
        )
        let daveKey1 = try XCTUnwrap(daveKeys.first(where: { $0.epoch == 1 }))
        let unwrappedDaveKey1 = try groupCrypto.unwrapGroupKey(daveKey1.wrappedKey, withLocalX25519: dave.x25519PrivateKey)
        XCTAssertEqual(
            try groupCrypto.decryptGroupMessage(daveSecondRecord.ciphertext, groupKey: unwrappedDaveKey1),
            Data(secondPlaintext.utf8)
        )

        try writeProofArtifacts(
            sentinel: sentinel,
            wireBody: wireBody,
            messageId: messageId,
            groupId: groupId,
            memberToken: bob.token,
            lateMemberUsername: dave.username
        )
    }

    private func makeLiveUser(
        prefix: String,
        registrationClient: HTTPRegistrationClient,
        authClient: HTTPAuthClient,
        messageService: HTTPMessageService,
        crypto: MessageCrypto
    ) async throws -> LiveGroupUser {
        let usernameSuffix = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(20))
        let username = "\(prefix)_\(usernameSuffix)"
        let identity = CryptoIdentity(privateKey: Curve25519.Signing.PrivateKey())
        let x25519PrivateKey = Curve25519.KeyAgreement.PrivateKey()
        let x25519PublicKey = x25519PrivateKey.publicKey.rawRepresentation.base64EncodedString()

        let registration = await registrationClient.register(username: username, publicKeyBase64: identity.publicKeyBase64)
        let userId: String
        switch registration {
        case let .success(registeredUserId):
            userId = registeredUserId
        default:
            throw LiveGroupError.registrationFailed(username, "\(registration)")
        }

        let token = try await signIn(username: username, identity: identity, authClient: authClient)
        let signature = crypto.signPrekey(x25519PublicKeyBase64: x25519PublicKey, with: identity)
        let published = await messageService.publishPrekey(
            token: token,
            x25519PublicKey: x25519PublicKey,
            signature: signature
        )
        XCTAssertTrue(published, "Expected signed prekey publish to succeed for \(username)")

        return LiveGroupUser(
            username: username,
            userId: userId,
            token: token,
            identity: identity,
            x25519PrivateKey: x25519PrivateKey,
            x25519PublicKey: x25519PublicKey
        )
    }

    private func signIn(username: String, identity: CryptoIdentity, authClient: HTTPAuthClient) async throws -> String {
        let challenge = await authClient.requestChallenge(username: username)
        let challengeId: String
        let nonceBase64: String
        switch challenge {
        case let .challenge(returnedChallengeId, returnedNonceBase64):
            challengeId = returnedChallengeId
            nonceBase64 = returnedNonceBase64
        default:
            throw LiveGroupError.challengeFailed(username, "\(challenge)")
        }

        let nonce = try XCTUnwrap(Data(base64Encoded: nonceBase64))
        let verification = await authClient.verify(
            challengeId: challengeId,
            signatureBase64: identity.sign(nonce).base64EncodedString()
        )
        switch verification {
        case let .success(token, _, returnedUsername):
            XCTAssertEqual(returnedUsername, username)
            return token
        default:
            throw LiveGroupError.verifyFailed(username, "\(verification)")
        }
    }

    private func wrappedCreateMembers(
        users: [LiveGroupUser],
        groupKey: Data,
        requesterToken: String,
        messageService: HTTPMessageService,
        groupCrypto: GroupCrypto
    ) async throws -> [GroupMemberKeyDTO] {
        try await users.asyncMap { user in
            let prekey = try await verifiedPrekey(username: user.username, token: requesterToken, service: messageService)
            return GroupMemberKeyDTO(
                username: prekey.username,
                wrappedKey: try groupCrypto.wrapGroupKey(groupKey, toRecipientX25519: prekey.x25519PublicKey)
            )
        }
    }

    private func wrappedKeys(
        members: [GroupMemberDTO],
        groupKey: Data,
        requesterToken: String,
        messageService: HTTPMessageService,
        groupCrypto: GroupCrypto
    ) async throws -> [WrappedKeyDTO] {
        try await members.asyncMap { member in
            let prekey = try await verifiedPrekey(username: member.username, token: requesterToken, service: messageService)
            return WrappedKeyDTO(
                memberId: prekey.userId,
                wrappedKey: try groupCrypto.wrapGroupKey(groupKey, toRecipientX25519: prekey.x25519PublicKey)
            )
        }
    }

    private func verifiedPrekey(username: String, token: String, service: HTTPMessageService) async throws -> PrekeyResponse {
        let fetchedPrekey = await service.fetchPrekey(username: username, token: token)
        let prekey = try XCTUnwrap(fetchedPrekey)
        XCTAssertTrue(
            MessageCrypto.verifyPrekey(
                x25519PublicKeyBase64: prekey.x25519PublicKey,
                signatureBase64: prekey.keySignature,
                identityPublicKeyBase64: prekey.identityPublicKey
            ),
            "Expected signed prekey to verify for \(username)"
        )
        return prekey
    }

    private func unwrappedKey(
        epoch: UInt32,
        groupId: String,
        user: LiveGroupUser,
        service: HTTPGroupService,
        crypto: GroupCrypto
    ) async throws -> Data {
        let keys = await service.fetchKeys(groupId: groupId, token: user.token)
        let record = try XCTUnwrap(keys.first(where: { $0.epoch == epoch }))
        return try crypto.unwrapGroupKey(record.wrappedKey, withLocalX25519: user.x25519PrivateKey)
    }

    private func waitForGroupHistoryMessage(
        id: String,
        groupId: String,
        token: String,
        service: HTTPGroupService
    ) async throws -> GroupMessageRecord {
        var lastHistory: [GroupMessageRecord] = []
        for _ in 0..<20 {
            lastHistory = await service.groupHistory(groupId: groupId, token: token, since: nil)
            if let record = lastHistory.first(where: { $0.id == id }) {
                return record
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTFail("Expected group history to contain message \(id), got \(lastHistory)")
        throw LiveGroupError.historyMissing(id)
    }

    @MainActor
    private func waitForCoordinatorMessageWithCatchup(
        in coordinator: GroupCoordinator,
        text: String,
        timeout: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> DisplayGroupMessage {
        if let message = try? await waitForCoordinatorMessage(
            in: coordinator,
            text: text,
            timeout: timeout,
            file: file,
            line: line
        ) {
            return message
        }

        await coordinator.reconnectLive()
        return try await waitForCoordinatorMessage(
            in: coordinator,
            text: text,
            timeout: timeout,
            file: file,
            line: line
        )
    }

    @MainActor
    private func waitForCoordinatorMessage(
        in coordinator: GroupCoordinator,
        text: String,
        timeout: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> DisplayGroupMessage {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let message = coordinator.messages.first(where: { $0.text == text }) {
                return message
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        XCTFail("Timed out waiting for coordinator message '\(text)'. Messages: \(coordinator.messages)", file: file, line: line)
        throw LiveGroupError.coordinatorMessageMissing(text)
    }

    private static func firstLiveGroupMessage(
        groupId: String,
        token: String,
        service: HTTPGroupService,
        timeoutNanoseconds: UInt64
    ) async throws -> GroupMessageRecord {
        try await withThrowingTaskGroup(of: GroupMessageRecord?.self) { group in
            group.addTask {
                for try await record in service.liveGroupMessages(groupId: groupId, token: token) {
                    return record
                }
                return nil
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                return nil
            }

            let first = try await group.next() ?? nil
            group.cancelAll()
            guard let first else {
                throw LiveGroupError.liveMessageMissing
            }
            return first
        }
    }

    private func writeProofArtifacts(
        sentinel: String,
        wireBody: String,
        messageId: String,
        groupId: String,
        memberToken: String,
        lateMemberUsername: String
    ) throws {
        let environment = ProcessInfo.processInfo.environment
        try writeIfRequested(sentinel, path: environment["CHATAPP_GROUP_SENTINEL_OUT"])
        try writeIfRequested(wireBody, path: environment["CHATAPP_GROUP_WIRE_OUT"])
        try writeIfRequested(messageId, path: environment["CHATAPP_GROUP_MSGID_OUT"])
        try writeIfRequested(groupId, path: environment["CHATAPP_GROUP_ID_OUT"])
        try writeIfRequested(memberToken, path: environment["CHATAPP_GROUP_TOKEN_OUT"])
        try writeIfRequested(lateMemberUsername, path: environment["CHATAPP_GROUP_LATE_MEMBER_OUT"])
    }

    private func writeIfRequested(_ value: String, path: String?) throws {
        guard let path else {
            return
        }
        try value.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
    }
}

private struct LiveGroupUser {
    let username: String
    let userId: String
    let token: String
    let identity: CryptoIdentity
    let x25519PrivateKey: Curve25519.KeyAgreement.PrivateKey
    let x25519PublicKey: String
}

private enum LiveGroupError: Error, CustomStringConvertible {
    case registrationFailed(String, String)
    case challengeFailed(String, String)
    case verifyFailed(String, String)
    case historyMissing(String)
    case liveMessageMissing
    case coordinatorMessageMissing(String)

    var description: String {
        switch self {
        case let .registrationFailed(username, result):
            return "Registration failed for \(username): \(result)"
        case let .challengeFailed(username, result):
            return "Challenge failed for \(username): \(result)"
        case let .verifyFailed(username, result):
            return "Verify failed for \(username): \(result)"
        case let .historyMissing(messageId):
            return "Group history did not include message \(messageId)"
        case .liveMessageMissing:
            return "Live group stream did not yield the sent message"
        case let .coordinatorMessageMissing(text):
            return "Coordinator did not surface message \(text)"
        }
    }
}

private extension Array {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async throws -> [T] {
        var values: [T] = []
        values.reserveCapacity(count)
        for element in self {
            values.append(try await transform(element))
        }
        return values
    }
}
