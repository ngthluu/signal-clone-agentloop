import CryptoKit
import Foundation
import XCTest
@testable import ChatApp

final class LiveConversationsE2ETests: XCTestCase {
    func testLiveConversationListOrderingAndHistory() async throws {
        let backendURLString = ProcessInfo.processInfo.environment["CHATAPP_LIVE_BACKEND_URL"]
        try XCTSkipUnless(backendURLString != nil, "CHATAPP_LIVE_BACKEND_URL is not set")

        guard let backendURLString, let backendURL = URL(string: backendURLString) else {
            XCTFail("CHATAPP_LIVE_BACKEND_URL is not a valid URL")
            return
        }

        let registrationClient = HTTPRegistrationClient(baseURL: backendURL)
        let authClient = HTTPAuthClient(baseURL: backendURL)
        let messageService = HTTPMessageService(baseURL: backendURL)
        let crypto = MessageCrypto()

        let viewer = try await makeLiveUser(
            prefix: "conv_v",
            registrationClient: registrationClient,
            authClient: authClient,
            messageService: messageService,
            crypto: crypto
        )
        let peerOne = try await makeLiveUser(
            prefix: "conv_p1",
            registrationClient: registrationClient,
            authClient: authClient,
            messageService: messageService,
            crypto: crypto
        )
        let peerTwo = try await makeLiveUser(
            prefix: "conv_p2",
            registrationClient: registrationClient,
            authClient: authClient,
            messageService: messageService,
            crypto: crypto
        )

        let p1First = "CONV_P1_FIRST_\(UUID().uuidString)"
        let p2Only = "CONV_P2_ONLY_\(UUID().uuidString)"
        let p1Latest = "CONV_P1_LATEST_\(UUID().uuidString)"

        try await sendEncrypted(
            plaintext: p1First,
            from: viewer,
            to: peerOne,
            messageService: messageService,
            crypto: crypto
        )
        try await Task.sleep(nanoseconds: 1_200_000_000)
        try await sendEncrypted(
            plaintext: p2Only,
            from: viewer,
            to: peerTwo,
            messageService: messageService,
            crypto: crypto
        )
        try await Task.sleep(nanoseconds: 1_200_000_000)
        try await sendEncrypted(
            plaintext: p1Latest,
            from: peerOne,
            to: viewer,
            messageService: messageService,
            crypto: crypto
        )

        let fetchedConversations = await messageService.conversations(token: viewer.token)
        let summaries = ConversationList.sorted(
            fetchedConversations.map {
                ConversationSummary(
                    peerId: $0.peerId,
                    peerUsername: $0.peerUsername,
                    lastActivityAt: $0.lastActivityAt,
                    lastMessageId: $0.lastMessageId
                )
            }
        )

        XCTAssertEqual(summaries.map(\.peerUsername), [peerOne.username, peerTwo.username])

        let peerOneHistory = try await fetchHistory(token: viewer.token, withUsername: peerOne.username, baseURL: backendURL)
        let peerTwoHistory = try await fetchHistory(token: viewer.token, withUsername: peerTwo.username, baseURL: backendURL)

        XCTAssertEqual(
            try decryptHistory(
                peerOneHistory,
                usersById: [viewer.userId: viewer, peerOne.userId: peerOne],
                crypto: crypto
            ),
            [p1First, p1Latest]
        )
        XCTAssertEqual(
            try decryptHistory(
                peerTwoHistory,
                usersById: [viewer.userId: viewer, peerTwo.userId: peerTwo],
                crypto: crypto
            ),
            [p2Only]
        )

        try writeProofArtifacts(
            token: viewer.token,
            orderedPeerUsernames: [peerOne.username, peerTwo.username],
            historyCounts: [
                peerOne.username: peerOneHistory.count,
                peerTwo.username: peerTwoHistory.count
            ]
        )
    }

    private func makeLiveUser(
        prefix: String,
        registrationClient: HTTPRegistrationClient,
        authClient: HTTPAuthClient,
        messageService: HTTPMessageService,
        crypto: MessageCrypto
    ) async throws -> LiveConversationUser {
        let usernameSuffix = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(20))
        let username = "\(prefix)_\(usernameSuffix)"
        let identity = CryptoIdentity(privateKey: Curve25519.Signing.PrivateKey())
        let x25519PrivateKey = Curve25519.KeyAgreement.PrivateKey()
        let x25519PublicKey = x25519PrivateKey.publicKey.rawRepresentation.base64EncodedString()

        let registration = await registrationClient.register(
            username: username,
            publicKeyBase64: identity.publicKeyBase64
        )
        let userId: String
        switch registration {
        case let .success(registeredUserId):
            userId = registeredUserId
        default:
            throw LiveConversationError.registrationFailed(username, "\(registration)")
        }

        let token = try await signIn(username: username, identity: identity, authClient: authClient)
        let signature = crypto.signPrekey(x25519PublicKeyBase64: x25519PublicKey, with: identity)
        let published = await messageService.publishPrekey(
            token: token,
            x25519PublicKey: x25519PublicKey,
            signature: signature
        )
        XCTAssertTrue(published, "Expected signed prekey publish to succeed for \(username)")

        return LiveConversationUser(
            username: username,
            userId: userId,
            token: token,
            identity: identity,
            x25519PrivateKey: x25519PrivateKey,
            x25519PublicKey: x25519PublicKey
        )
    }

    private func signIn(
        username: String,
        identity: CryptoIdentity,
        authClient: HTTPAuthClient
    ) async throws -> String {
        let challenge = await authClient.requestChallenge(username: username)
        let challengeId: String
        let nonceBase64: String
        switch challenge {
        case let .challenge(returnedChallengeId, returnedNonceBase64):
            challengeId = returnedChallengeId
            nonceBase64 = returnedNonceBase64
        default:
            throw LiveConversationError.challengeFailed(username, "\(challenge)")
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
            throw LiveConversationError.verifyFailed(username, "\(verification)")
        }
    }

    private func sendEncrypted(
        plaintext: String,
        from sender: LiveConversationUser,
        to recipient: LiveConversationUser,
        messageService: HTTPMessageService,
        crypto: MessageCrypto
    ) async throws {
        let fetchedPrekey = await messageService.fetchPrekey(username: recipient.username, token: sender.token)
        let recipientPrekey = try XCTUnwrap(fetchedPrekey)
        XCTAssertTrue(
            MessageCrypto.verifyPrekey(
                x25519PublicKeyBase64: recipientPrekey.x25519PublicKey,
                signatureBase64: recipientPrekey.keySignature,
                identityPublicKeyBase64: recipientPrekey.identityPublicKey
            )
        )

        let ciphertext = try crypto.encrypt(
            Data(plaintext.utf8),
            toRecipientX25519: recipientPrekey.x25519PublicKey
        )
        let sendResult = await messageService.send(
            token: sender.token,
            recipientUsername: recipient.username,
            ciphertext: ciphertext
        )

        guard case .success = sendResult else {
            XCTFail("Expected encrypted message send to succeed, got \(sendResult)")
            return
        }
    }

    private func fetchHistory(
        token: String,
        withUsername username: String,
        baseURL: URL
    ) async throws -> [MessageRecord] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("messages"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "with", value: username)]
        let url = try XCTUnwrap(components?.url)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(httpResponse.statusCode, 200)
        return try JSONDecoder().decode(LiveConversationHistoryResponse.self, from: data).messages
    }

    private func decryptHistory(
        _ records: [MessageRecord],
        usersById: [String: LiveConversationUser],
        crypto: MessageCrypto
    ) throws -> [String] {
        try records.map { record in
            guard let recipient = usersById[record.recipientId] else {
                throw LiveConversationError.unknownRecipient(record.recipientId)
            }
            let plaintext = try crypto.decrypt(
                record.ciphertext,
                withLocalX25519: recipient.x25519PrivateKey
            )
            return try XCTUnwrap(String(data: plaintext, encoding: .utf8))
        }
    }

    private func writeProofArtifacts(
        token: String,
        orderedPeerUsernames: [String],
        historyCounts: [String: Int]
    ) throws {
        let environment = ProcessInfo.processInfo.environment
        try writeIfRequested(token, path: environment["CHATAPP_CONV_TOKEN_OUT"])
        try writeIfRequested(orderedPeerUsernames.joined(separator: "\n"), path: environment["CHATAPP_CONV_ORDER_OUT"])
        let historyOutput = orderedPeerUsernames
            .map { "\($0)=\(historyCounts[$0] ?? 0)" }
            .joined(separator: "\n")
        try writeIfRequested(historyOutput, path: environment["CHATAPP_CONV_HISTORY_OUT"])
    }

    private func writeIfRequested(_ value: String, path: String?) throws {
        guard let path else {
            return
        }
        try value.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
    }
}

private struct LiveConversationUser {
    let username: String
    let userId: String
    let token: String
    let identity: CryptoIdentity
    let x25519PrivateKey: Curve25519.KeyAgreement.PrivateKey
    let x25519PublicKey: String
}

private struct LiveConversationHistoryResponse: Decodable {
    let messages: [MessageRecord]
}

private enum LiveConversationError: Error, CustomStringConvertible {
    case registrationFailed(String, String)
    case challengeFailed(String, String)
    case verifyFailed(String, String)
    case unknownRecipient(String)

    var description: String {
        switch self {
        case let .registrationFailed(username, result):
            return "Registration failed for \(username): \(result)"
        case let .challengeFailed(username, result):
            return "Challenge failed for \(username): \(result)"
        case let .verifyFailed(username, result):
            return "Verify failed for \(username): \(result)"
        case let .unknownRecipient(userId):
            return "History record had unknown recipient \(userId)"
        }
    }
}
