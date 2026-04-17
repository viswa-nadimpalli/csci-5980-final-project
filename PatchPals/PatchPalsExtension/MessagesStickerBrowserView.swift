import SwiftUI
import Messages
import Combine
import UIKit

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
                            previewSticker: viewModel.previewSticker(for: pack.id)
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

    private let stickerCache = StickerPackCache.shared

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
            await loadCachedManifests(for: loadedPacks)

            if let selectedPackID,
               let selectedPack = loadedPacks.first(where: { $0.id == selectedPackID }) {
                await loadStickers(for: selectedPack, userID: userID)
            } else {
                selectedPackID = loadedPacks.first?.id
                if let firstPack = loadedPacks.first {
                    await loadStickers(for: firstPack, userID: userID)
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
        guard let userID = SessionStore.loggedInUserID,
              let pack = packs.first(where: { $0.id == packID })
        else {
            return
        }
        if stickerMap[packID] == nil {
            await loadStickers(for: pack, userID: userID)
        }
    }

    func stickers(for packID: String) -> [Sticker] {
        stickerMap[packID] ?? []
    }

    func previewSticker(for packID: String) -> Sticker? {
        stickers(for: packID).first
    }

    private func prefetchPackPreviews(userID: String) async {
        await withTaskGroup(of: Void.self) { group in
            for pack in packs where pack.id != selectedPackID {
                group.addTask {
                    let stickers = (try? await StickerPackCache.shared.stickers(for: pack, userID: userID)) ?? []
                    await MainActor.run {
                        self.stickerMap[pack.id] = stickers
                    }
                }
            }
        }
    }

    private func loadCachedManifests(for packs: [Pack]) async {
        for pack in packs {
            if let cachedStickers = await stickerCache.cachedStickers(for: pack) {
                stickerMap[pack.id] = cachedStickers
            }
        }
    }

    private func loadStickers(for pack: Pack, userID: String) async {
        isLoadingPack = true
        do {
            stickerMap[pack.id] = try await stickerCache.stickers(for: pack, userID: userID)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingPack = false
    }
}

private struct PackChipView: View {
    let pack: Pack
    let isSelected: Bool
    let previewSticker: Sticker?

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(isSelected ? Color.accentColor : Color.black.opacity(0.06), lineWidth: isSelected ? 2 : 1)
                    )

                if let previewSticker {
                    CachedStickerImage(
                        url: previewSticker.downloadURL.flatMap(URL.init(string:)),
                        cacheKey: "pack-preview-\(previewSticker.s3Key)",
                        contentMode: SwiftUI.ContentMode.fill,
                        placeholder: {
                            ProgressView()
                        },
                        failure: {
                            Text(String(pack.name.prefix(1)).uppercased())
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                    )
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

            CachedStickerImage(
                url: sticker.downloadURL.flatMap(URL.init(string:)),
                cacheKey: sticker.s3Key,
                contentMode: SwiftUI.ContentMode.fit,
                placeholder: {
                    ProgressView()
                },
                failure: {
                    Image(systemName: "photo")
                        .font(.system(size: 26))
                        .foregroundStyle(.secondary)
                }
            )
            .padding(8)
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }
}

actor MessageStickerSender {
    func makeMSSticker(from sticker: Sticker) async throws -> MSSticker {
        let fileURL = try await StickerPackCache.shared.preparedFileURL(for: sticker)
        return try MSSticker(contentsOfFileURL: fileURL, localizedDescription: "PatchPals sticker")
    }
}
