import Foundation
import UniformTypeIdentifiers
import OSLog

private let signposter = OSSignposter(subsystem: "com.patchpals.api", category: "APIClient")

struct APIError: LocalizedError {
    let detail: String

    var errorDescription: String? { detail }

    private struct ErrorBody: Decodable {
        let detail: String
    }

    static func from(_ data: Data, statusCode: Int) -> APIError {
        if let body = try? JSONDecoder().decode(ErrorBody.self, from: data) {
            return APIError(detail: body.detail)
        }
        return APIError(detail: "Request failed with status \(statusCode).")
    }
}

final class APIClient {
    static let shared = APIClient()

    private init() {}

    private let baseURL = URL(string: "https://api.18-191-85-231.nip.io")!

    func createUser(email: String, password: String) async throws -> UserCreateResponse {
        let url = baseURL.appendingPathComponent("users")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(UserCreateResponse.self, from: data)
    }

    func fetchPacks(requesterID: String) async throws -> [Pack] {
        let state = signposter.beginInterval("APIClient - network fetch sticker packs", id: .exclusive)
        defer { signposter.endInterval("APIClient - network fetch sticker packs", state) }

        var components = URLComponents(
            url: baseURL.appendingPathComponent("packs"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "requester_id", value: requesterID)]

        let (data, response) = try await URLSession.shared.data(from: components.url!)
        try validate(response: response, data: data)
        return try JSONDecoder().decode([Pack].self, from: data)
    }

    func createPack(name: String, description: String?, ownerID: String) async throws -> Pack {
        let url = baseURL.appendingPathComponent("packs")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: String] = ["name": name, "owner_id": ownerID]
        if let description, !description.isEmpty {
            body["description"] = description
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(Pack.self, from: data)
    }

    func deletePack(packID: String, requesterID: String) async throws {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("packs/\(packID)"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "requester_id", value: requesterID)]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "DELETE"

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
    }

    func addMember(packID: String, requesterID: String, userID: String, role: PackRole) async throws -> Member {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("packs/\(packID)/members"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "requester_id", value: requesterID)]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["user_id": userID, "role": role.rawValue])

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(Member.self, from: data)
    }

    func removeMember(packID: String, requesterID: String, userID: String) async throws {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("packs/\(packID)/members/\(userID)"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "requester_id", value: requesterID)]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "DELETE"

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
    }

    func fetchStickers(packID: String, userID: String) async throws -> [Sticker] {
        let state = signposter.beginInterval("APIClient - network fetch stickers", id: .exclusive, "\(packID)")
        defer { signposter.endInterval("APIClient - network fetch stickers", state, "\(packID)") }

        var components = URLComponents(
            url: baseURL.appendingPathComponent("packs/\(packID)/stickers"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "user_id", value: userID)]

        let (data, response) = try await URLSession.shared.data(from: components.url!)
        try validate(response: response, data: data)
        return try JSONDecoder().decode([Sticker].self, from: data)
    }

    func deleteSticker(stickerID: String, userID: String) async throws {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("stickers/\(stickerID)"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "user_id", value: userID)]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "DELETE"

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
    }

    func uploadSticker(packID: String, userID: String, imageData: Data, contentType: String) async throws -> Sticker {
        let uploadInfo = try await getUploadURL(packID: packID, userID: userID)
        try await uploadImageToS3(uploadURL: uploadInfo.uploadURL, imageData: imageData, contentType: contentType)
        return try await createSticker(packID: packID, userID: userID, s3Key: uploadInfo.s3Key)
    }

    private func getUploadURL(packID: String, userID: String) async throws -> UploadURLResponse {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("packs/\(packID)/stickers/upload-url"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "user_id", value: userID)]

        let (data, response) = try await URLSession.shared.data(from: components.url!)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(UploadURLResponse.self, from: data)
    }

    private func uploadImageToS3(uploadURL: String, imageData: Data, contentType: String) async throws {
        guard let url = URL(string: uploadURL) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")

        let (_, response) = try await URLSession.shared.upload(for: request, from: imageData)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw APIError(detail: "Failed to upload image to storage.")
        }
    }

    private func createSticker(packID: String, userID: String, s3Key: String) async throws -> Sticker {
        let url = baseURL.appendingPathComponent("packs/\(packID)/stickers")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["user_id": userID, "s3_key": s3Key])

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(Sticker.self, from: data)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError(detail: "Invalid server response.")
        }
        guard 200..<300 ~= http.statusCode else {
            throw APIError.from(data, statusCode: http.statusCode)
        }
    }
}
