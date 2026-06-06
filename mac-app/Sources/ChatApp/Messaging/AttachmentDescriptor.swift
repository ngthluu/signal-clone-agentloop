import Foundation

struct AttachmentDescriptor: Codable, Equatable, Sendable {
    let chatapp: String
    let v: Int
    let attachmentId: String
    let fileKey: String
    let filename: String
    let mime: String
    let size: Int
    let encryptedBlob: String?

    init(
        chatapp: String = "attachment",
        v: Int = 1,
        attachmentId: String,
        fileKey: String,
        filename: String,
        mime: String,
        size: Int,
        encryptedBlob: String? = nil
    ) {
        self.chatapp = chatapp
        self.v = v
        self.attachmentId = attachmentId
        self.fileKey = fileKey
        self.filename = filename
        self.mime = mime
        self.size = size
        self.encryptedBlob = encryptedBlob
    }

    func encodedJSON() throws -> Data {
        try JSONEncoder().encode(self)
    }

    static func decode(_ plaintext: Data) -> AttachmentDescriptor? {
        guard
            let descriptor = try? JSONDecoder().decode(AttachmentDescriptor.self, from: plaintext),
            descriptor.chatapp == "attachment"
        else {
            return nil
        }

        return descriptor
    }

    enum CodingKeys: String, CodingKey {
        case chatapp
        case v
        case attachmentId = "attachment_id"
        case fileKey = "file_key"
        case filename
        case mime
        case size
        case encryptedBlob = "encrypted_blob"
    }
}

struct AttachmentInfo: Equatable, Sendable {
    let attachmentId: String
    let filename: String
    let mime: String
    let size: Int
    let fileKey: String
    let encryptedBlob: String?

    init(descriptor: AttachmentDescriptor) {
        attachmentId = descriptor.attachmentId
        filename = descriptor.filename
        mime = descriptor.mime
        size = descriptor.size
        fileKey = descriptor.fileKey
        encryptedBlob = descriptor.encryptedBlob
    }
}
