import Foundation

final class APIClient {
    static let shared = APIClient()

    private init() {}

//    private let baseURL = URL(string: "http://127.0.0.1:3001")!
    private let baseURL = URL(string: "https://api.18-191-85-231.nip.io")!

    func fetchPacks(requesterID: String) async throws -> [Pack] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("packs"),
            resolvingAgainstBaseURL: false
        )!

        components.queryItems = [
            URLQueryItem(name: "requester_id", value: requesterID)
        ]

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode([Pack].self, from: data)
    }

    func fetchStickers(packID: String, userID: String) async throws -> [Sticker] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("packs/\(packID)/stickers"),
            resolvingAgainstBaseURL: false
        )!

        components.queryItems = [
            URLQueryItem(name: "user_id", value: userID)
        ]

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode([Sticker].self, from: data)
    }

    // Delete Function
   func deleteSticker(stickerID: String, userID: String) async throws {
        var components = URLComponents(
           url: baseURL.appendingPathComponent("stickers/\(stickerID)"),
           resolvingAgainstBaseURL: false
       )!

       components.queryItems = [
           URLQueryItem(name: "user_id", value: userID)
       ]

       guard let url = components.url else {
           throw URLError(.badURL)
       }

       var request = URLRequest(url: url)
       request.httpMethod = "DELETE"

       let (_, response) = try await URLSession.shared.data(for: request)

       guard let httpResponse = response as? HTTPURLResponse,
           200..<300 ~= httpResponse.statusCode else {
           throw URLError(.badServerResponse)
       }
   }

   // Upload Sticker Functions

   // Getting upload URL
   func getUploadURL(packID: String, userID: String) async throws -> UploadURLResponse {
       var components = URLComponents(
           url: baseURL.appendingPathComponent("packs/\(packID)/stickers/upload-url"),
           resolvingAgainstBaseURL: false
       )!

       components.queryItems = [
           URLQueryItem(name: "user_id", value: userID)
       ]

       guard let url = components.url else {
           throw URLError(.badURL)
       }

       let (data, response) = try await URLSession.shared.data(from: url)

       guard let httpResponse = response as? HTTPURLResponse,
           200..<300 ~= httpResponse.statusCode else {
           throw URLError(.badServerResponse)
       }
   
       return try JSONDecoder().decode(UploadURLResponse.self, from: data)
   }

   // Uploading image bytes to the url
   func uploadImageToURL(uploadURL: String, imageData: Data) async throws {
       guard let url = URL(string: uploadURL) else {
           throw URLError(.badURL)
       }

       var request = URLRequest(url: url)
       request.httpMethod = "PUT"
       // If stickers are jpegs, change image type to image/jpeg
       request.setValue("image/png", forHTTPHeaderField: "Content-Type")

       let (_, response) = try await URLSession.shared.upload(for: request, from:imageData)

       guard let httpResponse = response as? HTTPURLResponse,
           200..<300 ~= httpResponse.statusCode else {
           throw URLError(.badServerResponse)
       }
   }

   // Registering Sticker in backend
   func createSticker(packID: String, userID: String, s3Key: String) async throws -> Sticker {
       let url = baseURL.appendingPathComponent("packs/\(packID)/stickers")

       var request = URLRequest(url: url)
       request.httpMethod = "POST"
       request.setValue("application/json", forHTTPHeaderField: "Content-Type")
   
       let body: [String: String] = [
           "user_id": userID,
           "s3_key": s3Key
       ]

       request.httpBody = try JSONSerialization.data(withJSONObject: body)

       let (data, response) = try await URLSession.shared.data(for: request)
   

       guard let httpResponse = response as? HTTPURLResponse,
               200..<300 ~= httpResponse.statusCode else {
               throw URLError(.badServerResponse)
           }

       return try JSONDecoder().decode(Sticker.self, from: data)
   }

   // Wrapping all 3 functions into 1 helper function
   func uploadSticker(packID: String, userID: String, imageData: Data) async throws -> Sticker {
       let uploadInfo = try await getUploadURL(packID: packID, userID: userID)
       try await uploadImageToURL(uploadURL: uploadInfo.uploadURL, imageData: imageData)
       return try await createSticker(packID: packID, userID: userID, s3Key: uploadInfo.s3Key)
   }
}
