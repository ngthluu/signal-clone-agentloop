import CryptoKit
import Foundation
import XCTest
@testable import ChatApp

final class GroupCoordinatorTests: XCTestCase {
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
    func testCreateGroupRequiresAtLeastTwoInvitedMembers() async throws {
        let harness = try makeHarness()
        let bobKey = Curve25519.KeyAgreement.PrivateKey()
        try harness.addVerifiedPrekey(username: "bob", userId: "user-b", key: bobKey)

        await harness.coordinator.createGroup(name: "Ops", memberUsernames: [])
        XCTAssertEqual(harness.coordinator.statusMessage, "Add at least two other members.")
        XCTAssertTrue(harness.groupService.createRequests.isEmpty)

        await harness.coordinator.createGroup(name: "Ops", memberUsernames: ["bob"])
        XCTAssertEqual(harness.coordinator.statusMessage, "Add at least two other members.")
        XCTAssertTrue(harness.groupService.createRequests.isEmpty)
    }

    @MainActor
    func testCreateGroupWrapsEpochZeroKeyToCreatorAndTwoInvitees() async throws {
        let harness = try makeHarness()
        let bobKey = Curve25519.KeyAgreement.PrivateKey()
        let carolKey = Curve25519.KeyAgreement.PrivateKey()
        try harness.addVerifiedPrekey(username: "bob", userId: "user-b", key: bobKey)
        try harness.addVerifiedPrekey(username: "carol", userId: "user-c", key: carolKey)

        await harness.coordinator.createGroup(name: " Ops ", memberUsernames: ["bob", "carol", "bob", "alice"])

        let request = try XCTUnwrap(harness.groupService.createRequests.last)
        XCTAssertEqual(request.name, "Ops")
        XCTAssertEqual(request.members.count, 3)
        XCTAssertEqual(request.members.map(\.username).sorted(), ["alice", "bob", "carol"])
        let byUsername = Dictionary(uniqueKeysWithValues: request.members.map { ($0.username, $0.wrappedKey) })
        let localPrivate = try harness.x25519.loadOrCreate()
        let aliceGK = try GroupCrypto().unwrapGroupKey(try XCTUnwrap(byUsername["alice"]), withLocalX25519: localPrivate)
        let bobGK = try GroupCrypto().unwrapGroupKey(try XCTUnwrap(byUsername["bob"]), withLocalX25519: bobKey)
        let carolGK = try GroupCrypto().unwrapGroupKey(try XCTUnwrap(byUsername["carol"]), withLocalX25519: carolKey)
        XCTAssertEqual(aliceGK, bobGK)
        XCTAssertEqual(aliceGK, carolGK)

        let ciphertext = try GroupCrypto().encryptGroupMessage(Data("hello group".utf8), epoch: 0, groupKey: bobGK)
        let plaintext = try GroupCrypto().decryptGroupMessage(ciphertext, groupKey: aliceGK)
        XCTAssertEqual(String(decoding: plaintext, as: UTF8.self), "hello group")
        XCTAssertEqual(harness.coordinator.groupId, "group-1")
        XCTAssertEqual(harness.coordinator.currentEpoch, 0)
    }

    @MainActor
    func testCreateGroupRejectsMemberWithInvalidPrekeySignature() async throws {
        let harness = try makeHarness()
        let bobKey = Curve25519.KeyAgreement.PrivateKey()
        let carolKey = Curve25519.KeyAgreement.PrivateKey()
        let identity = CryptoIdentity(privateKey: Curve25519.Signing.PrivateKey())
        let badSignature = MessageCrypto().signPrekey(
            x25519PublicKeyBase64: Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation.base64EncodedString(),
            with: identity
        )
        try harness.addVerifiedPrekey(username: "carol", userId: "user-c", key: carolKey)
        harness.messageService.prekeys["bob"] = PrekeyResponse(
            userId: "user-b",
            username: "bob",
            identityPublicKey: identity.publicKeyBase64,
            x25519PublicKey: bobKey.publicKey.rawRepresentation.base64EncodedString(),
            keySignature: badSignature
        )

        await harness.coordinator.createGroup(name: "Ops", memberUsernames: ["bob", "carol"])

        XCTAssertEqual(harness.coordinator.statusMessage, "Could not verify bob's keys.")
        XCTAssertTrue(harness.groupService.createRequests.isEmpty)
    }

    @MainActor
    func testSendEncryptsUnderCurrentEpochKey() async throws {
        let harness = try makeHarness()
        let bobKey = Curve25519.KeyAgreement.PrivateKey()
        let carolKey = Curve25519.KeyAgreement.PrivateKey()
        try harness.addVerifiedPrekey(username: "bob", userId: "user-b", key: bobKey)
        try harness.addVerifiedPrekey(username: "carol", userId: "user-c", key: carolKey)
        await harness.coordinator.createGroup(name: "Ops", memberUsernames: ["bob", "carol"])

        await harness.coordinator.send(text: "epoch secret")

        let sent = try XCTUnwrap(harness.groupService.sentMessages.last)
        XCTAssertEqual(sent.groupId, "group-1")
        XCTAssertEqual(sent.epoch, 0)
        XCTAssertNotEqual(sent.ciphertext, "epoch secret")
        XCTAssertFalse(sent.ciphertext.contains("epoch secret"))
        let key = try XCTUnwrap(harness.coordinator.epochKeys[0])
        let plaintext = try GroupCrypto().decryptGroupMessage(sent.ciphertext, groupKey: key)
        XCTAssertEqual(String(decoding: plaintext, as: UTF8.self), "epoch secret")
        XCTAssertEqual(harness.coordinator.messages.last?.text, "epoch secret")
    }

    @MainActor
    func testCreateGroupSubscribesLiveSoCreatorReceivesInboundMessages() async throws {
        let harness = try makeHarness()
        let bobKey = Curve25519.KeyAgreement.PrivateKey()
        let carolKey = Curve25519.KeyAgreement.PrivateKey()
        try harness.addVerifiedPrekey(username: "bob", userId: "user-b", key: bobKey)
        try harness.addVerifiedPrekey(username: "carol", userId: "user-c", key: carolKey)

        await harness.coordinator.createGroup(name: "Ops", memberUsernames: ["bob", "carol"])
        try await Task.sleep(nanoseconds: 50_000_000)
        let groupKey = try XCTUnwrap(harness.coordinator.epochKeys[0])
        harness.groupService.emitLive(
            try encryptedRecord(id: "msg-live-created", text: "creator sees me", groupKey: groupKey)
        )
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(harness.groupService.liveSubscriptions.map(\.groupId), ["group-1"])
        XCTAssertEqual(harness.coordinator.messages.map(\.text), ["creator sees me"])
    }

    @MainActor
    func testThreeMemberCoordinatorsAllSendAndDecryptLiveMessages() async throws {
        let sharedMessageService = FakeGroupMessageService()
        let sharedGroupService = FakeGroupService()
        let alice = try makeHarness(
            username: "alice",
            userId: "user-a",
            token: "token-a",
            messageService: sharedMessageService,
            groupService: sharedGroupService
        )
        let bob = try makeHarness(
            username: "bob",
            userId: "user-b",
            token: "token-b",
            messageService: sharedMessageService,
            groupService: sharedGroupService
        )
        let carol = try makeHarness(
            username: "carol",
            userId: "user-c",
            token: "token-c",
            messageService: sharedMessageService,
            groupService: sharedGroupService
        )

        await alice.coordinator.createGroup(name: "Ops", memberUsernames: ["bob", "carol"])
        let createRequest = try XCTUnwrap(sharedGroupService.createRequests.last)
        sharedGroupService.keysByGroupAndToken["group-1"] = [
            "token-a": [GroupKeyRecord(epoch: 0, wrappedKey: try XCTUnwrap(createRequest.members.first { $0.username == "alice" }?.wrappedKey))],
            "token-b": [GroupKeyRecord(epoch: 0, wrappedKey: try XCTUnwrap(createRequest.members.first { $0.username == "bob" }?.wrappedKey))],
            "token-c": [GroupKeyRecord(epoch: 0, wrappedKey: try XCTUnwrap(createRequest.members.first { $0.username == "carol" }?.wrappedKey))]
        ]

        await bob.coordinator.openGroup(id: "group-1")
        await carol.coordinator.openGroup(id: "group-1")
        try await Task.sleep(nanoseconds: 50_000_000)

        try await sendAndBroadcast(
            from: alice,
            senderId: "user-a",
            text: "alice to group",
            through: sharedGroupService
        )
        try await sendAndBroadcast(
            from: bob,
            senderId: "user-b",
            text: "bob to group",
            through: sharedGroupService
        )
        try await sendAndBroadcast(
            from: carol,
            senderId: "user-c",
            text: "carol to group",
            through: sharedGroupService
        )

        XCTAssertEqual(alice.coordinator.messages.map(\.text), ["alice to group", "bob to group", "carol to group"])
        XCTAssertEqual(bob.coordinator.messages.map(\.text), ["alice to group", "bob to group", "carol to group"])
        XCTAssertEqual(carol.coordinator.messages.map(\.text), ["alice to group", "bob to group", "carol to group"])
        XCTAssertEqual(alice.coordinator.messages.map(\.senderName), ["You", "bob", "carol"])
        XCTAssertEqual(bob.coordinator.messages.map(\.senderName), ["alice", "You", "carol"])
        XCTAssertEqual(carol.coordinator.messages.map(\.senderName), ["alice", "bob", "You"])
    }

    @MainActor
    func testExistingMemberReceivesLiveMessageAfterRekeyViaKeyRefetch() async throws {
        let harness = try makeHarness()
        let localPrivate = try harness.x25519.loadOrCreate()
        let keyZero = GroupCrypto().newGroupKey()
        let keyOne = GroupCrypto().newGroupKey()
        let wrappedZero = try GroupCrypto().wrapGroupKey(keyZero, toRecipientX25519: localPrivate.publicKey.rawRepresentation.base64EncodedString())
        let wrappedOne = try GroupCrypto().wrapGroupKey(keyOne, toRecipientX25519: localPrivate.publicKey.rawRepresentation.base64EncodedString())
        harness.groupService.keyFetchSequenceByGroup["group-1"] = [
            [GroupKeyRecord(epoch: 0, wrappedKey: wrappedZero)],
            [
                GroupKeyRecord(epoch: 0, wrappedKey: wrappedZero),
                GroupKeyRecord(epoch: 1, wrappedKey: wrappedOne)
            ]
        ]
        harness.groupService.setDetail(groupId: "group-1", currentEpoch: 1)
        harness.groupService.liveRecordsByGroup["group-1"] = [
            try encryptedRecord(id: "msg-epoch-1", text: "after rekey", groupKey: keyOne, epoch: 1)
        ]

        await harness.coordinator.openGroup(id: "group-1")
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(harness.groupService.fetchKeysCalls, ["group-1", "group-1"])
        XCTAssertEqual(harness.coordinator.currentEpoch, 1)
        XCTAssertEqual(harness.coordinator.messages.map(\.text), ["after rekey"])
    }

    @MainActor
    func testAddMemberRekeyPreservesExistingLiveDeliveryAndBlocksPriorEpochForNewMember() async throws {
        let sharedMessageService = FakeGroupMessageService()
        let sharedGroupService = FakeGroupService()
        let alice = try makeHarness(
            username: "alice",
            userId: "user-a",
            token: "token-a",
            messageService: sharedMessageService,
            groupService: sharedGroupService
        )
        let bob = try makeHarness(
            username: "bob",
            userId: "user-b",
            token: "token-b",
            messageService: sharedMessageService,
            groupService: sharedGroupService
        )
        let carol = try makeHarness(
            username: "carol",
            userId: "user-c",
            token: "token-c",
            messageService: sharedMessageService,
            groupService: sharedGroupService
        )

        let daveKey = Curve25519.KeyAgreement.PrivateKey()
        try alice.addVerifiedPrekey(username: "dave", userId: "user-d", key: daveKey)
        await alice.coordinator.createGroup(name: "Ops", memberUsernames: ["bob", "dave"])
        let createRequest = try XCTUnwrap(sharedGroupService.createRequests.last)
        sharedGroupService.keysByGroupAndToken["group-1"] = [
            "token-a": [GroupKeyRecord(epoch: 0, wrappedKey: try XCTUnwrap(createRequest.members.first { $0.username == "alice" }?.wrappedKey))],
            "token-b": [GroupKeyRecord(epoch: 0, wrappedKey: try XCTUnwrap(createRequest.members.first { $0.username == "bob" }?.wrappedKey))]
        ]

        await bob.coordinator.openGroup(id: "group-1")
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNotNil(bob.coordinator.epochKeys[0])
        XCTAssertNil(bob.coordinator.epochKeys[1])

        try await sendAndBroadcast(
            from: alice,
            senderId: "user-a",
            text: "epoch zero sentinel",
            through: sharedGroupService
        )
        let priorCiphertext = try XCTUnwrap(sharedGroupService.sentMessages.last?.ciphertext)

        await alice.coordinator.addMember(username: "carol")
        let addRequest = try XCTUnwrap(sharedGroupService.addRequests.last)
        XCTAssertEqual(addRequest.epoch, 1)
        sharedGroupService.keysByGroupAndToken["group-1"] = [
            "token-a": [
                GroupKeyRecord(epoch: 0, wrappedKey: try XCTUnwrap(createRequest.members.first { $0.username == "alice" }?.wrappedKey)),
                GroupKeyRecord(epoch: 1, wrappedKey: try XCTUnwrap(addRequest.keys.first { $0.memberId == "user-a" }?.wrappedKey))
            ],
            "token-b": [
                GroupKeyRecord(epoch: 0, wrappedKey: try XCTUnwrap(createRequest.members.first { $0.username == "bob" }?.wrappedKey)),
                GroupKeyRecord(epoch: 1, wrappedKey: try XCTUnwrap(addRequest.keys.first { $0.memberId == "user-b" }?.wrappedKey))
            ],
            "token-c": [
                GroupKeyRecord(epoch: 1, wrappedKey: try XCTUnwrap(addRequest.keys.first { $0.memberId == "user-c" }?.wrappedKey))
            ]
        ]

        await carol.coordinator.openGroup(id: "group-1")
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNotNil(carol.coordinator.epochKeys[1])
        XCTAssertNil(carol.coordinator.epochKeys[0])

        try await sendAndBroadcast(
            from: carol,
            senderId: "user-c",
            text: "epoch one for everyone",
            through: sharedGroupService
        )

        XCTAssertEqual(bob.coordinator.messages.map(\.text), ["epoch zero sentinel", "epoch one for everyone"])
        XCTAssertEqual(bob.coordinator.messages.map(\.senderName), ["alice", "carol"])
        XCTAssertNotNil(bob.coordinator.epochKeys[1])
        XCTAssertEqual(carol.coordinator.messages.map(\.text), ["epoch one for everyone"])

        let carolEpochOneKey = try XCTUnwrap(carol.coordinator.epochKeys[1])
        XCTAssertThrowsError(try GroupCrypto().decryptGroupMessage(priorCiphertext, groupKey: carolEpochOneKey))
    }

    @MainActor
    func testEpochEventRefreshesKeysGroupDetailAndGroupListBeforeNextMessage() async throws {
        let harness = try makeHarness()
        let localPrivate = try harness.x25519.loadOrCreate()
        let keyZero = GroupCrypto().newGroupKey()
        let keyOne = GroupCrypto().newGroupKey()
        let wrappedZero = try GroupCrypto().wrapGroupKey(keyZero, toRecipientX25519: localPrivate.publicKey.rawRepresentation.base64EncodedString())
        let wrappedOne = try GroupCrypto().wrapGroupKey(keyOne, toRecipientX25519: localPrivate.publicKey.rawRepresentation.base64EncodedString())
        harness.groupService.keysByGroup["group-1"] = [GroupKeyRecord(epoch: 0, wrappedKey: wrappedZero)]
        harness.groupService.listedGroups = [groupSummary(id: "group-1", name: "Ops")]

        await harness.coordinator.openGroup(id: "group-1")
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(harness.coordinator.currentEpoch, 0)
        XCTAssertNil(harness.coordinator.epochKeys[1])

        harness.groupService.setDetail(groupId: "group-1", currentEpoch: 1)
        harness.groupService.keysByGroup["group-1"] = [
            GroupKeyRecord(epoch: 0, wrappedKey: wrappedZero),
            GroupKeyRecord(epoch: 1, wrappedKey: wrappedOne)
        ]
        harness.groupService.emitEpoch(GroupEpochEvent(groupId: "group-1", epoch: 1))
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(harness.coordinator.currentEpoch, 1)
        XCTAssertEqual(harness.coordinator.epochKeys[1], keyOne)
        XCTAssertEqual(harness.groupService.fetchKeysCalls, ["group-1", "group-1"])
        XCTAssertEqual(harness.groupService.listTokens, ["token-1"])
    }

    @MainActor
    func testSendAfterRekeyEncryptsUnderLatestEpoch() async throws {
        let harness = try makeHarness()
        let localPrivate = try harness.x25519.loadOrCreate()
        let keyZero = GroupCrypto().newGroupKey()
        let keyOne = GroupCrypto().newGroupKey()
        let wrappedZero = try GroupCrypto().wrapGroupKey(keyZero, toRecipientX25519: localPrivate.publicKey.rawRepresentation.base64EncodedString())
        let wrappedOne = try GroupCrypto().wrapGroupKey(keyOne, toRecipientX25519: localPrivate.publicKey.rawRepresentation.base64EncodedString())
        harness.groupService.keysByGroup["group-1"] = [GroupKeyRecord(epoch: 0, wrappedKey: wrappedZero)]

        await harness.coordinator.openGroup(id: "group-1")
        harness.groupService.setDetail(groupId: "group-1", currentEpoch: 1)
        harness.groupService.keysByGroup["group-1"] = [
            GroupKeyRecord(epoch: 0, wrappedKey: wrappedZero),
            GroupKeyRecord(epoch: 1, wrappedKey: wrappedOne)
        ]

        await harness.coordinator.send(text: "latest epoch")

        let sent = try XCTUnwrap(harness.groupService.sentMessages.last)
        XCTAssertEqual(sent.epoch, 1)
        let plaintext = try GroupCrypto().decryptGroupMessage(sent.ciphertext, groupKey: keyOne)
        XCTAssertEqual(String(decoding: plaintext, as: UTF8.self), "latest epoch")
    }

    @MainActor
    func testSendAttachmentUploadsEncryptedBlobAndSendsGroupEncryptedDescriptor() async throws {
        let harness = try makeHarness()
        let bobKey = Curve25519.KeyAgreement.PrivateKey()
        let carolKey = Curve25519.KeyAgreement.PrivateKey()
        try harness.addVerifiedPrekey(username: "bob", userId: "user-b", key: bobKey)
        try harness.addVerifiedPrekey(username: "carol", userId: "user-c", key: carolKey)
        let fileBytes = Data("group attachment sentinel bytes".utf8)
        await harness.coordinator.createGroup(name: "Ops", memberUsernames: ["bob", "carol"])

        await harness.coordinator.sendAttachment(data: fileBytes, filename: "ops.txt", mime: "text/plain")

        let uploaded = try XCTUnwrap(harness.attachmentService.uploadedBlobs.last)
        XCTAssertNotEqual(uploaded, fileBytes)
        XCTAssertFalse(String(decoding: uploaded, as: UTF8.self).contains("group attachment sentinel"))
        let sent = try XCTUnwrap(harness.groupService.sentMessages.last)
        let groupKey = try XCTUnwrap(harness.coordinator.epochKeys[0])
        let plaintext = try GroupCrypto().decryptGroupMessage(sent.ciphertext, groupKey: groupKey)
        let descriptor = try XCTUnwrap(AttachmentDescriptor.decode(plaintext))
        XCTAssertEqual(descriptor.attachmentId, "attachment-1")
        XCTAssertEqual(descriptor.filename, "ops.txt")
        XCTAssertEqual(descriptor.mime, "text/plain")
        XCTAssertEqual(descriptor.size, fileBytes.count)
        XCTAssertEqual(harness.coordinator.messages.last?.attachment?.attachmentId, "attachment-1")
        XCTAssertEqual(harness.coordinator.messages.last?.text, "ops.txt")
    }

    @MainActor
    func testLateAddedMemberCannotDecryptPriorEpochMessage() async throws {
        let harness = try makeHarness()
        let bobKey = Curve25519.KeyAgreement.PrivateKey()
        let carolKey = Curve25519.KeyAgreement.PrivateKey()
        let daveKey = Curve25519.KeyAgreement.PrivateKey()
        try harness.addVerifiedPrekey(username: "bob", userId: "user-b", key: bobKey)
        try harness.addVerifiedPrekey(username: "carol", userId: "user-c", key: carolKey)
        try harness.addVerifiedPrekey(username: "dave", userId: "user-d", key: daveKey)
        await harness.coordinator.createGroup(name: "Ops", memberUsernames: ["bob", "carol"])
        let epochZeroKey = try XCTUnwrap(harness.coordinator.epochKeys[0])
        let epochZeroMessage = try GroupCrypto().encryptGroupMessage(Data("old secret".utf8), epoch: 0, groupKey: epochZeroKey)

        await harness.coordinator.addMember(username: "dave")

        XCTAssertNil(harness.coordinator.epochKeys[2])
        let addRequest = try XCTUnwrap(harness.groupService.addRequests.last)
        XCTAssertEqual(addRequest.epoch, 1)
        XCTAssertEqual(Set(addRequest.keys.map(\.memberId)), ["user-a", "user-b", "user-c", "user-d"])
        let daveWrapped = try XCTUnwrap(addRequest.keys.first { $0.memberId == "user-d" }?.wrappedKey)
        let daveEpochOneKey = try GroupCrypto().unwrapGroupKey(daveWrapped, withLocalX25519: daveKey)
        XCTAssertThrowsError(try GroupCrypto().decryptGroupMessage(epochZeroMessage, groupKey: daveEpochOneKey))
        XCTAssertNotEqual(daveEpochOneKey, epochZeroKey)
        XCTAssertEqual(harness.coordinator.currentEpoch, 1)
    }

    @MainActor
    func testOpenGroupDecryptsHistoryAndSkipsUndecryptable() async throws {
        let harness = try makeHarness()
        let localPrivate = try harness.x25519.loadOrCreate()
        let keyZero = GroupCrypto().newGroupKey()
        let keyOne = GroupCrypto().newGroupKey()
        let wrappedOne = try GroupCrypto().wrapGroupKey(keyOne, toRecipientX25519: localPrivate.publicKey.rawRepresentation.base64EncodedString())
        harness.groupService.keysByGroup["group-1"] = [GroupKeyRecord(epoch: 1, wrappedKey: wrappedOne)]
        harness.groupService.historyByGroup["group-1"] = [
            GroupMessageRecord(
                id: "msg-old",
                groupId: "group-1",
                senderId: "user-b",
                epoch: 0,
                ciphertext: try GroupCrypto().encryptGroupMessage(Data("old".utf8), epoch: 0, groupKey: keyZero),
                createdAt: "2026-06-03T00:00:00Z"
            ),
            GroupMessageRecord(
                id: "msg-new",
                groupId: "group-1",
                senderId: "user-b",
                epoch: 1,
                ciphertext: try GroupCrypto().encryptGroupMessage(Data("new".utf8), epoch: 1, groupKey: keyOne),
                createdAt: "2026-06-03T00:01:00Z"
            )
        ]

        await harness.coordinator.openGroup(id: "group-1")

        XCTAssertEqual(harness.coordinator.messages, [
            DisplayGroupMessage(
                id: "msg-new",
                senderId: "user-b",
                senderName: "bob",
                isMine: false,
                text: "new",
                attachment: nil,
                createdAt: "2026-06-03T00:01:00Z"
            )
        ])
    }

    @MainActor
    func testOpenGroupDetectsAttachmentDescriptorAndDownloadReturnsOriginalBytes() async throws {
        let harness = try makeHarness()
        let localPrivate = try harness.x25519.loadOrCreate()
        let groupKey = GroupCrypto().newGroupKey()
        let wrapped = try GroupCrypto().wrapGroupKey(
            groupKey,
            toRecipientX25519: localPrivate.publicKey.rawRepresentation.base64EncodedString()
        )
        let original = Data([0x00, 0xFF]) + Data("group downloaded sentinel".utf8)
        let fileKey = FileCrypto().newFileKey()
        harness.attachmentService.downloads["group-attachment-in"] = try FileCrypto().encrypt(original, using: fileKey)
        let descriptor = AttachmentDescriptor(
            attachmentId: "group-attachment-in",
            fileKey: fileKey.withUnsafeBytes { Data($0).base64EncodedString() },
            filename: "group.bin",
            mime: "application/octet-stream",
            size: original.count
        )
        harness.groupService.keysByGroup["group-1"] = [GroupKeyRecord(epoch: 0, wrappedKey: wrapped)]
        harness.groupService.historyByGroup["group-1"] = [
            GroupMessageRecord(
                id: "msg-attachment",
                groupId: "group-1",
                senderId: "user-b",
                epoch: 0,
                ciphertext: try GroupCrypto().encryptGroupMessage(descriptor.encodedJSON(), epoch: 0, groupKey: groupKey),
                createdAt: "2026-06-03T00:00:00Z"
            ),
            try encryptedRecord(id: "msg-text", text: "plain group still works", groupKey: groupKey)
        ]

        await harness.coordinator.openGroup(id: "group-1")

        XCTAssertEqual(harness.coordinator.messages.count, 2)
        let attachment = try XCTUnwrap(harness.coordinator.messages.first?.attachment)
        XCTAssertEqual(attachment.filename, "group.bin")
        XCTAssertEqual(harness.coordinator.messages.first?.text, "group.bin")
        XCTAssertNil(harness.coordinator.messages.last?.attachment)
        XCTAssertEqual(harness.coordinator.messages.last?.text, "plain group still works")
        let downloaded = await harness.coordinator.downloadAttachment(attachment)
        XCTAssertEqual(downloaded, original)
    }

    @MainActor
    func testRefreshGroupsPublishesAllListedGroupsOnLaunch() async throws {
        let harness = try makeHarness()
        harness.groupService.listedGroups = [
            groupSummary(id: "group-1", name: "Ops"),
            groupSummary(id: "group-2", name: "Incident")
        ]

        await harness.coordinator.refreshGroups()

        XCTAssertEqual(harness.groupService.listTokens, ["token-1"])
        XCTAssertEqual(harness.coordinator.groups.map(\.id), ["group-1", "group-2"])
        XCTAssertEqual(harness.coordinator.groups.map(\.name), ["Ops", "Incident"])
    }

    @MainActor
    func testOpenGroupKeepsServerHistoryOrderAndDecryptsEveryMessage() async throws {
        let harness = try makeHarness()
        let localPrivate = try harness.x25519.loadOrCreate()
        let groupKey = GroupCrypto().newGroupKey()
        let wrapped = try GroupCrypto().wrapGroupKey(groupKey, toRecipientX25519: localPrivate.publicKey.rawRepresentation.base64EncodedString())
        harness.groupService.keysByGroup["group-1"] = [GroupKeyRecord(epoch: 0, wrappedKey: wrapped)]
        harness.groupService.historyByGroup["group-1"] = [
            try encryptedRecord(id: "msg-1", text: "first", groupKey: groupKey),
            try encryptedRecord(id: "msg-2", text: "second", groupKey: groupKey),
            try encryptedRecord(id: "msg-3", text: "third", groupKey: groupKey)
        ]

        await harness.coordinator.openGroup(id: "group-1")

        XCTAssertEqual(harness.coordinator.messages.map(\.id), ["msg-1", "msg-2", "msg-3"])
        XCTAssertEqual(harness.coordinator.messages.map(\.text), ["first", "second", "third"])
    }

    @MainActor
    func testReconnectCatchesUpOfflineGroupMessagesInOrderAndDedupsLiveDuplicates() async throws {
        let harness = try makeHarness()
        let localPrivate = try harness.x25519.loadOrCreate()
        let groupKey = GroupCrypto().newGroupKey()
        let wrapped = try GroupCrypto().wrapGroupKey(groupKey, toRecipientX25519: localPrivate.publicKey.rawRepresentation.base64EncodedString())
        harness.groupService.keysByGroup["group-1"] = [GroupKeyRecord(epoch: 0, wrappedKey: wrapped)]
        harness.groupService.historyByGroup["group-1"] = [
            try encryptedRecord(id: "msg-1", text: "before disconnect", groupKey: groupKey)
        ]
        await harness.coordinator.openGroup(id: "group-1")
        harness.coordinator.cancelLiveSubscription()

        harness.groupService.historyByGroup["group-1"] = [
            try encryptedRecord(id: "msg-1", text: "before disconnect", groupKey: groupKey),
            try encryptedRecord(id: "msg-2", text: "offline one", groupKey: groupKey),
            try encryptedRecord(id: "msg-3", text: "offline two", groupKey: groupKey),
            try encryptedRecord(id: "msg-4", text: "offline three", groupKey: groupKey)
        ]
        harness.groupService.liveRecordsByGroup["group-1"] = [
            try encryptedRecord(id: "msg-3", text: "duplicate stream", groupKey: groupKey),
            try encryptedRecord(id: "msg-5", text: "live after reconnect", groupKey: groupKey)
        ]

        await harness.coordinator.reconnectLive()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(harness.coordinator.messages.map(\.id), ["msg-1", "msg-2", "msg-3", "msg-4", "msg-5"])
        XCTAssertEqual(harness.coordinator.messages.map(\.text), [
            "before disconnect",
            "offline one",
            "offline two",
            "offline three",
            "live after reconnect"
        ])
    }

    @MainActor
    func testSubscribeLiveDecryptsInboundGroupRecord() async throws {
        let harness = try makeHarness()
        let localPrivate = try harness.x25519.loadOrCreate()
        let groupKey = GroupCrypto().newGroupKey()
        let wrapped = try GroupCrypto().wrapGroupKey(groupKey, toRecipientX25519: localPrivate.publicKey.rawRepresentation.base64EncodedString())
        harness.groupService.keysByGroup["group-1"] = [GroupKeyRecord(epoch: 0, wrappedKey: wrapped)]
        harness.groupService.liveRecordsByGroup["group-1"] = [
            GroupMessageRecord(
                id: "msg-live",
                groupId: "group-1",
                senderId: "user-b",
                epoch: 0,
                ciphertext: try GroupCrypto().encryptGroupMessage(Data("streamed".utf8), epoch: 0, groupKey: groupKey),
                createdAt: "2026-06-03T00:02:00Z"
            ),
            GroupMessageRecord(
                id: "msg-live",
                groupId: "group-1",
                senderId: "user-b",
                epoch: 0,
                ciphertext: try GroupCrypto().encryptGroupMessage(Data("streamed duplicate".utf8), epoch: 0, groupKey: groupKey),
                createdAt: "2026-06-03T00:02:01Z"
            )
        ]

        await harness.coordinator.openGroup(id: "group-1")
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(harness.groupService.liveSubscriptions.map(\.groupId), ["group-1"])
        XCTAssertEqual(harness.groupService.liveSubscriptions.map(\.token), ["token-1"])
        XCTAssertEqual(harness.coordinator.messages, [
            DisplayGroupMessage(
                id: "msg-live",
                senderId: "user-b",
                senderName: "bob",
                isMine: false,
                text: "streamed",
                attachment: nil,
                createdAt: "2026-06-03T00:02:00Z"
            )
        ])
    }

    @MainActor
    func testSubscribeLiveRendersInboundAttachmentAndDownloadsOriginalBytes() async throws {
        let harness = try makeHarness()
        let localPrivate = try harness.x25519.loadOrCreate()
        let groupKey = GroupCrypto().newGroupKey()
        let wrapped = try GroupCrypto().wrapGroupKey(groupKey, toRecipientX25519: localPrivate.publicKey.rawRepresentation.base64EncodedString())
        let original = Data([0x47, 0x52, 0x50, 0x00, 0xFF]) + Data(" live group attachment".utf8)
        let fileKey = FileCrypto().newFileKey()
        let descriptor = AttachmentDescriptor(
            attachmentId: "group-live-attachment",
            fileKey: fileKey.withUnsafeBytes { Data($0).base64EncodedString() },
            filename: "live-group.bin",
            mime: "application/octet-stream",
            size: original.count
        )
        harness.attachmentService.downloads[descriptor.attachmentId] = try FileCrypto().encrypt(original, using: fileKey)
        harness.groupService.keysByGroup["group-1"] = [GroupKeyRecord(epoch: 0, wrappedKey: wrapped)]

        await harness.coordinator.openGroup(id: "group-1")
        try await Task.sleep(nanoseconds: 50_000_000)
        harness.groupService.emitLive(
            try encryptedAttachmentRecord(
                id: "msg-live-attachment",
                descriptor: descriptor,
                groupKey: groupKey,
                senderId: "user-b"
            )
        )
        try await Task.sleep(nanoseconds: 50_000_000)

        let message = try XCTUnwrap(harness.coordinator.messages.first)
        XCTAssertEqual(message.id, "msg-live-attachment")
        XCTAssertEqual(message.senderId, "user-b")
        XCTAssertEqual(message.senderName, "bob")
        XCTAssertNotEqual(message.senderName, "user-b")
        XCTAssertFalse(message.isMine)
        XCTAssertEqual(message.text, "live-group.bin")
        let attachment = try XCTUnwrap(message.attachment)
        XCTAssertEqual(attachment.attachmentId, "group-live-attachment")
        XCTAssertEqual(attachment.filename, "live-group.bin")
        XCTAssertEqual(attachment.size, original.count)
        let downloaded = await harness.coordinator.downloadAttachment(attachment)
        XCTAssertEqual(downloaded, original)
    }

    @MainActor
    func testExistingMemberReceivesLiveAttachmentAfterRekeyAndLateJoinerCannotDecryptPriorEpochAttachment() async throws {
        let sharedMessageService = FakeGroupMessageService()
        let sharedGroupService = FakeGroupService()
        let alice = try makeHarness(
            username: "alice",
            userId: "user-a",
            token: "token-a",
            messageService: sharedMessageService,
            groupService: sharedGroupService
        )
        let bob = try makeHarness(
            username: "bob",
            userId: "user-b",
            token: "token-b",
            messageService: sharedMessageService,
            groupService: sharedGroupService
        )
        let carol = try makeHarness(
            username: "carol",
            userId: "user-c",
            token: "token-c",
            messageService: sharedMessageService,
            groupService: sharedGroupService
        )

        let daveKey = Curve25519.KeyAgreement.PrivateKey()
        try alice.addVerifiedPrekey(username: "dave", userId: "user-d", key: daveKey)
        await alice.coordinator.createGroup(name: "Ops", memberUsernames: ["bob", "dave"])
        let createRequest = try XCTUnwrap(sharedGroupService.createRequests.last)
        sharedGroupService.keysByGroupAndToken["group-1"] = [
            "token-a": [GroupKeyRecord(epoch: 0, wrappedKey: try XCTUnwrap(createRequest.members.first { $0.username == "alice" }?.wrappedKey))],
            "token-b": [GroupKeyRecord(epoch: 0, wrappedKey: try XCTUnwrap(createRequest.members.first { $0.username == "bob" }?.wrappedKey))]
        ]

        await bob.coordinator.openGroup(id: "group-1")
        try await Task.sleep(nanoseconds: 50_000_000)
        let epochZeroKey = try XCTUnwrap(bob.coordinator.epochKeys[0])
        let priorDescriptor = AttachmentDescriptor(
            attachmentId: "prior-epoch-attachment",
            fileKey: FileCrypto().newFileKey().withUnsafeBytes { Data($0).base64EncodedString() },
            filename: "prior.bin",
            mime: "application/octet-stream",
            size: 4
        )
        let priorCiphertext = try GroupCrypto().encryptGroupMessage(priorDescriptor.encodedJSON(), epoch: 0, groupKey: epochZeroKey)

        await alice.coordinator.addMember(username: "carol")
        let addRequest = try XCTUnwrap(sharedGroupService.addRequests.last)
        XCTAssertEqual(addRequest.epoch, 1)
        sharedGroupService.keysByGroupAndToken["group-1"] = [
            "token-a": [
                GroupKeyRecord(epoch: 0, wrappedKey: try XCTUnwrap(createRequest.members.first { $0.username == "alice" }?.wrappedKey)),
                GroupKeyRecord(epoch: 1, wrappedKey: try XCTUnwrap(addRequest.keys.first { $0.memberId == "user-a" }?.wrappedKey))
            ],
            "token-b": [
                GroupKeyRecord(epoch: 0, wrappedKey: try XCTUnwrap(createRequest.members.first { $0.username == "bob" }?.wrappedKey)),
                GroupKeyRecord(epoch: 1, wrappedKey: try XCTUnwrap(addRequest.keys.first { $0.memberId == "user-b" }?.wrappedKey))
            ],
            "token-c": [
                GroupKeyRecord(epoch: 1, wrappedKey: try XCTUnwrap(addRequest.keys.first { $0.memberId == "user-c" }?.wrappedKey))
            ]
        ]
        XCTAssertNil(bob.coordinator.epochKeys[1])

        sharedGroupService.emitEpoch(GroupEpochEvent(groupId: "group-1", epoch: 1))
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(bob.coordinator.currentEpoch, 1)
        XCTAssertNotNil(bob.coordinator.epochKeys[1])

        await carol.coordinator.openGroup(id: "group-1")
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNotNil(carol.coordinator.epochKeys[1])
        XCTAssertNil(carol.coordinator.epochKeys[0])
        let carolEpochOneKey = try XCTUnwrap(carol.coordinator.epochKeys[1])
        XCTAssertThrowsError(try GroupCrypto().decryptGroupMessage(priorCiphertext, groupKey: carolEpochOneKey))

        let original = Data([0xE2, 0x01, 0x02, 0x03]) + Data(" post rekey attachment".utf8)
        try await sendAttachmentAndBroadcast(
            from: carol,
            senderId: "user-c",
            data: original,
            filename: "epoch-one.bin",
            mime: "application/octet-stream",
            through: sharedGroupService
        )
        bob.attachmentService.downloads["attachment-1"] = try XCTUnwrap(carol.attachmentService.downloads["attachment-1"])
        try await Task.sleep(nanoseconds: 50_000_000)

        let message = try XCTUnwrap(bob.coordinator.messages.last)
        XCTAssertEqual(message.senderId, "user-c")
        XCTAssertEqual(message.senderName, "carol")
        XCTAssertNotEqual(message.senderName, "user-c")
        XCTAssertEqual(message.text, "epoch-one.bin")
        let attachment = try XCTUnwrap(message.attachment)
        XCTAssertEqual(attachment.filename, "epoch-one.bin")
        XCTAssertEqual(attachment.size, original.count)
        let downloaded = await bob.coordinator.downloadAttachment(attachment)
        XCTAssertEqual(downloaded, original)
    }

    @MainActor
    func testSenderAttributionResolvesUsernameAndYouForLocalAccount() async throws {
        let harness = try makeHarness()
        let localPrivate = try harness.x25519.loadOrCreate()
        let groupKey = GroupCrypto().newGroupKey()
        let wrapped = try GroupCrypto().wrapGroupKey(groupKey, toRecipientX25519: localPrivate.publicKey.rawRepresentation.base64EncodedString())
        harness.groupService.keysByGroup["group-1"] = [GroupKeyRecord(epoch: 0, wrappedKey: wrapped)]
        harness.groupService.historyByGroup["group-1"] = [
            try encryptedRecord(id: "msg-bob", text: "from bob", groupKey: groupKey, senderId: "user-b"),
            try encryptedRecord(id: "msg-alice", text: "from alice", groupKey: groupKey, senderId: "user-a"),
            try encryptedRecord(id: "msg-unknown", text: "from unknown", groupKey: groupKey, senderId: "user-z")
        ]

        await harness.coordinator.openGroup(id: "group-1")

        XCTAssertEqual(harness.coordinator.messages.map(\.senderName), ["bob", "You", "user-z"])
        XCTAssertEqual(harness.coordinator.messages.map(\.senderId), ["user-b", "user-a", "user-z"])
    }

    private func groupSummary(id: String, name: String) -> GroupSummary {
        GroupSummary(
            id: id,
            name: name,
            creatorId: "user-a",
            currentEpoch: 0,
            joinedEpoch: 0,
            createdAt: "2026-06-03T00:00:00Z"
        )
    }

    private func encryptedRecord(
        id: String,
        text: String,
        groupKey: Data,
        groupId: String = "group-1",
        senderId: String = "user-b",
        epoch: UInt32 = 0
    ) throws -> GroupMessageRecord {
        GroupMessageRecord(
            id: id,
            groupId: groupId,
            senderId: senderId,
            epoch: epoch,
            ciphertext: try GroupCrypto().encryptGroupMessage(Data(text.utf8), epoch: epoch, groupKey: groupKey),
            createdAt: "2026-06-03T00:00:00Z"
        )
    }

    private func encryptedAttachmentRecord(
        id: String,
        descriptor: AttachmentDescriptor,
        groupKey: Data,
        groupId: String = "group-1",
        senderId: String = "user-b",
        epoch: UInt32 = 0
    ) throws -> GroupMessageRecord {
        GroupMessageRecord(
            id: id,
            groupId: groupId,
            senderId: senderId,
            epoch: epoch,
            ciphertext: try GroupCrypto().encryptGroupMessage(descriptor.encodedJSON(), epoch: epoch, groupKey: groupKey),
            createdAt: "2026-06-03T00:00:00Z"
        )
    }

    @MainActor
    private func sendAndBroadcast(
        from harness: Harness,
        senderId: String,
        text: String,
        through groupService: FakeGroupService
    ) async throws {
        await harness.coordinator.send(text: text)
        let sent = try XCTUnwrap(groupService.sentMessages.last)
        let messageId = "msg-\(groupService.sentMessages.count)"
        groupService.emitLive(GroupMessageRecord(
            id: messageId,
            groupId: sent.groupId,
            senderId: senderId,
            epoch: sent.epoch,
            ciphertext: sent.ciphertext,
            createdAt: "2026-06-03T00:00:00Z"
        ))
        try await Task.sleep(nanoseconds: 50_000_000)
    }

    @MainActor
    private func sendAttachmentAndBroadcast(
        from harness: Harness,
        senderId: String,
        data: Data,
        filename: String,
        mime: String,
        through groupService: FakeGroupService
    ) async throws {
        await harness.coordinator.sendAttachment(data: data, filename: filename, mime: mime)
        let sent = try XCTUnwrap(groupService.sentMessages.last)
        let messageId = "msg-\(groupService.sentMessages.count)"
        groupService.emitLive(GroupMessageRecord(
            id: messageId,
            groupId: sent.groupId,
            senderId: senderId,
            epoch: sent.epoch,
            ciphertext: sent.ciphertext,
            createdAt: "2026-06-03T00:00:00Z"
        ))
        try await Task.sleep(nanoseconds: 50_000_000)
    }

    @MainActor
    private func makeHarness(
        username: String = "alice",
        userId: String = "user-a",
        token: String = "token-1",
        messageService: FakeGroupMessageService = FakeGroupMessageService(),
        groupService: FakeGroupService = FakeGroupService()
    ) throws -> Harness {
        let sessionKeychain = KeychainStore(
            service: "\(KeychainStore.defaultService).group.tests.\(UUID().uuidString)",
            account: "\(KeychainStore.defaultAccount).session.tests",
            usesDataProtectionKeychain: false
        )
        let x25519Keychain = KeychainStore(
            service: "\(KeychainStore.defaultService).group.tests.\(UUID().uuidString)",
            account: "\(KeychainStore.defaultAccount).x25519.tests",
            usesDataProtectionKeychain: false
        )
        keychainStores.append(sessionKeychain)
        keychainStores.append(x25519Keychain)

        let sessionStore = SessionStore(keychainStore: sessionKeychain)
        try sessionStore.save(token)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("group-coordinator-\(UUID().uuidString)", isDirectory: true)
        cleanupURLs.append(directory)
        let accountStore = LocalAccountStore(directory: directory)
        let identity = CryptoIdentity(privateKey: Curve25519.Signing.PrivateKey())
        try accountStore.save(LocalAccount(username: username, publicKeyBase64: identity.publicKeyBase64, userId: userId))

        let x25519 = X25519KeyManager(keychainStore: x25519Keychain)
        _ = try x25519.loadOrCreate()
        let localX25519Public = try x25519.publicKeyBase64()
        let localSignature = MessageCrypto().signPrekey(x25519PublicKeyBase64: localX25519Public, with: identity)
        messageService.prekeys[username] = PrekeyResponse(
            userId: userId,
            username: username,
            identityPublicKey: identity.publicKeyBase64,
            x25519PublicKey: localX25519Public,
            keySignature: localSignature
        )

        let attachmentService = FakeAttachmentService()
        let coordinator = GroupCoordinator(
            identityProvider: StubGroupIdentityProvider(identity: identity),
            x25519KeyManager: x25519,
            sessionStore: sessionStore,
            accountStore: accountStore,
            messageService: messageService,
            groupService: groupService,
            crypto: GroupCrypto(),
            attachmentService: attachmentService,
            fileCrypto: FileCrypto()
        )
        return Harness(
            coordinator: coordinator,
            messageService: messageService,
            groupService: groupService,
            attachmentService: attachmentService,
            x25519: x25519
        )
    }
}

private struct Harness {
    let coordinator: GroupCoordinator
    let messageService: FakeGroupMessageService
    let groupService: FakeGroupService
    let attachmentService: FakeAttachmentService
    let x25519: X25519KeyManager

    func addVerifiedPrekey(username: String, userId: String, key: Curve25519.KeyAgreement.PrivateKey) throws {
        let identity = CryptoIdentity(privateKey: Curve25519.Signing.PrivateKey())
        let x25519Public = key.publicKey.rawRepresentation.base64EncodedString()
        let signature = MessageCrypto().signPrekey(x25519PublicKeyBase64: x25519Public, with: identity)
        messageService.prekeys[username] = PrekeyResponse(
            userId: userId,
            username: username,
            identityPublicKey: identity.publicKeyBase64,
            x25519PublicKey: x25519Public,
            keySignature: signature
        )
    }
}

private struct StubGroupIdentityProvider: IdentityProviding {
    let identity: CryptoIdentity

    func loadOrCreate() throws -> CryptoIdentity {
        identity
    }
}

private final class FakeGroupMessageService: MessageService, @unchecked Sendable {
    var prekeys: [String: PrekeyResponse] = [:]

    func publishPrekey(token: String, x25519PublicKey: String, signature: String) async -> Bool {
        true
    }

    func fetchPrekey(username: String, token: String) async -> PrekeyResponse? {
        prekeys[username]
    }

    func send(token: String, recipientUsername: String, ciphertext: String) async -> SendMessageResult {
        .failure("unused")
    }

    func history(token: String, withUsername username: String, since: String?) async -> [MessageRecord] {
        []
    }

    func inbox(token: String, since: Int) async -> InboxPage {
        InboxPage(messages: [], nextCursor: nil)
    }

    func conversations(token: String) async -> [ConversationSummary] {
        []
    }

    func liveMessages(token: String) -> AsyncThrowingStream<MessageRecord, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

private final class FakeGroupService: GroupService, @unchecked Sendable {
    var createRequests: [(name: String, members: [GroupMemberKeyDTO])] = []
    var addRequests: [(groupId: String, username: String, epoch: UInt32, keys: [WrappedKeyDTO])] = []
    var sentMessages: [(groupId: String, epoch: UInt32, ciphertext: String)] = []
    var listedGroups: [GroupSummary] = []
    var listTokens: [String] = []
    var keysByGroup: [String: [GroupKeyRecord]] = [:]
    var keysByGroupAndToken: [String: [String: [GroupKeyRecord]]] = [:]
    var keyFetchSequenceByGroup: [String: [[GroupKeyRecord]]] = [:]
    var fetchKeysCalls: [String] = []
    var historyByGroup: [String: [GroupMessageRecord]] = [:]
    var liveRecordsByGroup: [String: [GroupMessageRecord]] = [:]
    var liveSubscriptions: [(groupId: String, token: String)] = []
    private var liveContinuations: [AsyncThrowingStream<GroupMessageRecord, Error>.Continuation] = []
    private var epochHandlers: [@Sendable (GroupEpochEvent) -> Void] = []

    private var details: [String: GroupDetail] = [
        "group-1": GroupDetail(
            id: "group-1",
            name: "Ops",
            creatorId: "user-a",
            currentEpoch: 0,
            createdAt: "2026-06-03T00:00:00Z",
            members: [
                GroupMemberDTO(userId: "user-a", username: "alice", joinedEpoch: 0),
                GroupMemberDTO(userId: "user-b", username: "bob", joinedEpoch: 0)
            ]
        )
    ]
    private let userIdsByUsername = [
        "alice": "user-a",
        "bob": "user-b",
        "carol": "user-c",
        "dave": "user-d"
    ]

    func createGroup(token: String, name: String, members: [GroupMemberKeyDTO]) async -> CreateGroupResponse? {
        createRequests.append((name, members))
        let refs = members.map { member in
            GroupMemberRefDTO(userId: userIdsByUsername[member.username] ?? "user-\(member.username)", username: member.username)
        }
        details["group-1"] = GroupDetail(
            id: "group-1",
            name: name,
            creatorId: "user-a",
            currentEpoch: 0,
            createdAt: "2026-06-03T00:00:00Z",
            members: refs.map { GroupMemberDTO(userId: $0.userId, username: $0.username, joinedEpoch: 0) }
        )
        return CreateGroupResponse(groupId: "group-1", epoch: 0, members: refs)
    }

    func listGroups(token: String) async -> [GroupSummary] {
        listTokens.append(token)
        return listedGroups
    }

    func fetchGroup(id: String, token: String) async -> GroupDetail? {
        details[id]
    }

    func setDetail(groupId: String, currentEpoch: UInt32) {
        guard let detail = details[groupId] else {
            return
        }
        details[groupId] = GroupDetail(
            id: detail.id,
            name: detail.name,
            creatorId: detail.creatorId,
            currentEpoch: currentEpoch,
            createdAt: detail.createdAt,
            members: detail.members
        )
    }

    func addMember(
        groupId: String,
        token: String,
        username: String,
        epoch: UInt32,
        keys: [WrappedKeyDTO]
    ) async -> AddMemberResponse? {
        addRequests.append((groupId, username, epoch, keys))
        var detail = details[groupId]!
        let newMember = GroupMemberDTO(
            userId: userIdsByUsername[username] ?? "user-\(username)",
            username: username,
            joinedEpoch: epoch
        )
        detail = GroupDetail(
            id: detail.id,
            name: detail.name,
            creatorId: detail.creatorId,
            currentEpoch: epoch,
            createdAt: detail.createdAt,
            members: detail.members + [newMember]
        )
        details[groupId] = detail
        return AddMemberResponse(epoch: epoch, member: GroupMemberRefDTO(userId: newMember.userId, username: newMember.username))
    }

    func fetchKeys(groupId: String, token: String) async -> [GroupKeyRecord] {
        fetchKeysCalls.append(groupId)
        if var sequence = keyFetchSequenceByGroup[groupId], !sequence.isEmpty {
            let next = sequence.removeFirst()
            keyFetchSequenceByGroup[groupId] = sequence
            return next
        }
        if let records = keysByGroupAndToken[groupId]?[token] {
            return records
        }
        return keysByGroup[groupId] ?? []
    }

    func sendGroupMessage(groupId: String, token: String, epoch: UInt32, ciphertext: String) async -> SendGroupMessageResult {
        sentMessages.append((groupId, epoch, ciphertext))
        return .success(messageId: "msg-\(sentMessages.count)", createdAt: "2026-06-03T00:00:00Z", epoch: epoch)
    }

    func groupHistory(groupId: String, token: String, since: String?) async -> [GroupMessageRecord] {
        historyByGroup[groupId] ?? []
    }

    func liveGroupMessages(
        groupId: String,
        token: String,
        onEpochChange: (@Sendable (GroupEpochEvent) -> Void)?
    ) -> AsyncThrowingStream<GroupMessageRecord, Error> {
        liveSubscriptions.append((groupId, token))
        if let onEpochChange {
            epochHandlers.append(onEpochChange)
        }
        let records = liveRecordsByGroup[groupId] ?? []
        return AsyncThrowingStream { continuation in
            liveContinuations.append(continuation)
            Task {
                for record in records {
                    continuation.yield(record)
                    await Task.yield()
                }
            }
        }
    }

    func emitLive(_ record: GroupMessageRecord) {
        for continuation in liveContinuations {
            continuation.yield(record)
        }
    }

    func emitEpoch(_ event: GroupEpochEvent) {
        for handler in epochHandlers {
            handler(event)
        }
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
