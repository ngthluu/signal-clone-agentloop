import CryptoKit
import Foundation
import XCTest
@testable import ChatApp

final class LiveEmojiDME2ETests: XCTestCase {
    func testLiveEmojiOnlyDirectMessageRoundTripRendersForRecipient() async throws {
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

        let alice = try await makeLiveUser(
            prefix: "emoji_a",
            registrationClient: registrationClient,
            authClient: authClient,
            messageService: messageService,
            crypto: crypto
        )
        let bob = try await makeLiveUser(
            prefix: "emoji_b",
            registrationClient: registrationClient,
            authClient: authClient,
            messageService: messageService,
            crypto: crypto
        )

        let fetchedBobPrekey = await messageService.fetchPrekey(username: bob.username, token: alice.token)
        let bobPrekey = try XCTUnwrap(fetchedBobPrekey)
        XCTAssertEqual(bobPrekey.identityPublicKey, bob.identity.publicKeyBase64)
        XCTAssertEqual(bobPrekey.x25519PublicKey, bob.x25519PublicKey)
        XCTAssertTrue(
            MessageCrypto.verifyPrekey(
                x25519PublicKeyBase64: bobPrekey.x25519PublicKey,
                signatureBase64: bobPrekey.keySignature,
                identityPublicKeyBase64: bobPrekey.identityPublicKey
            )
        )

        let emoji = "😀🎉🚀🍕👍🏽👨‍👩‍👧🇯🇵❤️"
        let ciphertext = try crypto.encrypt(
            Data(emoji.utf8),
            toRecipientX25519: bobPrekey.x25519PublicKey
        )
        XCTAssertFalse(ciphertext.contains(emoji))

        let wireBodyData = try JSONEncoder().encode(
            SendMessageRequest(recipientUsername: bob.username, ciphertext: ciphertext)
        )
        let wireBody = try XCTUnwrap(String(data: wireBodyData, encoding: .utf8))
        XCTAssertFalse(wireBody.contains(emoji))

        async let liveRecord = Self.firstLiveMessage(
            for: bob.token,
            service: messageService,
            timeoutNanoseconds: 5_000_000_000
        )
        try await Task.sleep(nanoseconds: 150_000_000)

        let sendResponse = try await postMessage(
            body: wireBodyData,
            token: alice.token,
            baseURL: backendURL
        )
        let messageId = sendResponse.messageId

        let storedMessage = try await waitForHistoryMessage(
            id: messageId,
            token: bob.token,
            withUsername: alice.username,
            baseURL: backendURL
        )
        XCTAssertEqual(storedMessage.ciphertext, ciphertext)

        let decryptedHistory = try crypto.decrypt(
            storedMessage.ciphertext,
            withLocalX25519: bob.x25519PrivateKey
        )
        XCTAssertEqual(decryptedHistory, Data(emoji.utf8))
        let renderedHistoryText = try XCTUnwrap(String(data: decryptedHistory, encoding: .utf8))
        XCTAssertEqual(
            DisplayMessage(
                id: storedMessage.id,
                isMine: false,
                text: renderedHistoryText,
                createdAt: storedMessage.createdAt
            ).text,
            emoji
        )

        let streamedMessage = try await liveRecord
        XCTAssertEqual(streamedMessage.id, messageId)
        XCTAssertEqual(streamedMessage.ciphertext, ciphertext)
        let decryptedStream = try crypto.decrypt(
            streamedMessage.ciphertext,
            withLocalX25519: bob.x25519PrivateKey
        )
        XCTAssertEqual(decryptedStream, Data(emoji.utf8))
        let renderedStreamText = try XCTUnwrap(String(data: decryptedStream, encoding: .utf8))
        XCTAssertEqual(
            DisplayMessage(
                id: streamedMessage.id,
                isMine: false,
                text: renderedStreamText,
                createdAt: streamedMessage.createdAt
            ).text,
            emoji
        )

        try writeProofArtifacts(
            emoji: emoji,
            wireBody: wireBody,
            messageId: messageId,
            recipientToken: bob.token,
            senderUsername: alice.username
        )
    }

    private func makeLiveUser(
        prefix: String,
        registrationClient: HTTPRegistrationClient,
        authClient: HTTPAuthClient,
        messageService: HTTPMessageService,
        crypto: MessageCrypto
    ) async throws -> LiveEmojiDMUser {
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
            throw LiveEmojiDMError.registrationFailed(username, "\(registration)")
        }

        let token = try await signIn(username: username, identity: identity, authClient: authClient)
        let signature = crypto.signPrekey(x25519PublicKeyBase64: x25519PublicKey, with: identity)
        let published = await messageService.publishPrekey(
            token: token,
            x25519PublicKey: x25519PublicKey,
            signature: signature
        )
        XCTAssertTrue(published, "Expected signed prekey publish to succeed for \(username)")

        return LiveEmojiDMUser(
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
            throw LiveEmojiDMError.challengeFailed(username, "\(challenge)")
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
            throw LiveEmojiDMError.verifyFailed(username, "\(verification)")
        }
    }

    private func postMessage(
        body: Data,
        token: String,
        baseURL: URL
    ) async throws -> SendMessageResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent("messages"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(httpResponse.statusCode, 201)
        return try JSONDecoder().decode(SendMessageResponse.self, from: data)
    }

    private func waitForHistoryMessage(
        id: String,
        token: String,
        withUsername username: String,
        baseURL: URL
    ) async throws -> MessageRecord {
        var lastHistory: [MessageRecord] = []
        for _ in 0..<20 {
            lastHistory = try await fetchLiveHistory(token: token, withUsername: username, baseURL: baseURL)
            if let record = lastHistory.first(where: { $0.id == id }) {
                return record
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTFail("Expected history to contain message \(id), got \(lastHistory)")
        throw LiveEmojiDMError.historyMissing(id)
    }

    private static func firstLiveMessage(
        for token: String,
        service: HTTPMessageService,
        timeoutNanoseconds: UInt64
    ) async throws -> MessageRecord {
        try await withThrowingTaskGroup(of: MessageRecord?.self) { group in
            group.addTask {
                for try await record in service.liveMessages(token: token) {
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
                throw LiveEmojiDMError.liveMessageMissing
            }
            return first
        }
    }

    private func fetchLiveHistory(
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
        return try JSONDecoder().decode(LiveEmojiHistoryResponse.self, from: data).messages
    }

    private func writeProofArtifacts(
        emoji: String,
        wireBody: String,
        messageId: String,
        recipientToken: String,
        senderUsername: String
    ) throws {
        let environment = ProcessInfo.processInfo.environment
        try writeIfRequested(emoji, path: environment["CHATAPP_EMOJI_SENTINEL_OUT"])
        try writeIfRequested(wireBody, path: environment["CHATAPP_EMOJI_WIRE_OUT"])
        try writeIfRequested(messageId, path: environment["CHATAPP_EMOJI_MSGID_OUT"])
        try writeIfRequested(recipientToken, path: environment["CHATAPP_EMOJI_TOKEN_OUT"])
        try writeIfRequested(senderUsername, path: environment["CHATAPP_EMOJI_SENDER_OUT"])
    }

    private func writeIfRequested(_ value: String, path: String?) throws {
        guard let path else {
            return
        }
        try value.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
    }
}

private struct LiveEmojiDMUser {
    let username: String
    let userId: String
    let token: String
    let identity: CryptoIdentity
    let x25519PrivateKey: Curve25519.KeyAgreement.PrivateKey
    let x25519PublicKey: String
}

private struct LiveEmojiHistoryResponse: Decodable {
    let messages: [MessageRecord]
}

private enum LiveEmojiDMError: Error {
    case registrationFailed(String, String)
    case challengeFailed(String, String)
    case verifyFailed(String, String)
    case historyMissing(String)
    case liveMessageMissing
}
