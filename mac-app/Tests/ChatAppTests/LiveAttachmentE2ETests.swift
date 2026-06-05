import CryptoKit
import Foundation
import XCTest
@testable import ChatApp

final class LiveAttachmentE2ETests: XCTestCase {
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
    func testLiveAttachmentDMAndGroupRoundTripStoresOnlyCiphertext() async throws {
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
        let attachmentService = HTTPAttachmentService(baseURL: backendURL)
        let recordingAttachmentService = RecordingAttachmentService(delegate: attachmentService)

        let alice = try await makeLiveUser(
            prefix: "att_a",
            registrationClient: registrationClient,
            authClient: authClient,
            messageService: messageService
        )
        let bob = try await makeLiveUser(
            prefix: "att_b",
            registrationClient: registrationClient,
            authClient: authClient,
            messageService: messageService
        )
        let carol = try await makeLiveUser(
            prefix: "att_c",
            registrationClient: registrationClient,
            authClient: authClient,
            messageService: messageService
        )

        let sentinel = "ATTACHMENT_PLAINTEXT_SENTINEL_\(UUID().uuidString)"
        let original = Data([0x00, 0xFF, 0x41]) + Data("live attachment \(sentinel) bytes".utf8)
        let originalFile = try writeOriginalFile(original, filename: "live-attachment.txt")

        let aliceDM = makeDMCoordinator(
            for: alice,
            messageService: messageService,
            attachmentService: recordingAttachmentService
        )
        await aliceDM.startConversation(withUsername: bob.username)
        await aliceDM.sendAttachment(data: original, filename: "live-attachment.txt", mime: "text/plain")

        let dmAttachment = try XCTUnwrap(aliceDM.messages.last?.attachment)
        let dmUploadBlob = try XCTUnwrap(recordingAttachmentService.uploadedBlobs.first)
        XCTAssertNotEqual(dmUploadBlob, original)
        XCTAssertFalse(String(decoding: dmUploadBlob, as: UTF8.self).contains(sentinel))
        XCTAssertThrowsError(try FileCrypto().decrypt(dmUploadBlob, using: FileCrypto().newFileKey()))

        let bobDM = makeDMCoordinator(for: bob, messageService: messageService, attachmentService: attachmentService)
        await bobDM.startConversation(withUsername: alice.username)
        let inboundDMAttachment = try XCTUnwrap(bobDM.messages.first(where: { $0.attachment != nil })?.attachment)
        XCTAssertEqual(inboundDMAttachment.attachmentId, dmAttachment.attachmentId)
        let downloadedDM = await bobDM.downloadAttachment(inboundDMAttachment)
        XCTAssertEqual(downloadedDM, original)

        let wrongKeyDM = AttachmentInfo(
            descriptor: AttachmentDescriptor(
                attachmentId: inboundDMAttachment.attachmentId,
                fileKey: FileCrypto().newFileKey().withUnsafeBytes { Data($0).base64EncodedString() },
                filename: inboundDMAttachment.filename,
                mime: inboundDMAttachment.mime,
                size: inboundDMAttachment.size
            )
        )
        let wrongKeyDMDownload = await bobDM.downloadAttachment(wrongKeyDM)
        XCTAssertNil(wrongKeyDMDownload)

        let aliceGroup = makeGroupCoordinator(
            for: alice,
            messageService: messageService,
            groupService: groupService,
            attachmentService: recordingAttachmentService
        )
        await aliceGroup.createGroup(name: "Live Attachments \(UUID().uuidString)", memberUsernames: [bob.username, carol.username])
        let groupId = try XCTUnwrap(aliceGroup.groupId)
        await aliceGroup.sendAttachment(data: original, filename: "live-group-attachment.txt", mime: "text/plain")

        let groupAttachment = try XCTUnwrap(aliceGroup.messages.last?.attachment)
        let groupUploadBlob = try XCTUnwrap(recordingAttachmentService.uploadedBlobs.dropFirst().first)
        XCTAssertNotEqual(groupUploadBlob, original)
        XCTAssertFalse(String(decoding: groupUploadBlob, as: UTF8.self).contains(sentinel))
        XCTAssertThrowsError(try FileCrypto().decrypt(groupUploadBlob, using: FileCrypto().newFileKey()))

        let bobGroup = makeGroupCoordinator(
            for: bob,
            messageService: messageService,
            groupService: groupService,
            attachmentService: attachmentService
        )
        await bobGroup.openGroup(id: groupId)
        let inboundGroupAttachment = try XCTUnwrap(bobGroup.messages.first(where: { $0.attachment != nil })?.attachment)
        XCTAssertEqual(inboundGroupAttachment.attachmentId, groupAttachment.attachmentId)
        let downloadedGroup = await bobGroup.downloadAttachment(inboundGroupAttachment)
        XCTAssertEqual(downloadedGroup, original)

        try writeProofArtifacts(
            sentinel: sentinel,
            originalFile: originalFile,
            dmAttachmentId: dmAttachment.attachmentId,
            groupAttachmentId: groupAttachment.attachmentId,
            bobToken: bob.token,
            uploadWireFile: recordingAttachmentService.firstUploadFile
        )
    }

    @MainActor
    func testAlreadySubscribedRecipientReceivesLiveAttachmentsAndWritesByteIdenticalDownloads() async throws {
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
        let attachmentService = HTTPAttachmentService(baseURL: backendURL)

        let alice = try await makeLiveUser(
            prefix: "att_live_a",
            registrationClient: registrationClient,
            authClient: authClient,
            messageService: messageService
        )
        let bob = try await makeLiveUser(
            prefix: "att_live_b",
            registrationClient: registrationClient,
            authClient: authClient,
            messageService: messageService
        )
        let carol = try await makeLiveUser(
            prefix: "att_live_c",
            registrationClient: registrationClient,
            authClient: authClient,
            messageService: messageService
        )

        let original = Data([0x7F, 0x00, 0xCA, 0xFE]) + Data("live-stream attachment \(UUID().uuidString) bytes".utf8)
        let originalFile = try writeOriginalFile(original, filename: "live-stream-original.bin")

        let aliceDM = makeDMCoordinator(for: alice, messageService: messageService, attachmentService: attachmentService)
        let bobDM = makeDMCoordinator(for: bob, messageService: messageService, attachmentService: attachmentService)
        await aliceDM.startConversation(withUsername: bob.username)
        await bobDM.startConversation(withUsername: alice.username)
        try await Task.sleep(nanoseconds: 250_000_000)

        await aliceDM.sendAttachment(data: original, filename: "live-dm.bin", mime: "application/octet-stream")
        let liveDMAttachment = try await waitForDMAttachment(
            in: bobDM,
            filename: "live-dm.bin",
            timeoutNanoseconds: 5_000_000_000
        )
        XCTAssertEqual(liveDMAttachment.text, "live-dm.bin")
        XCTAssertFalse(liveDMAttachment.isMine)
        let dmInfo = try XCTUnwrap(liveDMAttachment.attachment)
        XCTAssertEqual(dmInfo.filename, "live-dm.bin")
        XCTAssertEqual(dmInfo.size, original.count)
        let downloadedDMOptional = await bobDM.downloadAttachment(dmInfo)
        let downloadedDM = try XCTUnwrap(downloadedDMOptional)
        let downloadedDMFile = try writeDownloadedFile(downloadedDM, filename: "live-dm-downloaded.bin")
        XCTAssertEqual(try Data(contentsOf: downloadedDMFile), try Data(contentsOf: originalFile))

        let aliceGroup = makeGroupCoordinator(
            for: alice,
            messageService: messageService,
            groupService: groupService,
            attachmentService: attachmentService
        )
        let bobGroup = makeGroupCoordinator(
            for: bob,
            messageService: messageService,
            groupService: groupService,
            attachmentService: attachmentService
        )
        await aliceGroup.createGroup(name: "Live Attachment Stream \(UUID().uuidString)", memberUsernames: [bob.username, carol.username])
        let groupId = try XCTUnwrap(aliceGroup.groupId)
        await bobGroup.openGroup(id: groupId)
        try await Task.sleep(nanoseconds: 250_000_000)

        await aliceGroup.sendAttachment(data: original, filename: "live-group.bin", mime: "application/octet-stream")
        let liveGroupAttachment = try await waitForGroupAttachment(
            in: bobGroup,
            filename: "live-group.bin",
            timeoutNanoseconds: 5_000_000_000
        )
        XCTAssertEqual(liveGroupAttachment.text, "live-group.bin")
        XCTAssertFalse(liveGroupAttachment.isMine)
        XCTAssertEqual(liveGroupAttachment.senderName, alice.username)
        XCTAssertNil(UUID(uuidString: liveGroupAttachment.senderName), "Group live attachment sender should render as a username, not a raw UUID.")
        let groupInfo = try XCTUnwrap(liveGroupAttachment.attachment)
        XCTAssertEqual(groupInfo.filename, "live-group.bin")
        XCTAssertEqual(groupInfo.size, original.count)
        let downloadedGroupOptional = await bobGroup.downloadAttachment(groupInfo)
        let downloadedGroup = try XCTUnwrap(downloadedGroupOptional)
        let downloadedGroupFile = try writeDownloadedFile(downloadedGroup, filename: "live-group-downloaded.bin")
        XCTAssertEqual(try Data(contentsOf: downloadedGroupFile), try Data(contentsOf: originalFile))

        try writeLiveDownloadProofArtifacts(
            originalFile: originalFile,
            dmDownloadedFile: downloadedDMFile,
            groupDownloadedFile: downloadedGroupFile
        )
    }

    @MainActor
    private func makeLiveUser(
        prefix: String,
        registrationClient: HTTPRegistrationClient,
        authClient: HTTPAuthClient,
        messageService: HTTPMessageService
    ) async throws -> LiveAttachmentUser {
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
            throw LiveAttachmentError.registrationFailed(username, "\(registration)")
        }

        let token = try await signIn(username: username, identity: identity, authClient: authClient)
        let signature = MessageCrypto().signPrekey(
            x25519PublicKeyBase64: x25519PrivateKey.publicKey.rawRepresentation.base64EncodedString(),
            with: identity
        )
        let published = await messageService.publishPrekey(
            token: token,
            x25519PublicKey: x25519PrivateKey.publicKey.rawRepresentation.base64EncodedString(),
            signature: signature
        )
        XCTAssertTrue(published)

        let sessionKeychain = KeychainStore(
            service: "\(KeychainStore.defaultService).live.attachments.\(UUID().uuidString)",
            account: "\(KeychainStore.defaultAccount).session",
            usesDataProtectionKeychain: false
        )
        let x25519Keychain = KeychainStore(
            service: "\(KeychainStore.defaultService).live.attachments.\(UUID().uuidString)",
            account: "\(KeychainStore.defaultAccount).x25519",
            usesDataProtectionKeychain: false
        )
        keychainStores.append(sessionKeychain)
        keychainStores.append(x25519Keychain)

        let sessionStore = SessionStore(keychainStore: sessionKeychain)
        try sessionStore.save(token)
        try x25519Keychain.save(x25519PrivateKey.rawRepresentation)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("live-attachment-account-\(UUID().uuidString)", isDirectory: true)
        cleanupURLs.append(directory)
        let accountStore = LocalAccountStore(directory: directory)
        try accountStore.save(LocalAccount(username: username, publicKeyBase64: identity.publicKeyBase64, userId: userId))

        return LiveAttachmentUser(
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
            throw LiveAttachmentError.challengeFailed(username, "\(challenge)")
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
            throw LiveAttachmentError.verifyFailed(username, "\(verification)")
        }
    }

    @MainActor
    private func makeDMCoordinator(
        for user: LiveAttachmentUser,
        messageService: HTTPMessageService,
        attachmentService: AttachmentService
    ) -> DMCoordinator {
        DMCoordinator(
            identityProvider: LiveAttachmentIdentityProvider(identity: user.identity),
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
    private func makeGroupCoordinator(
        for user: LiveAttachmentUser,
        messageService: HTTPMessageService,
        groupService: HTTPGroupService,
        attachmentService: AttachmentService
    ) -> GroupCoordinator {
        GroupCoordinator(
            identityProvider: LiveAttachmentIdentityProvider(identity: user.identity),
            x25519KeyManager: user.x25519KeyManager,
            sessionStore: user.sessionStore,
            accountStore: user.accountStore,
            messageService: messageService,
            groupService: groupService,
            crypto: GroupCrypto(),
            attachmentService: attachmentService,
            fileCrypto: FileCrypto()
        )
    }

    private func writeOriginalFile(_ data: Data, filename: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("live-attachment-proof-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileURL = directory.appendingPathComponent(filename)
        try data.write(to: fileURL)
        return fileURL
    }

    private func writeDownloadedFile(_ data: Data, filename: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("live-attachment-download-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileURL = directory.appendingPathComponent(filename)
        try data.write(to: fileURL)
        return fileURL
    }

    @MainActor
    private func waitForDMAttachment(
        in coordinator: DMCoordinator,
        filename: String,
        timeoutNanoseconds: UInt64
    ) async throws -> DisplayMessage {
        try await waitForAttachment(timeoutNanoseconds: timeoutNanoseconds) {
            coordinator.messages.first { $0.attachment != nil && $0.text == filename }
        }
    }

    @MainActor
    private func waitForGroupAttachment(
        in coordinator: GroupCoordinator,
        filename: String,
        timeoutNanoseconds: UInt64
    ) async throws -> DisplayGroupMessage {
        try await waitForAttachment(timeoutNanoseconds: timeoutNanoseconds) {
            coordinator.messages.first { $0.attachment != nil && $0.text == filename }
        }
    }

    @MainActor
    private func waitForAttachment<T>(
        timeoutNanoseconds: UInt64,
        lookup: () -> T?
    ) async throws -> T {
        let pollInterval: UInt64 = 100_000_000
        let attempts = max(1, Int(timeoutNanoseconds / pollInterval))
        for _ in 0..<attempts {
            if let value = lookup() {
                return value
            }
            try await Task.sleep(nanoseconds: pollInterval)
        }
        throw LiveAttachmentError.liveAttachmentMissing
    }

    private func writeProofArtifacts(
        sentinel: String,
        originalFile: URL,
        dmAttachmentId: String,
        groupAttachmentId: String,
        bobToken: String,
        uploadWireFile: URL?
    ) throws {
        let environment = ProcessInfo.processInfo.environment
        try writeIfRequested(sentinel, path: environment["CHATAPP_ATTACHMENT_SENTINEL_OUT"])
        try writeIfRequested(originalFile.path, path: environment["CHATAPP_ATTACHMENT_ORIGINAL_FILE_OUT"])
        try writeIfRequested(dmAttachmentId, path: environment["CHATAPP_ATTACHMENT_DM_ID_OUT"])
        try writeIfRequested(groupAttachmentId, path: environment["CHATAPP_ATTACHMENT_GROUP_ID_OUT"])
        try writeIfRequested(bobToken, path: environment["CHATAPP_ATTACHMENT_BOB_TOKEN_OUT"])
        if let uploadWireFile {
            try writeIfRequested(uploadWireFile.path, path: environment["CHATAPP_ATTACHMENT_UPLOAD_WIRE_FILE_OUT"])
        }
    }

    private func writeLiveDownloadProofArtifacts(
        originalFile: URL,
        dmDownloadedFile: URL,
        groupDownloadedFile: URL
    ) throws {
        let environment = ProcessInfo.processInfo.environment
        try writeIfRequested(originalFile.path, path: environment["CHATAPP_ATTACHMENT_LIVE_ORIGINAL_FILE_OUT"])
        try writeIfRequested(dmDownloadedFile.path, path: environment["CHATAPP_ATTACHMENT_LIVE_DM_DOWNLOAD_OUT"])
        try writeIfRequested(groupDownloadedFile.path, path: environment["CHATAPP_ATTACHMENT_LIVE_GROUP_DOWNLOAD_OUT"])
    }

    private func writeIfRequested(_ value: String, path: String?) throws {
        guard let path else {
            return
        }
        try value.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
    }
}

private struct LiveAttachmentUser {
    let username: String
    let userId: String
    let token: String
    let identity: CryptoIdentity
    let sessionStore: SessionStore
    let accountStore: LocalAccountStore
    let x25519KeyManager: X25519KeyManager
}

private struct LiveAttachmentIdentityProvider: IdentityProviding {
    let identity: CryptoIdentity

    func loadOrCreate() throws -> CryptoIdentity {
        identity
    }
}

private final class RecordingAttachmentService: AttachmentService, @unchecked Sendable {
    private let delegate: HTTPAttachmentService
    private(set) var uploadedBlobs: [Data] = []
    private(set) var firstUploadFile: URL?

    init(delegate: HTTPAttachmentService) {
        self.delegate = delegate
    }

    func upload(token: String, encryptedBlob: Data) async -> String? {
        uploadedBlobs.append(encryptedBlob)
        if firstUploadFile == nil {
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("live-attachment-upload-\(UUID().uuidString).blob")
            try? encryptedBlob.write(to: fileURL)
            firstUploadFile = fileURL
        }
        return await delegate.upload(token: token, encryptedBlob: encryptedBlob)
    }

    func download(token: String, attachmentId: String) async -> Data? {
        await delegate.download(token: token, attachmentId: attachmentId)
    }
}

private enum LiveAttachmentError: Error, CustomStringConvertible {
    case registrationFailed(String, String)
    case challengeFailed(String, String)
    case verifyFailed(String, String)
    case liveAttachmentMissing

    var description: String {
        switch self {
        case let .registrationFailed(username, result):
            return "Registration failed for \(username): \(result)"
        case let .challengeFailed(username, result):
            return "Challenge failed for \(username): \(result)"
        case let .verifyFailed(username, result):
            return "Verify failed for \(username): \(result)"
        case .liveAttachmentMissing:
            return "Live attachment did not render before timeout"
        }
    }
}
