import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

struct CachedStickerRecord: Codable {
    var sticker: Sticker
    var localFilename: String?
}

struct CachedPackManifest: Codable {
    let packID: String
    let version: Int
    var stickers: [CachedStickerRecord]
}

actor StickerPackCache {
    static let shared = StickerPackCache()

    private let fileManager = FileManager.default
    private let supportedStickerTypes: Set<UTType> = [.png, .jpeg, .gif]
    private let maxStickerFileSize = 500 * 1024
    private let maxStickerDimension: CGFloat = 618
    private let minStickerDimension: CGFloat = 120
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func cachedStickers(for pack: Pack) -> [Sticker]? {
        guard let manifest = try? loadManifest(packID: pack.id),
              manifest.version == version(for: pack)
        else {
            return nil
        }

        return decoratedStickers(from: manifest)
    }

    func stickers(for pack: Pack, userID: String) async throws -> [Sticker] {
        if var manifest = try? loadManifest(packID: pack.id),
           manifest.version == version(for: pack) {
            manifest = try await ensurePreparedAssets(in: manifest)
            try saveManifest(manifest)
            return decoratedStickers(from: manifest)
        }

        let stickers = try await APIClient.shared.fetchStickers(packID: pack.id, userID: userID)
        let existingManifest = try? loadManifest(packID: pack.id)
        let existingFilenames = Dictionary(
            uniqueKeysWithValues: (existingManifest?.stickers ?? []).map { ($0.sticker.id, $0.localFilename) }
        )

        var records: [CachedStickerRecord] = []
        records.reserveCapacity(stickers.count)

        for sticker in stickers {
            let existingFilename = existingFilenames[sticker.id] ?? nil
            let localFilename = try? await prepareStickerFile(for: sticker, existingFilename: existingFilename)
            records.append(CachedStickerRecord(sticker: sticker, localFilename: localFilename))
        }

        let manifest = CachedPackManifest(packID: pack.id, version: version(for: pack), stickers: records)
        try saveManifest(manifest)

        let liveFilenames = Set(records.compactMap(\.localFilename))
        let staleFilenames = Set((existingManifest?.stickers ?? []).compactMap(\.localFilename)).subtracting(liveFilenames)
        try removeStickerFiles(named: Array(staleFilenames))

        return decoratedStickers(from: manifest)
    }

    func preparedFileURL(for sticker: Sticker) async throws -> URL {
        var manifest = (try? loadManifest(packID: sticker.packId)) ?? CachedPackManifest(
            packID: sticker.packId,
            version: 0,
            stickers: []
        )

        if let index = manifest.stickers.firstIndex(where: { $0.sticker.id == sticker.id }) {
            if let filename = manifest.stickers[index].localFilename,
               let url = try existingStickerFileURL(filename: filename) {
                return url
            }

            let filename = try await prepareStickerFile(for: sticker, existingFilename: manifest.stickers[index].localFilename)
            manifest.stickers[index].sticker = sticker
            manifest.stickers[index].localFilename = filename
            try saveManifest(manifest)
            return try stickerFileURL(filename: filename)
        }

        let filename = try await prepareStickerFile(for: sticker, existingFilename: nil)
        manifest.stickers.append(CachedStickerRecord(sticker: sticker, localFilename: filename))
        try saveManifest(manifest)
        return try stickerFileURL(filename: filename)
    }

    private func ensurePreparedAssets(in manifest: CachedPackManifest) async throws -> CachedPackManifest {
        var updatedManifest = manifest

        for index in updatedManifest.stickers.indices {
            let record = updatedManifest.stickers[index]
            if let filename = record.localFilename,
               (try? existingStickerFileURL(filename: filename)) != nil {
                continue
            }

            let filename = try? await prepareStickerFile(for: record.sticker, existingFilename: record.localFilename)
            updatedManifest.stickers[index].localFilename = filename
        }

        return updatedManifest
    }

    private func prepareStickerFile(for sticker: Sticker, existingFilename: String?) async throws -> String {
        if let existingFilename,
           let existingURL = try existingStickerFileURL(filename: existingFilename) {
            return existingURL.lastPathComponent
        }

        guard let remoteURLString = sticker.downloadURL,
              let remoteURL = URL(string: remoteURLString)
        else {
            throw APIError(detail: "This sticker is missing a download URL.")
        }

        let (data, _) = try await URLSession.shared.data(from: remoteURL)
        let type = destinationType(for: data)
        let filename = "\(sticker.id).\(type.preferredFilenameExtension ?? "png")"
        let outputURL = try stickerFileURL(filename: filename)

        try removeVariantFiles(for: sticker.id, preserving: filename)

        if fileManager.fileExists(atPath: outputURL.path) {
            try? fileManager.removeItem(at: outputURL)
        }

        let sanitizedData = try dataForStickerFile(from: data, destinationType: type)
        try sanitizedData.write(to: outputURL, options: .atomic)
        return filename
    }

    private func removeVariantFiles(for stickerID: String, preserving filename: String) throws {
        let directory = try stickersDirectoryURL()
        let existingFiles = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)

        for fileURL in existingFiles
        where fileURL.deletingPathExtension().lastPathComponent == stickerID && fileURL.lastPathComponent != filename {
            try? fileManager.removeItem(at: fileURL)
        }
    }

    private func removeStickerFiles(named filenames: [String]) throws {
        for filename in filenames {
            guard let url = try existingStickerFileURL(filename: filename) else { continue }
            try? fileManager.removeItem(at: url)
        }
    }

    private func loadManifest(packID: String) throws -> CachedPackManifest {
        let data = try Data(contentsOf: try manifestURL(packID: packID))
        return try decoder.decode(CachedPackManifest.self, from: data)
    }

    private func saveManifest(_ manifest: CachedPackManifest) throws {
        let data = try encoder.encode(manifest)
        try data.write(to: try manifestURL(packID: manifest.packID), options: .atomic)
    }

    private func version(for pack: Pack) -> Int {
        pack.stickersVersion ?? 0
    }

    private func decoratedStickers(from manifest: CachedPackManifest) -> [Sticker] {
        manifest.stickers.map { record in
            var sticker = record.sticker

            if let filename = record.localFilename,
               let resolvedURL = try? existingStickerFileURL(filename: filename) {
                sticker.downloadURL = resolvedURL.absoluteString
            }

            return sticker
        }
    }

    private func manifestURL(packID: String) throws -> URL {
        try manifestsDirectoryURL().appendingPathComponent("\(packID).json")
    }

    private func existingStickerFileURL(filename: String) throws -> URL? {
        let url = try stickerFileURL(filename: filename)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    private func stickerFileURL(filename: String) throws -> URL {
        try stickersDirectoryURL().appendingPathComponent(filename)
    }

    private func manifestsDirectoryURL() throws -> URL {
        let directory = try rootCacheDirectoryURL().appendingPathComponent("manifests", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    private func stickersDirectoryURL() throws -> URL {
        let directory = try rootCacheDirectoryURL().appendingPathComponent("stickers", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    private func rootCacheDirectoryURL() throws -> URL {
        if let groupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: PatchPalsShared.appGroupIdentifier) {
            let directory = groupURL.appendingPathComponent("StickerPackCache", isDirectory: true)
            if !fileManager.fileExists(atPath: directory.path) {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            return directory
        }

        let cachesDirectory = try fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = cachesDirectory.appendingPathComponent("StickerPackCache", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    private func destinationType(for data: Data) -> UTType {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let identifier = CGImageSourceGetType(source) as String?,
              let detectedType = UTType(identifier)
        else {
            return .png
        }

        if supportedStickerTypes.contains(detectedType) {
            return detectedType
        }

        return .png
    }

    private func dataForStickerFile(from data: Data, destinationType: UTType) throws -> Data {
        if destinationType != .png, data.count <= maxStickerFileSize, imageFitsStickerBounds(data: data) {
            return data
        }

        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let identifier = CGImageSourceGetType(source) as String?,
           let detectedType = UTType(identifier),
           detectedType == .png,
           data.count <= maxStickerFileSize,
           imageFitsStickerBounds(data: data) {
            return data
        }

        guard let image = UIImage(data: data) else {
            throw APIError(detail: "This sticker format can't be converted for Messages.")
        }

        return try sanitizedStickerData(from: image)
    }

    private func imageFitsStickerBounds(data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat
        else {
            return false
        }

        return width <= maxStickerDimension && height <= maxStickerDimension
    }

    private func sanitizedStickerData(from image: UIImage) throws -> Data {
        var targetDimension = min(max(image.size.width, image.size.height), maxStickerDimension)

        while targetDimension >= minStickerDimension {
            let renderedImage = resizedImage(from: image, maxDimension: targetDimension)

            if let pngData = renderedImage.pngData(), pngData.count <= maxStickerFileSize {
                return pngData
            }

            targetDimension *= 0.82
        }

        throw APIError(detail: "This sticker is too large for Messages. Try a smaller image.")
    }

    private func resizedImage(from image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longestSide = max(image.size.width, image.size.height)
        guard longestSide > 0 else { return image }

        let scale = min(1, maxDimension / longestSide)
        let targetSize = CGSize(
            width: max(1, floor(image.size.width * scale)),
            height: max(1, floor(image.size.height * scale))
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false

        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
