import SwiftUI
import Messages
import Combine
import ImageIO
import UniformTypeIdentifiers
import UIKit
import OSLog

private let signposter = OSSignposter(subsystem: "com.patchpals.oldboy", category: "MessagesStickerBrowser")

struct MessagesStickerBrowserView: View {
    @StateObject private var viewModel = MessagesStickerBrowserViewModel()

    let onSendSticker: @Sendable (Sticker) async -> Void
    let onRequestExpandedPresentation: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            packsStrip
            Divider()
            content
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .task {
            await viewModel.load()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Stickers")
                    .font(.system(size: 22, weight: .semibold))
                Text(viewModel.headerSubtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                onRequestExpandedPresentation()
                Task {
                    await viewModel.refresh()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var packsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(viewModel.packs) { pack in
                    Button {
                        onRequestExpandedPresentation()
                        Task {
                            await viewModel.selectPack(pack.id)
                        }
                    } label: {
                        PackChipView(
                            pack: pack,
                            isSelected: viewModel.selectedPackID == pack.id,
                            previewURL: viewModel.previewURL(for: pack.id)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.packs.isEmpty {
            ProgressView("Loading sticker packs...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = viewModel.errorMessage {
            ContentUnavailableView(
                "Couldn't Load Stickers",
                systemImage: "exclamationmark.bubble",
                description: Text(errorMessage)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.needsSignIn {
            ContentUnavailableView(
                "Open PatchPals First",
                systemImage: "person.crop.circle.badge.exclamationmark",
                description: Text("Sign in to PatchPals in the main app once, then reopen Messages.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let pack = viewModel.selectedPack {
            if viewModel.isLoadingPack {
                ProgressView("Loading \(pack.name)...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.stickers(for: pack.id).isEmpty {
                ContentUnavailableView(
                    "No Stickers Yet",
                    systemImage: "square.grid.3x3",
                    description: Text("This pack is empty.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(viewModel.stickers(for: pack.id)) { sticker in
                            Button {
                                Task {
                                    await onSendSticker(sticker)
                                }
                            } label: {
                                StickerTileView(sticker: sticker)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                }
            }
        } else {
            ContentUnavailableView(
                "No Packs Yet",
                systemImage: "rectangle.stack.badge.plus",
                description: Text("Create a sticker pack in PatchPals to use it here.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

@MainActor
final class MessagesStickerBrowserViewModel: ObservableObject {
    @Published private(set) var packs: [Pack] = []
    @Published private(set) var selectedPackID: String?
    @Published private(set) var stickerMap: [String: [Sticker]] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingPack = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var needsSignIn = false

    var headerSubtitle: String {
        if let selectedPack {
            return selectedPack.name
        }
        return "Your packs"
    }

    var selectedPack: Pack? {
        guard let selectedPackID else { return nil }
        return packs.first(where: { $0.id == selectedPackID })
    }

    func load() async {
        guard packs.isEmpty else { return }
        await refresh()
    }

    func refresh() async {
        let state = signposter.beginInterval("Refresh Sticker Packs", id: .exclusive)
        defer { signposter.endInterval("Refresh Sticker Packs", state) }

        guard let userID = SessionStore.loggedInUserID else {
            needsSignIn = true
            packs = []
            selectedPackID = nil
            stickerMap = [:]
            errorMessage = nil
            return
        }

        isLoading = true
        errorMessage = nil
        needsSignIn = false

        do {
            let loadedPacks = try await APIClient.shared.fetchPacks(requesterID: userID)
            packs = loadedPacks

            if let selectedPackID, loadedPacks.contains(where: { $0.id == selectedPackID }) {
                await loadStickers(for: selectedPackID, userID: userID)
            } else {
                selectedPackID = loadedPacks.first?.id
                if let firstPackID = loadedPacks.first?.id {
                    await loadStickers(for: firstPackID, userID: userID)
                }
            }

            await prefetchPackPreviews(userID: userID)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func selectPack(_ packID: String) async {
        selectedPackID = packID
        guard let userID = SessionStore.loggedInUserID else { return }
        if stickerMap[packID] == nil {
            await loadStickers(for: packID, userID: userID)
        }
    }

    func stickers(for packID: String) -> [Sticker] {
        stickerMap[packID] ?? []
    }

    func previewURL(for packID: String) -> URL? {
        guard let firstURL = stickers(for: packID).first?.downloadURL else { return nil }
        return URL(string: firstURL)
    }

    private func prefetchPackPreviews(userID: String) async {
        await withTaskGroup(of: Void.self) { group in
            for pack in packs where stickerMap[pack.id] == nil {
                group.addTask {
                    let stickers = (try? await APIClient.shared.fetchStickers(packID: pack.id, userID: userID)) ?? []
                    await MainActor.run {
                        if self.stickerMap[pack.id] == nil {
                            self.stickerMap[pack.id] = stickers
                        }
                    }
                }
            }
        }
    }

    private func loadStickers(for packID: String, userID: String) async {
        let state = signposter.beginInterval("Load Stickers for Pack", id: .exclusive, "\(pack.id)")
        isLoadingPack = true

        defer {
            isLoadingPack = false
            signposter.endInterval("Load Stickers for Pack", state)
        }

        do {
            stickerMap[packID] = try await APIClient.shared.fetchStickers(packID: packID, userID: userID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct PackChipView: View {
    let pack: Pack
    let isSelected: Bool
    let previewURL: URL?

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(isSelected ? Color.accentColor : Color.black.opacity(0.06), lineWidth: isSelected ? 2 : 1)
                    )

                if let previewURL {
                    AsyncImage(url: previewURL) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        ProgressView()
                    }
                } else {
                    Text(String(pack.name.prefix(1)).uppercased())
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 68, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Text(pack.name)
                .font(.caption)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
                .frame(width: 72)
        }
    }
}

private struct StickerTileView: View {
    let sticker: Sticker

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))

            if let rawURL = sticker.downloadURL, let url = URL(string: rawURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .padding(8)
                } placeholder: {
                    ProgressView()
                }
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 26))
                    .foregroundStyle(.secondary)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }
}

actor MessageStickerSender {
    private let fileManager = FileManager.default
    private let supportedStickerTypes: Set<UTType> = [.png, .jpeg, .gif]
    private let maxStickerFileSize = 500 * 1024
    private let maxStickerDimension: CGFloat = 618
    private let minStickerDimension: CGFloat = 120

    func makeMSSticker(from sticker: Sticker) async throws -> MSSticker {
        let fileURL = try await localFileURL(for: sticker)
        return try MSSticker(contentsOfFileURL: fileURL, localizedDescription: "PatchPals sticker")
    }

    private func localFileURL(for sticker: Sticker) async throws -> URL {
        guard let remoteURLString = sticker.downloadURL, let remoteURL = URL(string: remoteURLString) else {
            throw APIError(detail: "This sticker is missing a download URL.")
        }

        let cacheDirectory = try cacheDirectoryURL()
        let (data, _) = try await URLSession.shared.data(from: remoteURL)
        let preparedFile = try preparedStickerFile(for: sticker.id, data: data, cacheDirectory: cacheDirectory)

        if let existingFiles = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) {
            for fileURL in existingFiles where fileURL.deletingPathExtension().lastPathComponent == sticker.id && fileURL != preparedFile {
                try? fileManager.removeItem(at: fileURL)
            }
        }

        if fileManager.fileExists(atPath: preparedFile.path) {
            try? fileManager.removeItem(at: preparedFile)
        }

        try dataForStickerFile(from: data, destinationType: destinationType(for: data)).write(to: preparedFile, options: .atomic)
        return preparedFile
    }

    private func preparedStickerFile(for stickerID: String, data: Data, cacheDirectory: URL) throws -> URL {
        let type = destinationType(for: data)
        return cacheDirectory.appendingPathComponent("\(stickerID).\(type.preferredFilenameExtension ?? "png")")
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

    private func cacheDirectoryURL() throws -> URL {
        let cachesDirectory = try fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = cachesDirectory.appendingPathComponent("MessagesStickerCache", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
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
