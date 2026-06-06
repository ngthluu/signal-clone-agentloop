import CryptoKit
import Foundation
import XCTest
@testable import ChatApp

final class DMCoordinatorTests: XCTestCase {
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
    func testStartConversationRejectsPeerWithInvalidPrekeySignature() async throws {
        let harness = try makeHarness()
        let peerKey = Curve25519.KeyAgreement.PrivateKey()
        let peerIdentity = CryptoIdentity(privateKey: Curve25519.Signing.PrivateKey())
        let badSignature = MessageCrypto().signPrekey(
            x25519PublicKeyBase64: Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation.base64EncodedString(),
            with: peerIdentity
        )
        harness.service.prekeys["bob"] = PrekeyResponse(
            userId: "user-b",
            username: "bob",
            identityPublicKey: peerIdentity.publicKeyBase64,
            x25519PublicKey: peerKey.publicKey.rawRepresentation.base64EncodedString(),
            keySignature: badSignature
        )

        await harness.coordinator.startConversation(withUsername: "bob")

        XCTAssertEqual(harness.coordinator.statusMessage, "Could not verify bob's keys.")
        XCTAssertNil(harness.coordinator.peerUsername)
        XCTAssertEqual(harness.service.historyRequests.count, 0)
    }

    @MainActor
    func testStartConversationShowsUserNotFoundForMissingPeer() async throws {
        let harness = try makeHarness()

        await harness.coordinator.startConversation(withUsername: "missing")

        XCTAssertEqual(harness.coordinator.statusMessage, "User not found.")
        XCTAssertNil(harness.coordinator.peerUsername)
    }

    @MainActor
    func testOpenSelectedConversationLoadsEmptyDetailOnce() async throws {
        let harness = try makeHarness()
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        try configureVerifiedPeer(in: harness, username: "bob", userId: "user-b", recipientKey: recipient)

        await harness.coordinator.open(DirectConversationSelection(peerUserId: "user-b", peerUsername: "bob"))

        XCTAssertEqual(harness.coordinator.peerUsername, "bob")
        XCTAssertEqual(harness.coordinator.messages, [])
        XCTAssertEqual(harness.coordinator.detailState, .loaded(peerUsername: "bob", isEmpty: true))
        XCTAssertEqual(harness.service.historyRequests.map(\.username), ["bob"])
    }

    @MainActor
    func testOpenSelectedConversationReportsMissingAndInvalidStates() async throws {
        let missingHarness = try makeHarness()

        await missingHarness.coordinator.open(DirectConversationSelection(peerUserId: "user-missing", peerUsername: "missing"))

        XCTAssertEqual(missingHarness.coordinator.detailState, .failed(peerUsername: "missing", message: "User not found."))
        XCTAssertEqual(missingHarness.coordinator.messages, [])
        XCTAssertNil(missingHarness.coordinator.peerUsername)

        let invalidHarness = try makeHarness()
        let peerKey = Curve25519.KeyAgreement.PrivateKey()
        let peerIdentity = CryptoIdentity(privateKey: Curve25519.Signing.PrivateKey())
        let badSignature = MessageCrypto().signPrekey(
            x25519PublicKeyBase64: Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation.base64EncodedString(),
            with: peerIdentity
        )
        invalidHarness.service.prekeys["mallory"] = PrekeyResponse(
            userId: "user-m",
            username: "mallory",
            identityPublicKey: peerIdentity.publicKeyBase64,
            x25519PublicKey: peerKey.publicKey.rawRepresentation.base64EncodedString(),
            keySignature: badSignature
        )

        await invalidHarness.coordinator.open(DirectConversationSelection(peerUserId: "user-m", peerUsername: "mallory"))

        XCTAssertEqual(invalidHarness.coordinator.detailState, .failed(peerUsername: "mallory", message: "Could not verify mallory's keys."))
        XCTAssertEqual(invalidHarness.coordinator.messages, [])
        XCTAssertNil(invalidHarness.coordinator.peerUsername)
    }

    @MainActor
    func testOpenSelectedConversationIgnoresStaleHistoryRace() async throws {
        let harness = try makeHarness()
        let bobRecipient = Curve25519.KeyAgreement.PrivateKey()
        let carolRecipient = Curve25519.KeyAgreement.PrivateKey()
        try configureVerifiedPeer(in: harness, username: "bob", userId: "user-b", recipientKey: bobRecipient)
        try configureVerifiedPeer(in: harness, username: "carol", userId: "user-c", recipientKey: carolRecipient)
        let localPrivate = try harness.x25519.loadOrCreate()
        harness.service.histories["bob"] = [
            try encryptedRecord(id: "bob-1", senderId: "user-b", recipientId: "user-a", text: "late bob", localPrivate: localPrivate)
        ]
        harness.service.histories["carol"] = [
            try encryptedRecord(id: "carol-1", senderId: "user-c", recipientId: "user-a", text: "current carol", localPrivate: localPrivate)
        ]
        harness.service.historyDelays["bob"] = 250_000_000

        async let staleOpen: Void = harness.coordinator.open(DirectConversationSelection(peerUserId: "user-b", peerUsername: "bob"))
        try await Task.sleep(nanoseconds: 50_000_000)
        await harness.coordinator.open(DirectConversationSelection(peerUserId: "user-c", peerUsername: "carol"))
        _ = await staleOpen

        XCTAssertEqual(harness.coordinator.peerUsername, "carol")
        XCTAssertEqual(harness.coordinator.messages.map(\.id), ["carol-1"])
        XCTAssertEqual(harness.coordinator.messages.map(\.text), ["current carol"])
        XCTAssertEqual(harness.coordinator.detailState, .loaded(peerUsername: "carol", isEmpty: false))
    }

    @MainActor
    func testSendEncryptsCiphertextAndRecipientCanDecryptIt() async throws {
        let harness = try makeHarness()
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        try configureVerifiedPeer(in: harness, username: "bob", recipientKey: recipient)

        await harness.coordinator.startConversation(withUsername: "bob")
        await harness.coordinator.send(text: "hello bob")

        let sent = try XCTUnwrap(harness.service.sentMessages.last)
        XCTAssertEqual(sent.recipientUsername, "bob")
        XCTAssertNotEqual(sent.ciphertext, "hello bob")
        XCTAssertFalse(sent.ciphertext.contains("hello bob"))

        let decrypted = try MessageCrypto().decrypt(sent.ciphertext, withLocalX25519: recipient)
        XCTAssertEqual(String(decoding: decrypted, as: UTF8.self), "hello bob")
        XCTAssertEqual(harness.coordinator.messages.last?.text, "hello bob")
        XCTAssertEqual(harness.coordinator.messages.last?.isMine, true)
    }

    @MainActor
    func testSendAttachmentUploadsEncryptedBlobAndSendsEncryptedDescriptor() async throws {
        let harness = try makeHarness()
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        try configureVerifiedPeer(in: harness, username: "bob", recipientKey: recipient)
        let contentSentinel = "DM_ATTACHMENT_CONTENT_SENTINEL_\(UUID().uuidString)"
        let filenameSentinel = "DM_ATTACHMENT_FILENAME_SENTINEL_\(UUID().uuidString).bin"
        let fileBytes = Data([0x00, 0xFF, 0x42, 0x80])
            + Data(contentSentinel.utf8)
            + Data([0x13, 0x00, 0xFE])
        let mime = "application/x-chatapp-sentinel"

        await harness.coordinator.startConversation(withUsername: "bob")
        await harness.coordinator.sendAttachment(data: fileBytes, filename: filenameSentinel, mime: mime)

        let uploaded = try XCTUnwrap(harness.attachmentService.uploadedBlobs.last)
        XCTAssertNotEqual(uploaded, fileBytes)
        XCTAssertNil(uploaded.range(of: Data(contentSentinel.utf8)))

        let sent = try XCTUnwrap(harness.service.sentMessages.last)
        XCTAssertNoPlaintextSentinels(
            in: sent.ciphertext,
            filenameSentinel: filenameSentinel,
            contentSentinel: contentSentinel
        )
        let descriptorPlaintext = try MessageCrypto().decrypt(sent.ciphertext, withLocalX25519: recipient)
        let descriptor = try XCTUnwrap(AttachmentDescriptor.decode(descriptorPlaintext))
        XCTAssertEqual(descriptor.attachmentId, "attachment-1")
        XCTAssertEqual(descriptor.filename, filenameSentinel)
        XCTAssertEqual(descriptor.mime, mime)
        XCTAssertEqual(descriptor.size, fileBytes.count)
        let descriptorKey = try XCTUnwrap(Data(base64Encoded: descriptor.fileKey))
        XCTAssertEqual(descriptorKey.count, 32)
        XCTAssertEqual(try FileCrypto().decrypt(uploaded, using: SymmetricKey(data: descriptorKey)), fileBytes)
        XCTAssertEqual(harness.coordinator.messages.last?.attachment?.attachmentId, "attachment-1")
        XCTAssertEqual(harness.coordinator.messages.last?.attachment?.fileKey, descriptor.fileKey)
        XCTAssertEqual(harness.coordinator.messages.last?.attachment?.filename, filenameSentinel)
        XCTAssertEqual(harness.coordinator.messages.last?.attachment?.mime, mime)
        XCTAssertEqual(harness.coordinator.messages.last?.attachment?.size, fileBytes.count)
        XCTAssertEqual(harness.coordinator.messages.last?.text, filenameSentinel)
        let downloaded = await harness.coordinator.downloadAttachment(AttachmentInfo(descriptor: descriptor))
        XCTAssertEqual(downloaded, fileBytes)
    }

    @MainActor
    func testLoadHistoryDecryptsInboundRecordIntoDisplayMessages() async throws {
        let harness = try makeHarness()
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        try configureVerifiedPeer(in: harness, username: "bob", recipientKey: recipient)

        let localPrivate = try harness.x25519.loadOrCreate()
        let ciphertext = try MessageCrypto().encrypt(
            Data("hello alice".utf8),
            toRecipientX25519: localPrivate.publicKey.rawRepresentation.base64EncodedString()
        )
        harness.service.histories["bob"] = [
            MessageRecord(
                id: "msg-in",
                senderId: "user-b",
                recipientId: "user-a",
                ciphertext: ciphertext,
                createdAt: "2026-06-03T00:00:00Z"
            )
        ]

        await harness.coordinator.startConversation(withUsername: "bob")

        XCTAssertEqual(harness.coordinator.messages, [
            DisplayMessage(
                id: "msg-in",
                isMine: false,
                text: "hello alice",
                attachment: nil,
                createdAt: "2026-06-03T00:00:00Z"
            )
        ])
    }

    @MainActor
    func testLoadHistoryDetectsAttachmentDescriptorAndDownloadReturnsOriginalBytes() async throws {
        let harness = try makeHarness()
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        try configureVerifiedPeer(in: harness, username: "bob", recipientKey: recipient)
        let localPrivate = try harness.x25519.loadOrCreate()
        let contentSentinel = "DM_HISTORY_ATTACHMENT_CONTENT_SENTINEL_\(UUID().uuidString)"
        let filenameSentinel = "DM_HISTORY_ATTACHMENT_FILENAME_SENTINEL_\(UUID().uuidString).bin"
        let original = Data([0x00, 0xFF]) + Data(contentSentinel.utf8) + Data([0x80, 0x7F])
        let fileKey = FileCrypto().newFileKey()
        let encryptedBlob = try FileCrypto().encrypt(original, using: fileKey)
        harness.attachmentService.downloads["attachment-in"] = encryptedBlob
        let descriptor = AttachmentDescriptor(
            attachmentId: "attachment-in",
            fileKey: fileKey.withUnsafeBytes { Data($0).base64EncodedString() },
            filename: filenameSentinel,
            mime: "application/octet-stream",
            size: original.count
        )
        let attachmentCiphertext = try MessageCrypto().encrypt(
            descriptor.encodedJSON(),
            toRecipientX25519: localPrivate.publicKey.rawRepresentation.base64EncodedString()
        )
        XCTAssertNoPlaintextSentinels(
            in: attachmentCiphertext,
            filenameSentinel: filenameSentinel,
            contentSentinel: contentSentinel
        )
        harness.service.histories["bob"] = [
            MessageRecord(
                id: "msg-attachment",
                senderId: "user-b",
                recipientId: "user-a",
                ciphertext: attachmentCiphertext,
                createdAt: "2026-06-03T00:00:00Z"
            ),
            MessageRecord(
                id: "msg-text",
                senderId: "user-b",
                recipientId: "user-a",
                ciphertext: try MessageCrypto().encrypt(
                    Data("plain still works".utf8),
                    toRecipientX25519: localPrivate.publicKey.rawRepresentation.base64EncodedString()
                ),
                createdAt: "2026-06-03T00:01:00Z"
            )
        ]

        await harness.coordinator.startConversation(withUsername: "bob")

        XCTAssertEqual(harness.coordinator.messages.count, 2)
        let attachment = try XCTUnwrap(harness.coordinator.messages.first?.attachment)
        XCTAssertEqual(attachment.filename, filenameSentinel)
        XCTAssertEqual(attachment.mime, "application/octet-stream")
        XCTAssertEqual(attachment.size, original.count)
        XCTAssertEqual(attachment.fileKey, descriptor.fileKey)
        XCTAssertEqual(harness.coordinator.messages.first?.text, filenameSentinel)
        XCTAssertNil(harness.coordinator.messages.last?.attachment)
        XCTAssertEqual(harness.coordinator.messages.last?.text, "plain still works")
        let downloaded = await harness.coordinator.downloadAttachment(attachment)
        XCTAssertEqual(downloaded, original)
    }

    @MainActor
    func testSubscribeLiveDecryptsInboundRecordAndDedupesExistingMessages() async throws {
        let harness = try makeHarness()
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        try configureVerifiedPeer(in: harness, username: "bob", recipientKey: recipient)
        let localPrivate = try harness.x25519.loadOrCreate()
        let ciphertext = try MessageCrypto().encrypt(
            Data("hello live".utf8),
            toRecipientX25519: localPrivate.publicKey.rawRepresentation.base64EncodedString()
        )
        harness.service.liveRecords = [
            MessageRecord(
                id: "msg-live",
                senderId: "user-b",
                recipientId: "user-a",
                ciphertext: ciphertext,
                createdAt: "2026-06-03T00:00:00Z"
            ),
            MessageRecord(
                id: "msg-live",
                senderId: "user-b",
                recipientId: "user-a",
                ciphertext: ciphertext,
                createdAt: "2026-06-03T00:00:00Z"
            )
        ]

        await harness.coordinator.startConversation(withUsername: "bob")
        await harness.coordinator.subscribeLive()
        try await waitForMessages(in: harness, count: 1)

        XCTAssertEqual(harness.coordinator.messages, [
            DisplayMessage(
                id: "msg-live",
                isMine: false,
                text: "hello live",
                attachment: nil,
                createdAt: "2026-06-03T00:00:00Z"
            )
        ])
    }

    @MainActor
    func testSubscribeLiveIgnoresNonSelectedConversationAndDuplicateIds() async throws {
        let harness = try makeHarness()
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        try configureVerifiedPeer(in: harness, username: "bob", userId: "user-b", recipientKey: recipient)
        let localPrivate = try harness.x25519.loadOrCreate()

        await harness.coordinator.open(DirectConversationSelection(peerUserId: "user-b", peerUsername: "bob"))
        try await harness.service.waitForLiveSubscription()

        harness.service.yieldLive(MessageRecord(
            id: "bad-ciphertext",
            senderId: "user-b",
            recipientId: "user-a",
            ciphertext: "not-base64",
            createdAt: "2026-06-03T00:00:00Z"
        ))
        harness.service.yieldLive(try encryptedRecord(
            id: "carol-live",
            senderId: "user-c",
            recipientId: "user-a",
            text: "wrong peer",
            localPrivate: localPrivate
        ))
        harness.service.yieldLive(try encryptedRecord(
            id: "wrong-recipient",
            senderId: "user-b",
            recipientId: "user-z",
            text: "wrong recipient",
            localPrivate: localPrivate
        ))
        harness.service.yieldLive(try encryptedRecord(
            id: "bob-live",
            senderId: "user-b",
            recipientId: "user-a",
            text: "right peer",
            localPrivate: localPrivate
        ))
        harness.service.yieldLive(try encryptedRecord(
            id: "bob-live",
            senderId: "user-b",
            recipientId: "user-a",
            text: "duplicate",
            localPrivate: localPrivate
        ))
        try await waitForMessages(in: harness, count: 1)

        XCTAssertEqual(harness.coordinator.messages.map(\.id), ["bob-live"])
        XCTAssertEqual(harness.coordinator.messages.map(\.text), ["right peer"])
        XCTAssertEqual(harness.coordinator.detailState, .loaded(peerUsername: "bob", isEmpty: false))
    }

    @MainActor
    func testSubscribeLiveDeliversAttachmentDisplayDedupesAndDownloadsOriginalBytes() async throws {
        let harness = try makeHarness()
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        try configureVerifiedPeer(in: harness, username: "bob", recipientKey: recipient)
        let localPrivate = try harness.x25519.loadOrCreate()
        let contentSentinel = "DM_LIVE_ATTACHMENT_CONTENT_SENTINEL_\(UUID().uuidString)"
        let filenameSentinel = "DM_LIVE_ATTACHMENT_FILENAME_SENTINEL_\(UUID().uuidString).pdf"
        let original = Data([0xCA, 0xFE]) + Data(contentSentinel.utf8) + Data([0x00, 0x81])
        let fileKey = FileCrypto().newFileKey()
        let encryptedBlob = try FileCrypto().encrypt(original, using: fileKey)
        harness.attachmentService.downloads["attachment-live"] = encryptedBlob
        let descriptor = AttachmentDescriptor(
            attachmentId: "attachment-live",
            fileKey: fileKey.withUnsafeBytes { Data($0).base64EncodedString() },
            filename: filenameSentinel,
            mime: "application/pdf",
            size: original.count
        )
        let attachmentCiphertext = try MessageCrypto().encrypt(
            descriptor.encodedJSON(),
            toRecipientX25519: localPrivate.publicKey.rawRepresentation.base64EncodedString()
        )
        XCTAssertNoPlaintextSentinels(
            in: attachmentCiphertext,
            filenameSentinel: filenameSentinel,
            contentSentinel: contentSentinel
        )
        let liveRecord = MessageRecord(
            id: "msg-live-attachment",
            senderId: "user-b",
            recipientId: "user-a",
            ciphertext: attachmentCiphertext,
            createdAt: "2026-06-03T00:00:00Z"
        )

        await harness.coordinator.startConversation(withUsername: "bob")
        try await harness.service.waitForLiveSubscription()

        harness.service.yieldLive(liveRecord)
        try await waitForMessages(in: harness, count: 1)

        let display = try XCTUnwrap(harness.coordinator.messages.first)
        let attachment = try XCTUnwrap(display.attachment)
        XCTAssertEqual(display.id, "msg-live-attachment")
        XCTAssertEqual(display.isMine, false)
        XCTAssertEqual(display.text, filenameSentinel)
        XCTAssertFalse(UUID(uuidString: display.text) != nil, "Attachment display text should be the legible filename, not a raw UUID.")
        XCTAssertEqual(attachment.attachmentId, "attachment-live")
        XCTAssertEqual(attachment.filename, filenameSentinel)
        XCTAssertEqual(attachment.mime, "application/pdf")
        XCTAssertEqual(attachment.size, original.count)
        XCTAssertEqual(attachment.fileKey, descriptor.fileKey)

        harness.service.yieldLive(liveRecord)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(harness.coordinator.messages.count, 1)

        let downloaded = await harness.coordinator.downloadAttachment(attachment)
        XCTAssertEqual(downloaded, original)
    }

    @MainActor
    func testSubscribeLiveCatchesUpOfflineHistoryInServerOrderAndDedupesSSE() async throws {
        let harness = try makeHarness()
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        try configureVerifiedPeer(in: harness, username: "bob", recipientKey: recipient)
        let localPrivate = try harness.x25519.loadOrCreate()

        await harness.coordinator.startConversation(withUsername: "bob")
        XCTAssertEqual(harness.coordinator.messages, [])

        var offlineRecords: [MessageRecord] = []
        for (index, text) in ["one", "two", "three"].enumerated() {
            let ciphertext = try MessageCrypto().encrypt(
                Data(text.utf8),
                toRecipientX25519: localPrivate.publicKey.rawRepresentation.base64EncodedString()
            )
            offlineRecords.append(MessageRecord(
                id: "offline-\(index + 1)",
                senderId: "user-b",
                recipientId: "user-a",
                ciphertext: ciphertext,
                createdAt: "2026-06-03T00:00:00Z"
            ))
        }
        harness.service.histories["bob"] = offlineRecords
        harness.service.liveRecords = [offlineRecords[1], offlineRecords[2]]

        await harness.coordinator.subscribeLive()
        try await waitForMessages(in: harness, count: 3)

        XCTAssertEqual(harness.coordinator.messages.map(\.id), ["offline-1", "offline-2", "offline-3"])
        XCTAssertEqual(harness.coordinator.messages.map(\.text), ["one", "two", "three"])
        XCTAssertEqual(Set(harness.coordinator.messages.map(\.id)).count, 3)
        XCTAssertGreaterThanOrEqual(harness.service.historyRequests.filter { $0.username == "bob" }.count, 2)
    }

    @MainActor
    func testPublicSubscribeLiveCatchesUpSelectedConversationWithoutReplacingExistingMessages() async throws {
        let harness = try makeHarness()
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        try configureVerifiedPeer(in: harness, username: "bob", userId: "user-b", recipientKey: recipient)
        let localPrivate = try harness.x25519.loadOrCreate()
        let existing = try encryptedRecord(
            id: "existing",
            senderId: "user-b",
            recipientId: "user-a",
            text: "existing",
            localPrivate: localPrivate
        )
        let offline = try encryptedRecord(
            id: "offline",
            senderId: "user-b",
            recipientId: "user-a",
            text: "offline",
            localPrivate: localPrivate
        )
        harness.service.histories["bob"] = [existing]

        await harness.coordinator.open(DirectConversationSelection(peerUserId: "user-b", peerUsername: "bob"))
        XCTAssertEqual(harness.coordinator.messages.map(\.id), ["existing"])

        harness.service.histories["bob"] = [existing, offline]
        await harness.coordinator.subscribeLive()
        try await waitForMessages(in: harness, count: 2)

        XCTAssertEqual(harness.coordinator.messages.map(\.id), ["existing", "offline"])
        XCTAssertEqual(harness.coordinator.messages.map(\.text), ["existing", "offline"])
        XCTAssertEqual(Set(harness.coordinator.messages.map(\.id)).count, 2)
    }

    @MainActor
    func testCancelLiveSubscriptionCancelsWithoutRemovingMessages() async throws {
        let harness = try makeHarness()
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        try configureVerifiedPeer(in: harness, username: "bob", recipientKey: recipient)

        await harness.coordinator.startConversation(withUsername: "bob")
        harness.coordinator.cancelLiveSubscription()

        XCTAssertEqual(harness.coordinator.messages, [])
    }

    @MainActor
    private func makeHarness() throws -> Harness {
        let sessionKeychain = KeychainStore(
            service: "\(KeychainStore.defaultService).dm.tests.\(UUID().uuidString)",
            account: "\(KeychainStore.defaultAccount).session.tests",
            usesDataProtectionKeychain: false
        )
        let x25519Keychain = KeychainStore(
            service: "\(KeychainStore.defaultService).dm.tests.\(UUID().uuidString)",
            account: "\(KeychainStore.defaultAccount).x25519.tests",
            usesDataProtectionKeychain: false
        )
        keychainStores.append(sessionKeychain)
        keychainStores.append(x25519Keychain)

        let sessionStore = SessionStore(keychainStore: sessionKeychain)
        try sessionStore.save("token-1")

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dm-coordinator-\(UUID().uuidString)", isDirectory: true)
        cleanupURLs.append(directory)
        let accountStore = LocalAccountStore(directory: directory)
        let identity = CryptoIdentity(privateKey: Curve25519.Signing.PrivateKey())
        try accountStore.save(LocalAccount(username: "alice", publicKeyBase64: identity.publicKeyBase64, userId: "user-a"))

        let x25519 = X25519KeyManager(keychainStore: x25519Keychain)
        let service = FakeMessageService()
        let attachmentService = FakeAttachmentService()
        let coordinator = DMCoordinator(
            identityProvider: StubIdentityProvider(identity: identity),
            x25519KeyManager: x25519,
            sessionStore: sessionStore,
            accountStore: accountStore,
            service: service,
            crypto: MessageCrypto(),
            attachmentService: attachmentService,
            fileCrypto: FileCrypto()
        )
        return Harness(coordinator: coordinator, service: service, attachmentService: attachmentService, x25519: x25519)
    }

    @MainActor
    private func configureVerifiedPeer(
        in harness: Harness,
        username: String,
        userId: String = "user-b",
        recipientKey: Curve25519.KeyAgreement.PrivateKey
    ) throws {
        let identity = CryptoIdentity(privateKey: Curve25519.Signing.PrivateKey())
        let x25519PublicKey = recipientKey.publicKey.rawRepresentation.base64EncodedString()
        let signature = MessageCrypto().signPrekey(x25519PublicKeyBase64: x25519PublicKey, with: identity)
        harness.service.prekeys[username] = PrekeyResponse(
            userId: userId,
            username: username,
            identityPublicKey: identity.publicKeyBase64,
            x25519PublicKey: x25519PublicKey,
            keySignature: signature
        )
    }

    @MainActor
    private func waitForMessages(in harness: Harness, count: Int) async throws {
        for _ in 0..<20 {
            if harness.coordinator.messages.count == count {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func XCTAssertNoPlaintextSentinels(
        in ciphertext: String,
        filenameSentinel: String,
        contentSentinel: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(ciphertext.contains(filenameSentinel), file: file, line: line)
        XCTAssertFalse(ciphertext.contains(contentSentinel), file: file, line: line)
        if let ciphertextBytes = Data(base64Encoded: ciphertext) {
            XCTAssertNil(ciphertextBytes.range(of: Data(filenameSentinel.utf8)), file: file, line: line)
            XCTAssertNil(ciphertextBytes.range(of: Data(contentSentinel.utf8)), file: file, line: line)
        } else {
            XCTFail("DM ciphertext should be base64.", file: file, line: line)
        }
    }

    private func encryptedRecord(
        id: String,
        senderId: String,
        recipientId: String,
        text: String,
        localPrivate: Curve25519.KeyAgreement.PrivateKey,
        createdAt: String = "2026-06-03T00:00:00Z"
    ) throws -> MessageRecord {
        MessageRecord(
            id: id,
            senderId: senderId,
            recipientId: recipientId,
            ciphertext: try MessageCrypto().encrypt(
                Data(text.utf8),
                toRecipientX25519: localPrivate.publicKey.rawRepresentation.base64EncodedString()
            ),
            createdAt: createdAt
        )
    }
}

private struct Harness {
    let coordinator: DMCoordinator
    let service: FakeMessageService
    let attachmentService: FakeAttachmentService
    let x25519: X25519KeyManager
}

private struct StubIdentityProvider: IdentityProviding {
    let identity: CryptoIdentity

    func loadOrCreate() throws -> CryptoIdentity {
        identity
    }
}

private final class FakeMessageService: MessageService, @unchecked Sendable {
    var prekeys: [String: PrekeyResponse] = [:]
    var histories: [String: [MessageRecord]] = [:]
    var liveRecords: [MessageRecord] = []
    var liveContinuation: AsyncThrowingStream<MessageRecord, Error>.Continuation?
    var liveSubscriptionWaiter: CheckedContinuation<Void, Never>?
    var sentMessages: [(recipientUsername: String, ciphertext: String)] = []
    var historyRequests: [(username: String, since: String?)] = []
    var historyDelays: [String: UInt64] = [:]

    func publishPrekey(token: String, x25519PublicKey: String, signature: String) async -> Bool {
        true
    }

    func fetchPrekey(username: String, token: String) async -> PrekeyResponse? {
        prekeys[username]
    }

    func send(token: String, recipientUsername: String, ciphertext: String) async -> SendMessageResult {
        sentMessages.append((recipientUsername: recipientUsername, ciphertext: ciphertext))
        return .success(messageId: "msg-\(sentMessages.count)", createdAt: "2026-06-03T00:00:00Z")
    }

    func history(token: String, withUsername username: String, since: String?) async -> [MessageRecord] {
        historyRequests.append((username: username, since: since))
        if let delay = historyDelays[username] {
            try? await Task.sleep(nanoseconds: delay)
        }
        return histories[username] ?? []
    }

    func inbox(token: String, since: Int) async -> InboxPage {
        InboxPage(messages: [], nextCursor: nil)
    }

    func conversations(token: String) async -> [ConversationSummary] {
        []
    }

    func liveMessages(token: String) -> AsyncThrowingStream<MessageRecord, Error> {
        AsyncThrowingStream { continuation in
            liveContinuation = continuation
            liveSubscriptionWaiter?.resume()
            liveSubscriptionWaiter = nil
            for record in liveRecords {
                continuation.yield(record)
            }
            if !liveRecords.isEmpty {
                continuation.finish()
            }
        }
    }

    func waitForLiveSubscription() async throws {
        if liveContinuation != nil {
            return
        }
        await withCheckedContinuation { continuation in
            liveSubscriptionWaiter = continuation
        }
    }

    func yieldLive(_ record: MessageRecord) {
        liveContinuation?.yield(record)
    }
}

private final class FakeAttachmentService: AttachmentService, @unchecked Sendable {
    var uploadedBlobs: [Data] = []
    var downloads: [String: Data] = [:]

    func upload(token: String, encryptedBlob: Data) async -> String? {
        uploadedBlobs.append(encryptedBlob)
        let id = "attachment-\(uploadedBlobs.count)"
        downloads[id] = encryptedBlob
        return id
    }

    func download(token: String, attachmentId: String) async -> Data? {
        downloads[attachmentId]
    }
}
