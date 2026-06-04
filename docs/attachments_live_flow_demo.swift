import CryptoKit
import Foundation

enum DemoError: Error, CustomStringConvertible {
    case usage
    case badURL(String)
    case http(String)
    case decode(String)
    case timeout(String)
    case crypto(String)
    case assertion(String)

    var description: String {
        switch self {
        case .usage:
            return "usage: swift docs/attachments_live_flow_demo.swift <backend-url> <output-dir>"
        case let .badURL(value):
            return "invalid backend URL: \(value)"
        case let .http(message), let .decode(message), let .timeout(message),
             let .crypto(message), let .assertion(message):
            return message
        }
    }
}

struct RegisterRequest: Encodable {
    let username: String
    let identityPublicKey: String

    enum CodingKeys: String, CodingKey {
        case username
        case identityPublicKey = "identity_public_key"
    }
}

struct RegisterResponse: Decodable {
    let userId: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
    }
}

struct ChallengeRequest: Encodable {
    let username: String
}

struct ChallengeResponse: Decodable {
    let challengeId: String
    let nonce: String

    enum CodingKeys: String, CodingKey {
        case challengeId = "challenge_id"
        case nonce
    }
}

struct VerifyRequest: Encodable {
    let challengeId: String
    let signature: String

    enum CodingKeys: String, CodingKey {
        case challengeId = "challenge_id"
        case signature
    }
}

struct VerifyResponse: Decodable {
    let token: String
    let userId: String
    let username: String

    enum CodingKeys: String, CodingKey {
        case token
        case userId = "user_id"
        case username
    }
}

struct PublishPrekeyRequest: Encodable {
    let x25519PublicKey: String
    let keySignature: String

    enum CodingKeys: String, CodingKey {
        case x25519PublicKey = "x25519_public_key"
        case keySignature = "key_signature"
    }
}

struct PrekeyResponse: Decodable {
    let userId: String
    let username: String
    let identityPublicKey: String
    let x25519PublicKey: String
    let keySignature: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
        case identityPublicKey = "identity_public_key"
        case x25519PublicKey = "x25519_public_key"
        case keySignature = "key_signature"
    }
}

struct UploadAttachmentResponse: Decodable {
    let attachmentId: String

    enum CodingKeys: String, CodingKey {
        case attachmentId = "attachment_id"
    }
}

struct AttachmentDescriptor: Codable {
    let chatapp: String
    let version: Int
    let attachmentId: String
    let fileKey: String
    let filename: String
    let mime: String
    let size: Int

    enum CodingKeys: String, CodingKey {
        case chatapp
        case version = "v"
        case attachmentId = "attachment_id"
        case fileKey = "file_key"
        case filename
        case mime
        case size
    }
}

struct SendMessageRequest: Encodable {
    let recipientUsername: String
    let ciphertext: String

    enum CodingKeys: String, CodingKey {
        case recipientUsername = "recipient_username"
        case ciphertext
    }
}

struct MessageRecord: Decodable {
    let id: String
    let senderId: String
    let recipientId: String
    let ciphertext: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case senderId = "sender_id"
        case recipientId = "recipient_id"
        case ciphertext
        case createdAt = "created_at"
    }
}

struct GroupMemberKeyRequest: Encodable {
    let username: String
    let wrappedKey: String

    enum CodingKeys: String, CodingKey {
        case username
        case wrappedKey = "wrapped_key"
    }
}

struct CreateGroupRequest: Encodable {
    let name: String
    let members: [GroupMemberKeyRequest]
}

struct CreateGroupResponse: Decodable {
    let groupId: String
    let epoch: UInt32

    enum CodingKeys: String, CodingKey {
        case groupId = "group_id"
        case epoch
    }
}

struct GroupKeyRecord: Decodable {
    let epoch: UInt32
    let wrappedKey: String

    enum CodingKeys: String, CodingKey {
        case epoch
        case wrappedKey = "wrapped_key"
    }
}

struct SendGroupMessageRequest: Encodable {
    let epoch: UInt32
    let ciphertext: String
}

struct GroupMessageRecord: Decodable {
    let id: String
    let groupId: String
    let senderId: String
    let epoch: UInt32
    let ciphertext: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case groupId = "group_id"
        case senderId = "sender_id"
        case epoch
        case ciphertext
        case createdAt = "created_at"
    }
}

struct DemoUser {
    let username: String
    let userId: String
    let token: String
    let identity: Curve25519.Signing.PrivateKey
    let x25519: Curve25519.KeyAgreement.PrivateKey
}

final class DemoClient {
    private let baseURL: URL
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func makeUser(prefix: String) async throws -> DemoUser {
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12)
        let username = "\(prefix)_\(suffix)"
        let identity = Curve25519.Signing.PrivateKey()
        let x25519 = Curve25519.KeyAgreement.PrivateKey()
        let registration: RegisterResponse = try await post(
            ["register"],
            RegisterRequest(
                username: username,
                identityPublicKey: identity.publicKey.rawRepresentation.base64EncodedString()
            ),
            expected: [201]
        )
        let challenge: ChallengeResponse = try await post(
            ["auth", "challenge"],
            ChallengeRequest(username: username),
            expected: [201]
        )
        guard let nonce = Data(base64Encoded: challenge.nonce) else {
            throw DemoError.decode("auth challenge nonce was not valid base64")
        }
        let signature = try identity.signature(for: nonce).base64EncodedString()
        let verification: VerifyResponse = try await post(
            ["auth", "verify"],
            VerifyRequest(challengeId: challenge.challengeId, signature: signature),
            expected: [200]
        )
        guard verification.username == username, verification.userId == registration.userId else {
            throw DemoError.assertion("auth verification returned the wrong identity")
        }
        let prekey = x25519.publicKey.rawRepresentation
        let prekeySignature = try identity.signature(for: prekey).base64EncodedString()
        try await put(
            ["keys"],
            PublishPrekeyRequest(
                x25519PublicKey: prekey.base64EncodedString(),
                keySignature: prekeySignature
            ),
            token: verification.token,
            expected: [200, 201]
        )
        return DemoUser(
            username: username,
            userId: registration.userId,
            token: verification.token,
            identity: identity,
            x25519: x25519
        )
    }

    func fetchPrekey(username: String, token: String) async throws -> PrekeyResponse {
        try await get(["keys", username], token: token)
    }

    func uploadAttachment(token: String, encryptedBlob: Data) async throws -> String {
        var request = URLRequest(url: url(["attachments"]))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.httpBody = encryptedBlob
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 201 else {
            throw DemoError.http("POST /attachments failed")
        }
        return try decoder.decode(UploadAttachmentResponse.self, from: data).attachmentId
    }

    func downloadAttachment(token: String, attachmentId: String) async throws -> Data {
        var request = URLRequest(url: url(["attachments", attachmentId]))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw DemoError.http("GET /attachments/\(attachmentId) failed")
        }
        return data
    }

    func sendDM(token: String, recipientUsername: String, ciphertext: String) async throws {
        struct SendResponse: Decodable {}
        let _: SendResponse = try await post(
            ["messages"],
            SendMessageRequest(recipientUsername: recipientUsername, ciphertext: ciphertext),
            token: token,
            expected: [200, 201]
        )
    }

    func liveDM(token: String) -> AsyncThrowingStream<MessageRecord, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: url(["messages", "stream"]))
                    request.httpMethod = "GET"
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        throw DemoError.http("DM live stream failed to connect")
                    }
                    for try await line in bytes.lines {
                        guard !Task.isCancelled else { break }
                        if let record: MessageRecord = try parseSSEData(line) {
                            continuation.yield(record)
                        }
                    }
                    continuation.finish()
                } catch {
                    Task.isCancelled ? continuation.finish() : continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func createGroup(token: String, name: String, members: [GroupMemberKeyRequest]) async throws -> CreateGroupResponse {
        try await post(["groups"], CreateGroupRequest(name: name, members: members), token: token, expected: [200, 201])
    }

    func fetchGroupKeys(groupId: String, token: String) async throws -> [GroupKeyRecord] {
        try await get(["groups", groupId, "keys"], token: token)
    }

    func sendGroupMessage(groupId: String, token: String, epoch: UInt32, ciphertext: String) async throws {
        struct SendResponse: Decodable {}
        let _: SendResponse = try await post(
            ["groups", groupId, "messages"],
            SendGroupMessageRequest(epoch: epoch, ciphertext: ciphertext),
            token: token,
            expected: [200, 201]
        )
    }

    func liveGroup(groupId: String, token: String) -> AsyncThrowingStream<GroupMessageRecord, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: url(["groups", groupId, "stream"]))
                    request.httpMethod = "GET"
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        throw DemoError.http("group live stream failed to connect")
                    }
                    var eventName: String?
                    for try await line in bytes.lines {
                        guard !Task.isCancelled else { break }
                        if line.isEmpty {
                            eventName = nil
                            continue
                        }
                        if line.hasPrefix("event:") {
                            eventName = String(line.dropFirst("event:".count)).trimmingCharacters(in: .whitespaces)
                            continue
                        }
                        if eventName == nil, let record: GroupMessageRecord = try parseSSEData(line) {
                            continuation.yield(record)
                        }
                    }
                    continuation.finish()
                } catch {
                    Task.isCancelled ? continuation.finish() : continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func get<T: Decodable>(_ path: [String], token: String) async throws -> T {
        var request = URLRequest(url: url(path))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw DemoError.http("GET /\(path.joined(separator: "/")) failed")
        }
        return try decoder.decode(T.self, from: data)
    }

    private func post<T: Encodable, U: Decodable>(
        _ path: [String],
        _ payload: T,
        token: String? = nil,
        expected: Set<Int>
    ) async throws -> U {
        var request = URLRequest(url: url(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try encoder.encode(payload)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, expected.contains(http.statusCode) else {
            throw DemoError.http("POST /\(path.joined(separator: "/")) failed")
        }
        return try decoder.decode(U.self, from: data)
    }

    private func put<T: Encodable>(
        _ path: [String],
        _ payload: T,
        token: String,
        expected: Set<Int>
    ) async throws {
        var request = URLRequest(url: url(path))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(payload)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, expected.contains(http.statusCode) else {
            throw DemoError.http("PUT /\(path.joined(separator: "/")) failed")
        }
    }

    private func url(_ path: [String]) -> URL {
        path.reduce(baseURL) { partial, component in
            partial.appendingPathComponent(component)
        }
    }
}

struct MessageCrypto {
    private static let version: UInt8 = 0x01
    private static let sharedInfo = Data("chatapp-dm-v1".utf8)

    func encrypt(_ plaintext: Data, to recipientBase64: String) throws -> String {
        guard let publicKeyData = Data(base64Encoded: recipientBase64) else {
            throw DemoError.crypto("recipient prekey was not base64")
        }
        let recipient = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: publicKeyData)
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let secret = try ephemeral.sharedSecretFromKeyAgreement(with: recipient)
        let key = secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data(), sharedInfo: Self.sharedInfo, outputByteCount: 32)
        guard let combined = try AES.GCM.seal(plaintext, using: key).combined else {
            throw DemoError.crypto("DM seal did not produce combined data")
        }
        var envelope = Data([Self.version])
        envelope.append(ephemeral.publicKey.rawRepresentation)
        envelope.append(combined)
        return envelope.base64EncodedString()
    }

    func decrypt(_ envelopeBase64: String, with localPrivate: Curve25519.KeyAgreement.PrivateKey) throws -> Data {
        guard let envelope = Data(base64Encoded: envelopeBase64), envelope.count > 33, envelope.first == Self.version else {
            throw DemoError.crypto("invalid DM envelope")
        }
        let publicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: envelope[1..<33])
        let combined = envelope[33..<envelope.count]
        let secret = try localPrivate.sharedSecretFromKeyAgreement(with: publicKey)
        let key = secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data(), sharedInfo: Self.sharedInfo, outputByteCount: 32)
        return try AES.GCM.open(AES.GCM.SealedBox(combined: Data(combined)), using: key)
    }
}

struct GroupCrypto {
    private static let version: UInt8 = 0x02

    func encrypt(_ plaintext: Data, epoch: UInt32, groupKey: Data) throws -> String {
        guard let combined = try AES.GCM.seal(plaintext, using: SymmetricKey(data: groupKey)).combined else {
            throw DemoError.crypto("group seal did not produce combined data")
        }
        var envelope = Data([Self.version])
        var beEpoch = epoch.bigEndian
        withUnsafeBytes(of: &beEpoch) { envelope.append(contentsOf: $0) }
        envelope.append(combined)
        return envelope.base64EncodedString()
    }

    func decrypt(_ envelopeBase64: String, groupKey: Data) throws -> Data {
        guard let envelope = Data(base64Encoded: envelopeBase64), envelope.count > 5, envelope.first == Self.version else {
            throw DemoError.crypto("invalid group envelope")
        }
        return try AES.GCM.open(AES.GCM.SealedBox(combined: Data(envelope[5..<envelope.count])), using: SymmetricKey(data: groupKey))
    }
}

struct FileCrypto {
    func newFileKey() -> Data {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }

    func encrypt(_ plaintext: Data, using key: Data) throws -> Data {
        guard let combined = try AES.GCM.seal(plaintext, using: SymmetricKey(data: key)).combined else {
            throw DemoError.crypto("file seal did not produce combined data")
        }
        return combined
    }

    func decrypt(_ encryptedBlob: Data, using key: Data) throws -> Data {
        try AES.GCM.open(AES.GCM.SealedBox(combined: encryptedBlob), using: SymmetricKey(data: key))
    }
}

func parseSSEData<T: Decodable>(_ line: String) throws -> T? {
    guard line.hasPrefix("data:") else {
        return nil
    }
    let json = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
    guard let data = json.data(using: .utf8) else {
        throw DemoError.decode("SSE data was not UTF-8")
    }
    return try JSONDecoder().decode(T.self, from: data)
}

func awaitFirst<S: AsyncSequence>(
    from sequence: S,
    named name: String,
    where predicate: @escaping (S.Element) -> Bool
) async throws -> S.Element where S.Element: Sendable {
    try await withThrowingTaskGroup(of: S.Element.self) { group in
        group.addTask {
            for try await element in sequence {
                if predicate(element) {
                    return element
                }
            }
            throw DemoError.timeout("\(name) stream ended before the expected event arrived")
        }
        group.addTask {
            try await Task.sleep(nanoseconds: 8_000_000_000)
            throw DemoError.timeout("timed out waiting for \(name) live event")
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

func makeDescriptor(attachmentId: String, fileKey: Data, filename: String, mime: String, size: Int) throws -> Data {
    let descriptor = AttachmentDescriptor(
        chatapp: "attachment",
        version: 1,
        attachmentId: attachmentId,
        fileKey: fileKey.base64EncodedString(),
        filename: filename,
        mime: mime,
        size: size
    )
    return try JSONEncoder().encode(descriptor)
}

func verifyPrekey(_ prekey: PrekeyResponse) throws {
    guard
        let identity = Data(base64Encoded: prekey.identityPublicKey),
        let x25519 = Data(base64Encoded: prekey.x25519PublicKey),
        let signature = Data(base64Encoded: prekey.keySignature)
    else {
        throw DemoError.crypto("prekey response contained invalid base64")
    }
    let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: identity)
    guard publicKey.isValidSignature(signature, for: x25519) else {
        throw DemoError.crypto("prekey signature did not verify for \(prekey.username)")
    }
}

@main
struct DemoMain {
    static func main() async {
        do {
            try await run()
        } catch {
            fputs("attachments live flow demo failed: \(error)\n", stderr)
            exit(1)
        }
    }

    static func run() async throws {
        guard CommandLine.arguments.count == 3 else {
            throw DemoError.usage
        }
        guard let baseURL = URL(string: CommandLine.arguments[1]) else {
            throw DemoError.badURL(CommandLine.arguments[1])
        }
        let outputDir = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let client = DemoClient(baseURL: baseURL)
        let messageCrypto = MessageCrypto()
        let groupCrypto = GroupCrypto()
        let fileCrypto = FileCrypto()

        let alice = try await client.makeUser(prefix: "demo_alice")
        let bob = try await client.makeUser(prefix: "demo_bob")

        let sentinel = "ATTACHMENT_RENDERED_FLOW_SENTINEL_\(UUID().uuidString)"
        let dmOriginal = Data("DM live attachment \(sentinel)\n".utf8)
        let groupOriginal = Data("Group live attachment \(sentinel)\n".utf8)
        let dmOriginalURL = outputDir.appendingPathComponent("dm-original.txt")
        let dmSavedURL = outputDir.appendingPathComponent("dm-downloaded.txt")
        let groupOriginalURL = outputDir.appendingPathComponent("group-original.txt")
        let groupSavedURL = outputDir.appendingPathComponent("group-downloaded.txt")
        try dmOriginal.write(to: dmOriginalURL)
        try groupOriginal.write(to: groupOriginalURL)

        let bobPrekey = try await client.fetchPrekey(username: bob.username, token: alice.token)
        try verifyPrekey(bobPrekey)

        let dmStream = client.liveDM(token: bob.token)
        try await Task.sleep(nanoseconds: 300_000_000)
        let dmFileKey = fileCrypto.newFileKey()
        let dmEncryptedFile = try fileCrypto.encrypt(dmOriginal, using: dmFileKey)
        guard dmEncryptedFile != dmOriginal else {
            throw DemoError.assertion("DM encrypted blob matched plaintext")
        }
        let dmAttachmentId = try await client.uploadAttachment(token: alice.token, encryptedBlob: dmEncryptedFile)
        let dmDescriptor = try makeDescriptor(
            attachmentId: dmAttachmentId,
            fileKey: dmFileKey,
            filename: "dm-original.txt",
            mime: "text/plain",
            size: dmOriginal.count
        )
        let dmCiphertext = try messageCrypto.encrypt(dmDescriptor, to: bobPrekey.x25519PublicKey)
        let dmWait = Task {
            try await awaitFirst(from: dmStream, named: "DM") { $0.senderId == alice.userId && $0.recipientId == bob.userId }
        }
        try await client.sendDM(token: alice.token, recipientUsername: bob.username, ciphertext: dmCiphertext)
        let dmRecord = try await dmWait.value
        let dmPlainDescriptor = try messageCrypto.decrypt(dmRecord.ciphertext, with: bob.x25519)
        let decodedDMDescriptor = try JSONDecoder().decode(AttachmentDescriptor.self, from: dmPlainDescriptor)
        guard decodedDMDescriptor.attachmentId == dmAttachmentId, decodedDMDescriptor.filename == "dm-original.txt" else {
            throw DemoError.assertion("DM live descriptor did not contain the expected attachment metadata")
        }
        let dmDownloadedEncrypted = try await client.downloadAttachment(token: bob.token, attachmentId: decodedDMDescriptor.attachmentId)
        let dmDownloaded = try fileCrypto.decrypt(dmDownloadedEncrypted, using: dmFileKey)
        guard dmDownloaded == dmOriginal, String(data: dmDownloaded, encoding: .utf8)?.contains(sentinel) == true else {
            throw DemoError.assertion("DM downloaded file was not byte-identical/openable text")
        }
        try dmDownloaded.write(to: dmSavedURL)

        let alicePrekey = try await client.fetchPrekey(username: alice.username, token: alice.token)
        try verifyPrekey(alicePrekey)
        let groupKey = fileCrypto.newFileKey()
        let createGroup = try await client.createGroup(
            token: alice.token,
            name: "Rendered Attachment Demo \(UUID().uuidString.prefix(8))",
            members: [
                GroupMemberKeyRequest(username: alice.username, wrappedKey: try messageCrypto.encrypt(groupKey, to: alicePrekey.x25519PublicKey)),
                GroupMemberKeyRequest(username: bob.username, wrappedKey: try messageCrypto.encrypt(groupKey, to: bobPrekey.x25519PublicKey))
            ]
        )
        let bobGroupKeys = try await client.fetchGroupKeys(groupId: createGroup.groupId, token: bob.token)
        guard let bobEpochZero = bobGroupKeys.first(where: { $0.epoch == createGroup.epoch }) else {
            throw DemoError.assertion("Bob did not receive a wrapped group key for epoch \(createGroup.epoch)")
        }
        let bobGroupKey = try messageCrypto.decrypt(bobEpochZero.wrappedKey, with: bob.x25519)
        guard bobGroupKey == groupKey else {
            throw DemoError.assertion("Bob could not unwrap the group key used by Alice")
        }

        let groupStream = client.liveGroup(groupId: createGroup.groupId, token: bob.token)
        try await Task.sleep(nanoseconds: 300_000_000)
        let groupFileKey = fileCrypto.newFileKey()
        let groupEncryptedFile = try fileCrypto.encrypt(groupOriginal, using: groupFileKey)
        guard groupEncryptedFile != groupOriginal else {
            throw DemoError.assertion("group encrypted blob matched plaintext")
        }
        let groupAttachmentId = try await client.uploadAttachment(token: alice.token, encryptedBlob: groupEncryptedFile)
        let groupDescriptor = try makeDescriptor(
            attachmentId: groupAttachmentId,
            fileKey: groupFileKey,
            filename: "group-original.txt",
            mime: "text/plain",
            size: groupOriginal.count
        )
        let groupCiphertext = try groupCrypto.encrypt(groupDescriptor, epoch: createGroup.epoch, groupKey: groupKey)
        let groupWait = Task {
            try await awaitFirst(from: groupStream, named: "group") { $0.senderId == alice.userId && $0.groupId == createGroup.groupId }
        }
        try await client.sendGroupMessage(
            groupId: createGroup.groupId,
            token: alice.token,
            epoch: createGroup.epoch,
            ciphertext: groupCiphertext
        )
        let groupRecord = try await groupWait.value
        let groupPlainDescriptor = try groupCrypto.decrypt(groupRecord.ciphertext, groupKey: bobGroupKey)
        let decodedGroupDescriptor = try JSONDecoder().decode(AttachmentDescriptor.self, from: groupPlainDescriptor)
        guard decodedGroupDescriptor.attachmentId == groupAttachmentId, decodedGroupDescriptor.filename == "group-original.txt" else {
            throw DemoError.assertion("group live descriptor did not contain the expected attachment metadata")
        }
        let groupDownloadedEncrypted = try await client.downloadAttachment(token: bob.token, attachmentId: decodedGroupDescriptor.attachmentId)
        let groupDownloaded = try fileCrypto.decrypt(groupDownloadedEncrypted, using: groupFileKey)
        guard groupDownloaded == groupOriginal, String(data: groupDownloaded, encoding: .utf8)?.contains(sentinel) == true else {
            throw DemoError.assertion("group downloaded file was not byte-identical/openable text")
        }
        try groupDownloaded.write(to: groupSavedURL)

        print("DM_ORIGINAL=\(dmOriginalURL.path)")
        print("DM_DOWNLOADED=\(dmSavedURL.path)")
        print("GROUP_ORIGINAL=\(groupOriginalURL.path)")
        print("GROUP_DOWNLOADED=\(groupSavedURL.path)")
        print("DM_ATTACHMENT_ID=\(dmAttachmentId)")
        print("GROUP_ATTACHMENT_ID=\(groupAttachmentId)")
        print("LIVE_FLOW=dm,group")
    }
}
