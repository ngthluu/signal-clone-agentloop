import CryptoKit
import Foundation
import XCTest
@testable import ChatApp

final class LiveDME2ETests: XCTestCase {
    func testLiveEncryptedDirectMessageRoundTripStoresOnlyCiphertext() async throws {
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
            prefix: "dm_a",
            registrationClient: registrationClient,
            authClient: authClient,
            messageService: messageService,
            crypto: crypto
        )
        let bob = try await makeLiveUser(
            prefix: "dm_b",
            registrationClient: registrationClient,
            authClient: authClient,
            messageService: messageService,
            crypto: crypto
        )

        let fetchedBobPrekey = await messageService.fetchPrekey(username: bob.username, token: alice.token)
        let bobPrekey = try XCTUnwrap(fetchedBobPrekey)
        XCTAssertTrue(
            MessageCrypto.verifyPrekey(
                x25519PublicKeyBase64: bobPrekey.x25519PublicKey,
                signatureBase64: bobPrekey.keySignature,
                identityPublicKeyBase64: bobPrekey.identityPublicKey
            )
        )

        let sentinel = "PLAINTEXT_SENTINEL_\(UUID().uuidString)"
        let ciphertext = try crypto.encrypt(
            Data(sentinel.utf8),
            toRecipientX25519: bobPrekey.x25519PublicKey
        )
        XCTAssertFalse(ciphertext.contains(sentinel))

        let wireBodyData = try JSONEncoder().encode(
            SendMessageRequest(recipientUsername: bob.username, ciphertext: ciphertext)
        )
        let wireBody = try XCTUnwrap(String(data: wireBodyData, encoding: .utf8))
        XCTAssertFalse(wireBody.contains(sentinel))

        async let liveRecord = Self.firstLiveMessage(
            for: bob.token,
            service: messageService,
            timeoutNanoseconds: 5_000_000_000
        )
        try await Task.sleep(nanoseconds: 150_000_000)

        let sendResult = await messageService.send(
            token: alice.token,
            recipientUsername: bob.username,
            ciphertext: ciphertext
        )
        let messageId: String
        switch sendResult {
        case let .success(returnedMessageId, _):
            messageId = returnedMessageId
        default:
            XCTFail("Expected encrypted message send to succeed, got \(sendResult)")
            return
        }

        let storedMessage = try await waitForHistoryMessage(
            id: messageId,
            token: bob.token,
            withUsername: alice.username,
            baseURL: backendURL
        )
        XCTAssertEqual(storedMessage.ciphertext, ciphertext)
        XCTAssertEqual(
            try crypto.decrypt(storedMessage.ciphertext, withLocalX25519: bob.x25519PrivateKey),
            Data(sentinel.utf8)
        )

        let streamedMessage = try await liveRecord
        XCTAssertEqual(streamedMessage.id, messageId)
        XCTAssertEqual(streamedMessage.ciphertext, ciphertext)
        XCTAssertEqual(
            try crypto.decrypt(streamedMessage.ciphertext, withLocalX25519: bob.x25519PrivateKey),
            Data(sentinel.utf8)
        )

        try writeProofArtifacts(
            sentinel: sentinel,
            wireBody: wireBody,
            messageId: messageId,
            recipientToken: bob.token
        )
    }

    private func makeLiveUser(
        prefix: String,
        registrationClient: HTTPRegistrationClient,
        authClient: HTTPAuthClient,
        messageService: HTTPMessageService,
        crypto: MessageCrypto
    ) async throws -> LiveDMUser {
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
            throw LiveDMError.registrationFailed(username, "\(registration)")
        }

        let token = try await signIn(username: username, identity: identity, authClient: authClient)
        let signature = crypto.signPrekey(x25519PublicKeyBase64: x25519PublicKey, with: identity)
        let published = await messageService.publishPrekey(
            token: token,
            x25519PublicKey: x25519PublicKey,
            signature: signature
        )
        XCTAssertTrue(published, "Expected signed prekey publish to succeed for \(username)")

        return LiveDMUser(
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
            throw LiveDMError.challengeFailed(username, "\(challenge)")
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
            throw LiveDMError.verifyFailed(username, "\(verification)")
        }
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
        throw LiveDMError.historyMissing(id)
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
                throw LiveDMError.liveMessageMissing
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
        return try JSONDecoder().decode(LiveHistoryResponse.self, from: data).messages
    }

    private func writeProofArtifacts(
        sentinel: String,
        wireBody: String,
        messageId: String,
        recipientToken: String
    ) throws {
        let environment = ProcessInfo.processInfo.environment
        try writeIfRequested(sentinel, path: environment["CHATAPP_DM_SENTINEL_OUT"])
        try writeIfRequested(wireBody, path: environment["CHATAPP_DM_WIRE_OUT"])
        try writeIfRequested(messageId, path: environment["CHATAPP_DM_MSGID_OUT"])
        try writeIfRequested(recipientToken, path: environment["CHATAPP_DM_TOKEN_OUT"])
    }

    private func writeIfRequested(_ value: String, path: String?) throws {
        guard let path else {
            return
        }
        try value.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
    }
}

private struct LiveDMUser {
    let username: String
    let userId: String
    let token: String
    let identity: CryptoIdentity
    let x25519PrivateKey: Curve25519.KeyAgreement.PrivateKey
    let x25519PublicKey: String
}

private struct LiveHistoryResponse: Decodable {
    let messages: [MessageRecord]
}

private enum LiveDMError: Error, CustomStringConvertible {
    case registrationFailed(String, String)
    case challengeFailed(String, String)
    case verifyFailed(String, String)
    case historyMissing(String)
    case liveMessageMissing

    var description: String {
        switch self {
        case let .registrationFailed(username, result):
            return "Registration failed for \(username): \(result)"
        case let .challengeFailed(username, result):
            return "Challenge failed for \(username): \(result)"
        case let .verifyFailed(username, result):
            return "Verify failed for \(username): \(result)"
        case let .historyMissing(messageId):
            return "History did not include message \(messageId)"
        case .liveMessageMissing:
            return "Live message stream did not yield the sent message"
        }
    }
}
