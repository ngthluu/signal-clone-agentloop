import Foundation

struct RegisterPayload: Encodable {
    let username: String
    let identityPublicKey: String

    enum CodingKeys: String, CodingKey {
        case username
        case identityPublicKey = "identity_public_key"
    }
}
