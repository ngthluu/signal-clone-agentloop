import Foundation

struct ChallengeRequest: Codable, Sendable {
    let username: String
}

struct ChallengeResponse: Codable, Sendable {
    let challengeId: String
    let nonce: String

    enum CodingKeys: String, CodingKey {
        case challengeId = "challenge_id"
        case nonce
    }
}

struct VerifyRequest: Codable, Sendable {
    let challengeId: String
    let signature: String

    enum CodingKeys: String, CodingKey {
        case challengeId = "challenge_id"
        case signature
    }
}

struct VerifyResponse: Codable, Sendable {
    let token: String
    let userId: String
    let username: String

    enum CodingKeys: String, CodingKey {
        case token
        case userId = "user_id"
        case username
    }
}

struct SessionResponse: Codable, Sendable {
    let userId: String
    let username: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
    }
}
