import Foundation

struct CreateGroupRequest: Codable, Equatable {
    let name: String
    let members: [GroupMemberKeyDTO]
}

struct GroupMemberKeyDTO: Codable, Equatable {
    let username: String
    let wrappedKey: String

    enum CodingKeys: String, CodingKey {
        case username
        case wrappedKey = "wrapped_key"
    }
}

struct CreateGroupResponse: Codable, Equatable {
    let groupId: String
    let epoch: UInt32
    let members: [GroupMemberRefDTO]

    enum CodingKeys: String, CodingKey {
        case groupId = "group_id"
        case epoch
        case members
    }
}

struct GroupMemberRefDTO: Codable, Equatable {
    let userId: String
    let username: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
    }
}

struct GroupSummary: Codable, Equatable {
    let id: String
    let name: String
    let creatorId: String
    let currentEpoch: UInt32
    let joinedEpoch: UInt32
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case creatorId = "creator_id"
        case currentEpoch = "current_epoch"
        case joinedEpoch = "joined_epoch"
        case createdAt = "created_at"
    }
}

struct GroupDetail: Codable, Equatable {
    let id: String
    let name: String
    let creatorId: String
    let currentEpoch: UInt32
    let createdAt: String
    let members: [GroupMemberDTO]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case creatorId = "creator_id"
        case currentEpoch = "current_epoch"
        case createdAt = "created_at"
        case members
    }
}

struct GroupMemberDTO: Codable, Equatable {
    let userId: String
    let username: String
    let joinedEpoch: UInt32

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
        case joinedEpoch = "joined_epoch"
    }
}

struct AddMemberRequest: Codable, Equatable {
    let username: String
    let epoch: UInt32
    let keys: [WrappedKeyDTO]
}

struct WrappedKeyDTO: Codable, Equatable {
    let memberId: String
    let wrappedKey: String

    enum CodingKeys: String, CodingKey {
        case memberId = "member_id"
        case wrappedKey = "wrapped_key"
    }
}

struct AddMemberResponse: Codable, Equatable {
    let epoch: UInt32
    let member: GroupMemberRefDTO
}

struct GroupKeyRecord: Codable, Equatable {
    let epoch: UInt32
    let wrappedKey: String

    enum CodingKeys: String, CodingKey {
        case epoch
        case wrappedKey = "wrapped_key"
    }
}

struct SendGroupMessageRequest: Codable, Equatable {
    let epoch: UInt32
    let ciphertext: String
}

struct SendGroupMessageResponse: Codable, Equatable {
    let messageId: String
    let createdAt: String
    let epoch: UInt32

    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case createdAt = "created_at"
        case epoch
    }
}

struct GroupMessageRecord: Codable, Equatable {
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

struct GroupHistoryResponse: Codable, Equatable {
    let messages: [GroupMessageRecord]
}
