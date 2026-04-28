import Foundation

enum PackRole: String, Codable, CaseIterable {
    case contributor
    case viewer

    var displayName: String {
        switch self {
        case .contributor:
            return "Contributor"
        case .viewer:
            return "Viewer"
        }
    }
}

struct Pack: Identifiable, Codable {
    let id: String
    var name: String
    var description: String?
    let ownerId: String
    var packVersion: Int
    var stickers: [Sticker]?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case ownerId = "owner_id"
        case packVersion = "pack_version"
        case stickersVersion = "stickers_version"
        case stickers
    }

    init(
        id: String,
        name: String,
        description: String?,
        ownerId: String,
        packVersion: Int,
        stickers: [Sticker]? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.ownerId = ownerId
        self.packVersion = packVersion
        self.stickers = stickers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        ownerId = try container.decode(String.self, forKey: .ownerId)
        packVersion = try container.decodeIfPresent(Int.self, forKey: .packVersion)
            ?? container.decodeIfPresent(Int.self, forKey: .stickersVersion)
            ?? 0
        stickers = try container.decodeIfPresent([Sticker].self, forKey: .stickers)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(ownerId, forKey: .ownerId)
        try container.encode(packVersion, forKey: .packVersion)
        try container.encodeIfPresent(stickers, forKey: .stickers)
    }
}

struct PackVersionEntry: Codable {
    let packId: String
    let packVersion: Int

    enum CodingKeys: String, CodingKey {
        case packId = "pack_id"
        case packVersion = "pack_version"
    }
}

struct PackFull: Codable {
    let id: String
    let name: String
    let description: String?
    let ownerId: String
    let packVersion: Int
    let stickers: [Sticker]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case ownerId = "owner_id"
        case packVersion = "pack_version"
        case stickers
    }
}

struct PackWebSocketEvent: Decodable {
    let eventType: String
    let packId: String
    let packVersion: Int

    enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case packId = "pack_id"
        case packVersion = "pack_version"
    }
}

struct Sticker: Identifiable, Codable {
    let id: String
    let packId: String
    let uploadedBy: String
    let s3Key: String
    var downloadURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case packId = "pack_id"
        case uploadedBy = "uploaded_by"
        case s3Key = "s3_key"
        case downloadURL = "download_url"
    }
}

struct UploadURLResponse: Codable {
    let uploadURL: String
    let s3Key: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case uploadURL = "upload_url"
        case s3Key = "s3_key"
        case expiresIn = "expires_in"
    }
}

struct Member: Codable {
    let userId: String
    let packId: String
    let role: PackRole

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case packId = "pack_id"
        case role
    }
}

struct UserCreateResponse: Codable {
    let id: String
    let email: String
}
