import CryptoKit
import Foundation
import XCTest
@testable import ChatApp

final class LiveAuthE2ETests: XCTestCase {
    func testLivePasswordFreeAuthRoundTripAndRejectsCorruptedSignature() async throws {
        let backendURLString = ProcessInfo.processInfo.environment["CHATAPP_LIVE_BACKEND_URL"]
        try XCTSkipUnless(backendURLString != nil, "CHATAPP_LIVE_BACKEND_URL is not set")

        guard let backendURLString, let backendURL = URL(string: backendURLString) else {
            XCTFail("CHATAPP_LIVE_BACKEND_URL is not a valid URL")
            return
        }

        let usernameSuffix = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(20))
        let username = "auth_\(usernameSuffix)"
        let identity = CryptoIdentity(privateKey: Curve25519.Signing.PrivateKey())
        let registrationClient = HTTPRegistrationClient(baseURL: backendURL)
        let authClient = HTTPAuthClient(baseURL: backendURL)

        let registration = await registrationClient.register(
            username: username,
            publicKeyBase64: identity.publicKeyBase64
        )
        guard case let .success(registeredUserId) = registration else {
            XCTFail("Expected live registration to succeed, got \(registration)")
            return
        }
        XCTAssertFalse(registeredUserId.isEmpty)

        let challenge = await authClient.requestChallenge(username: username)
        let challengeId: String
        let nonceBase64: String
        switch challenge {
        case let .challenge(returnedChallengeId, returnedNonceBase64):
            challengeId = returnedChallengeId
            nonceBase64 = returnedNonceBase64
        default:
            XCTFail("Expected challenge for registered user, got \(challenge)")
            return
        }

        let nonce = try XCTUnwrap(Data(base64Encoded: nonceBase64))
        let signatureBase64 = identity.sign(nonce).base64EncodedString()

        let verification = await authClient.verify(
            challengeId: challengeId,
            signatureBase64: signatureBase64
        )
        let token: String
        switch verification {
        case let .success(returnedToken, userId, returnedUsername):
            token = returnedToken
            XCTAssertEqual(userId, registeredUserId)
            XCTAssertEqual(returnedUsername, username)
        default:
            XCTFail("Expected signed nonce to verify, got \(verification)")
            return
        }

        XCTAssertFalse(token.isEmpty)
        let isSessionValid = await authClient.validateSession(token: token)
        XCTAssertTrue(isSessionValid)

        if let tokenOut = ProcessInfo.processInfo.environment["CHATAPP_LIVE_TOKEN_OUT"] {
            try token.write(to: URL(fileURLWithPath: tokenOut), atomically: true, encoding: .utf8)
        }

        let rejectedChallenge = await authClient.requestChallenge(username: username)
        let rejectedChallengeId: String
        let rejectedNonceBase64: String
        switch rejectedChallenge {
        case let .challenge(returnedChallengeId, returnedNonceBase64):
            rejectedChallengeId = returnedChallengeId
            rejectedNonceBase64 = returnedNonceBase64
        default:
            XCTFail("Expected second challenge for registered user, got \(rejectedChallenge)")
            return
        }

        let rejectedNonce = try XCTUnwrap(Data(base64Encoded: rejectedNonceBase64))
        var corruptedSignature = identity.sign(rejectedNonce)
        corruptedSignature[0] ^= 0xff

        let rejected = await authClient.verify(
            challengeId: rejectedChallengeId,
            signatureBase64: corruptedSignature.base64EncodedString()
        )
        guard case .rejected = rejected else {
            XCTFail("Expected corrupted signature to be rejected, got \(rejected)")
            return
        }
    }
}
