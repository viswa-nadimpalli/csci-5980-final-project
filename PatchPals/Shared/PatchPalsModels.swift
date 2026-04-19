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
        case stickers
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
    let downloadURL: String?

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
