import CryptoKit
import Foundation
import XCTest
@testable import ChatApp

final class LiveDMAttachmentE2ETests: XCTestCase {
    private var cleanupURLs: [URL] = []
    private var keychainStores: [KeychainStore] = []

    override func tearDownWithError() throws {
        for store in keychainStores {
            try store.delete()
        }
        for url in cleanupURLs {
            try? FileManager.default.removeItem(at: url)
        }
        try super.tearDownWithError()
    }

    @MainActor
    func testSubscribedRecipientReceivesDownloadsAndDecryptsBinaryAttachment() async throws {
        let backendURLString = ProcessInfo.processInfo.environment["CHATAPP_LIVE_BACKEND_URL"]
        try XCTSkipUnless(backendURLString != nil, "CHATAPP_LIVE_BACKEND_URL is not set")

        guard let backendURLString, let backendURL = URL(string: backendURLString) else {
            XCTFail("CHATAPP_LIVE_BACKEND_URL is not a valid URL")
            return
        }

        let registrationClient = HTTPRegistrationClient(baseURL: backendURL)
        let authClient = HTTPAuthClient(baseURL: backendURL)
        let messageService = HTTPMessageService(baseURL: backendURL)
        let attachmentService = HTTPAttachmentService(baseURL: backendURL)
        let recordingAttachmentService = LiveDMRecordingAttachmentService(delegate: attachmentService)

        let alice = try await makeLiveUser(
            prefix: "dm_att_a",
            registrationClient: registrationClient,
            authClient: authClient,
            messageService: messageService
        )
        let bob = try await makeLiveUser(
            prefix: "dm_att_b",
            registrationClient: registrationClient,
            authClient: authClient,
            messageService: messageService
        )

        let contentSentinel = "DM_LIVE_ATTACHMENT_CONTENT_SENTINEL_\(UUID().uuidString)"
        let filenameSentinel = "DM_LIVE_ATTACHMENT_FILENAME_SENTINEL_\(UUID().uuidString).bin"
        let original = Data([0x00, 0xFF, 0x41, 0x80, 0x13])
            + Data(contentSentinel.utf8)
            + Data([0x00, 0xCA, 0xFE, 0x7F])
        let originalFile = try writeArtifactFile(data: original, filename: filenameSentinel)

        let aliceDM = makeDMCoordinator(
            for: alice,
            messageService: messageService,
            attachmentService: recordingAttachmentService
        )
        let bobDM = makeDMCoordinator(
            for: bob,
            messageService: messageService,
            attachmentService: attachmentService
        )

        await aliceDM.startConversation(withUsername: bob.username)
        await bobDM.startConversation(withUsername: alice.username)
        try await waitForLiveSubscription(to: alice.username, in: bobDM)

        await aliceDM.sendAttachment(data: original, filename: filenameSentinel, mime: "application/octet-stream")

        let received = try await waitForAttachment(
            in: bobDM,
            filename: filenameSentinel,
            timeoutNanoseconds: 5_000_000_000
        )
        XCTAssertFalse(received.isMine)
        XCTAssertEqual(received.text, filenameSentinel)
        let attachment = try XCTUnwrap(received.attachment)
        XCTAssertEqual(attachment.filename, filenameSentinel)
        XCTAssertEqual(attachment.mime, "application/octet-stream")
        XCTAssertEqual(attachment.size, original.count)

        let uploadBlob = try XCTUnwrap(recordingAttachmentService.uploadedBlobs.first)
        XCTAssertNil(recordingAttachmentService.uploadWriteError)
        XCTAssertNotEqual(uploadBlob, original)
        XCTAssertNil(uploadBlob.range(of: Data(contentSentinel.utf8)))
        XCTAssertNil(uploadBlob.range(of: Data(filenameSentinel.utf8)))

        let downloadedOptional = await bobDM.downloadAttachment(attachment)
        let downloaded = try XCTUnwrap(downloadedOptional)
        let downloadedFile = try writeArtifactFile(data: downloaded, filename: "downloaded-\(filenameSentinel)")
        XCTAssertEqual(downloaded, original)
        XCTAssertEqual(try Data(contentsOf: downloadedFile), try Data(contentsOf: originalFile))

        try writeProofArtifacts(
            contentSentinel: contentSentinel,
            filenameSentinel: filenameSentinel,
            originalFile: originalFile,
            downloadedFile: downloadedFile,
            uploadWireFile: try XCTUnwrap(recordingAttachmentService.firstUploadFile),
            attachmentId: attachment.attachmentId,
            bobToken: bob.token
        )
    }

    @MainActor
    private func makeLiveUser(
        prefix: String,
        registrationClient: HTTPRegistrationClient,
        authClient: HTTPAuthClient,
        messageService: HTTPMessageService
    ) async throws -> LiveDMAttachmentUser {
        let suffix = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(20))
        let username = "\(prefix)_\(suffix)"
        let identity = CryptoIdentity(privateKey: Curve25519.Signing.PrivateKey())
        let x25519PrivateKey = Curve25519.KeyAgreement.PrivateKey()

        let registration = await registrationClient.register(username: username, publicKeyBase64: identity.publicKeyBase64)
        let userId: String
        switch registration {
        case let .success(registeredUserId):
            userId = registeredUserId
        default:
            throw LiveDMAttachmentError.registrationFailed(username, "\(registration)")
        }

        let token = try await signIn(username: username, identity: identity, authClient: authClient)
        let publicKey = x25519PrivateKey.publicKey.rawRepresentation.base64EncodedString()
        let signature = MessageCrypto().signPrekey(x25519PublicKeyBase64: publicKey, with: identity)
        let published = await messageService.publishPrekey(
            token: token,
            x25519PublicKey: publicKey,
            signature: signature
        )
        XCTAssertTrue(published, "Expected signed prekey publish to succeed for \(username)")

        let sessionKeychain = KeychainStore(
            service: "\(KeychainStore.defaultService).live.dm.attachments.\(UUID().uuidString)",
            account: "\(KeychainStore.defaultAccount).session",
            usesDataProtectionKeychain: false
        )
        let x25519Keychain = KeychainStore(
            service: "\(KeychainStore.defaultService).live.dm.attachments.\(UUID().uuidString)",
            account: "\(KeychainStore.defaultAccount).x25519",
            usesDataProtectionKeychain: false
        )
        keychainStores.append(sessionKeychain)
        keychainStores.append(x25519Keychain)

        let sessionStore = SessionStore(keychainStore: sessionKeychain)
        try sessionStore.save(token)
        try x25519Keychain.save(x25519PrivateKey.rawRepresentation)

        let accountDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("live-dm-attachment-account-\(UUID().uuidString)", isDirectory: true)
        cleanupURLs.append(accountDirectory)
        let accountStore = LocalAccountStore(directory: accountDirectory)
        try accountStore.save(LocalAccount(username: username, publicKeyBase64: identity.publicKeyBase64, userId: userId))

        return LiveDMAttachmentUser(
            username: username,
            userId: userId,
            token: token,
            identity: identity,
            sessionStore: sessionStore,
            accountStore: accountStore,
            x25519KeyManager: X25519KeyManager(keychainStore: x25519Keychain)
        )
    }

    @MainActor
    private func signIn(username: String, identity: CryptoIdentity, authClient: HTTPAuthClient) async throws -> String {
        let challenge = await authClient.requestChallenge(username: username)
        let challengeId: String
        let nonceBase64: String
        switch challenge {
        case let .challenge(returnedChallengeId, returnedNonceBase64):
            challengeId = returnedChallengeId
            nonceBase64 = returnedNonceBase64
        default:
            throw LiveDMAttachmentError.challengeFailed(username, "\(challenge)")
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
            throw LiveDMAttachmentError.verifyFailed(username, "\(verification)")
        }
    }

    @MainActor
    private func makeDMCoordinator(
        for user: LiveDMAttachmentUser,
        messageService: HTTPMessageService,
        attachmentService: AttachmentService
    ) -> DMCoordinator {
        DMCoordinator(
            identityProvider: LiveDMAttachmentIdentityProvider(identity: user.identity),
            x25519KeyManager: user.x25519KeyManager,
            sessionStore: user.sessionStore,
            accountStore: user.accountStore,
            service: messageService,
            crypto: MessageCrypto(),
            attachmentService: attachmentService,
            fileCrypto: FileCrypto()
        )
    }

    @MainActor
    private func waitForLiveSubscription(to username: String, in coordinator: DMCoordinator) async throws {
        for _ in 0..<20 {
            if coordinator.peerUsername == username, coordinator.statusMessage.isEmpty {
                try await Task.sleep(nanoseconds: 150_000_000)
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw LiveDMAttachmentError.liveSubscriptionMissing
    }

    @MainActor
    private func waitForAttachment(
        in coordinator: DMCoordinator,
        filename: String,
        timeoutNanoseconds: UInt64
    ) async throws -> DisplayMessage {
        let pollInterval: UInt64 = 100_000_000
        let attempts = max(1, Int(timeoutNanoseconds / pollInterval))
        for _ in 0..<attempts {
            if let message = coordinator.messages.first(where: { $0.attachment != nil && $0.text == filename }) {
                return message
            }
            try await Task.sleep(nanoseconds: pollInterval)
        }
        throw LiveDMAttachmentError.liveAttachmentMissing
    }

    private func writeArtifactFile(data: Data, filename: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("live-dm-attachment-proof-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileURL = directory.appendingPathComponent(filename)
        try data.write(to: fileURL)
        return fileURL
    }

    private func writeProofArtifacts(
        contentSentinel: String,
        filenameSentinel: String,
        originalFile: URL,
        downloadedFile: URL,
        uploadWireFile: URL,
        attachmentId: String,
        bobToken: String
    ) throws {
        let environment = ProcessInfo.processInfo.environment
        try writeIfRequested(contentSentinel, paths: [
            environment["CHATAPP_DM_ATTACHMENT_CONTENT_SENTINEL_OUT"],
            environment["CHATAPP_ATTACHMENT_CONTENT_SENTINEL_OUT"]
        ])
        try writeIfRequested(filenameSentinel, paths: [
            environment["CHATAPP_DM_ATTACHMENT_FILENAME_SENTINEL_OUT"],
            environment["CHATAPP_ATTACHMENT_FILENAME_SENTINEL_OUT"]
        ])
        try writeIfRequested(originalFile.path, paths: [
            environment["CHATAPP_DM_ATTACHMENT_ORIGINAL_FILE_OUT"],
            environment["CHATAPP_ATTACHMENT_ORIGINAL_FILE_OUT"],
            environment["CHATAPP_ATTACHMENT_LIVE_ORIGINAL_FILE_OUT"]
        ])
        try writeIfRequested(downloadedFile.path, paths: [
            environment["CHATAPP_DM_ATTACHMENT_DOWNLOADED_FILE_OUT"],
            environment["CHATAPP_DM_ATTACHMENT_DOWNLOAD_FILE_OUT"],
            environment["CHATAPP_ATTACHMENT_LIVE_DM_DOWNLOAD_OUT"]
        ])
        try writeIfRequested(uploadWireFile.path, paths: [
            environment["CHATAPP_DM_ATTACHMENT_UPLOAD_WIRE_FILE_OUT"],
            environment["CHATAPP_ATTACHMENT_UPLOAD_WIRE_FILE_OUT"]
        ])
        try writeIfRequested(attachmentId, paths: [
            environment["CHATAPP_DM_ATTACHMENT_ID_OUT"],
            environment["CHATAPP_ATTACHMENT_DM_ID_OUT"]
        ])
        try writeIfRequested(bobToken, paths: [
            environment["CHATAPP_DM_ATTACHMENT_BOB_TOKEN_OUT"],
            environment["CHATAPP_ATTACHMENT_BOB_TOKEN_OUT"]
        ])
    }

    private func writeIfRequested(_ value: String, paths: [String?]) throws {
        for path in paths.compactMap({ $0 }) {
            try value.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
        }
    }
}

private struct LiveDMAttachmentUser {
    let username: String
    let userId: String
    let token: String
    let identity: CryptoIdentity
    let sessionStore: SessionStore
    let accountStore: LocalAccountStore
    let x25519KeyManager: X25519KeyManager
}

private struct LiveDMAttachmentIdentityProvider: IdentityProviding {
    let identity: CryptoIdentity

    func loadOrCreate() throws -> CryptoIdentity {
        identity
    }
}

private final class LiveDMRecordingAttachmentService: AttachmentService, @unchecked Sendable {
    private let delegate: HTTPAttachmentService
    private(set) var uploadedBlobs: [Data] = []
    private(set) var firstUploadFile: URL?
    private(set) var uploadWriteError: Error?

    init(delegate: HTTPAttachmentService) {
        self.delegate = delegate
    }

    func upload(token: String, encryptedBlob: Data) async -> String? {
        uploadedBlobs.append(encryptedBlob)
        if firstUploadFile == nil {
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("live-dm-attachment-upload-\(UUID().uuidString).blob")
            do {
                try encryptedBlob.write(to: fileURL)
                firstUploadFile = fileURL
            } catch {
                uploadWriteError = error
            }
        }
        return await delegate.upload(token: token, encryptedBlob: encryptedBlob)
    }

    func download(token: String, attachmentId: String) async -> Data? {
        await delegate.download(token: token, attachmentId: attachmentId)
    }
}

private enum LiveDMAttachmentError: Error, CustomStringConvertible {
    case registrationFailed(String, String)
    case challengeFailed(String, String)
    case verifyFailed(String, String)
    case liveSubscriptionMissing
    case liveAttachmentMissing

    var description: String {
        switch self {
        case let .registrationFailed(username, result):
            return "Registration failed for \(username): \(result)"
        case let .challengeFailed(username, result):
            return "Challenge failed for \(username): \(result)"
        case let .verifyFailed(username, result):
            return "Verify failed for \(username): \(result)"
        case .liveSubscriptionMissing:
            return "Live DM subscription was not ready before timeout"
        case .liveAttachmentMissing:
            return "Live DM attachment did not render before timeout"
        }
    }
}
