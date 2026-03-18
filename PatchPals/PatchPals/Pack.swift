import Foundation

struct Pack: Identifiable, Codable {
    let id: String
    var name: String
    var description: String?
    let ownerId: String
    var stickers: [Sticker]?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case ownerId = "owner_id"
        case stickers
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
