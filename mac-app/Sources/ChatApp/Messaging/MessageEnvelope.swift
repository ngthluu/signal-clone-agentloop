import Foundation

struct PublishPrekeyRequest: Codable, Equatable {
    let x25519PublicKey: String
    let keySignature: String

    enum CodingKeys: String, CodingKey {
        case x25519PublicKey = "x25519_public_key"
        case keySignature = "key_signature"
    }
}

struct PrekeyResponse: Codable, Equatable {
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

struct SendMessageRequest: Codable, Equatable {
    let recipientUsername: String
    let ciphertext: String

    enum CodingKeys: String, CodingKey {
        case recipientUsername = "recipient_username"
        case ciphertext
    }
}

struct SendMessageResponse: Codable, Equatable {
    let messageId: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case createdAt = "created_at"
    }
}

struct MessageRecord: Codable, Equatable {
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
