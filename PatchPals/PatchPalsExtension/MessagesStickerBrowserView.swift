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
        .onReceive(NotificationCenter.default.publisher(for: .patchPalsMessagesExtensionDidBecomeActive)) { _ in
            Task {
                await viewModel.refresh()
            }
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

    private let cache = PackCacheService.shared
    private let wsClient = PackWebSocketClient()

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

    // MARK: - Startup

    func load() async {
        guard packs.isEmpty else { return }

        // 1. Show cached data immediately so the UI isn't blank
        let cached = cache.loadAll()
        if !cached.isEmpty {
            packs = cached.map {
                Pack(id: $0.id, name: $0.name, description: $0.description,
                     ownerId: $0.ownerId, packVersion: $0.packVersion)
            }
            for entry in cached {
                stickerMap[entry.id] = entry.stickers
            }
            selectedPackID = packs.first?.id
        }

        // 2. Then refresh from server (version-aware)
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
            // Fetch all pack versions in one cheap call
            let serverVersions = try await APIClient.shared.fetchPackVersions(userID: userID)
            let serverVersionMap = Dictionary(uniqueKeysWithValues: serverVersions.map { ($0.packId, $0.packVersion) })

            // Fetch full data only for stale or missing packs
            try await withThrowingTaskGroup(of: PackFull?.self) { group in
                for entry in serverVersions {
                    let cachedVersion = cache.cachedVersion(for: entry.packId)
                    if cachedVersion == nil || cachedVersion! < entry.packVersion {
                        group.addTask {
                            try await APIClient.shared.fetchPackFull(packID: entry.packId, requesterID: userID)
                        }
                    }
                }

                for try await full in group {
                    if let full {
                        cache.upsertFromFull(full)
                        stickerMap[full.id] = full.stickers
                    }
                }
            }

            // Remove packs the user no longer belongs to
            let serverPackIDs = Set(serverVersions.map { $0.packId })
            for cached in cache.loadAll() where !serverPackIDs.contains(cached.id) {
                cache.remove(packID: cached.id)
                stickerMap.removeValue(forKey: cached.id)
            }

            // Rebuild packs list from fresh cache
            let allCached = cache.loadAll()
            packs = allCached
                .sorted { ($0.name, $0.id) < ($1.name, $1.id) }
                .map {
                    Pack(id: $0.id, name: $0.name, description: $0.description,
                         ownerId: $0.ownerId, packVersion: $0.packVersion)
                }

            // Apply any server-version overrides to pack list
            packs = packs.map { pack in
                var p = pack
                if let v = serverVersionMap[pack.id] { p.packVersion = v }
                return p
            }

            if let selectedPackID, !packs.contains(where: { $0.id == selectedPackID }) {
                self.selectedPackID = packs.first?.id
            } else if selectedPackID == nil {
                selectedPackID = packs.first?.id
            }

            if let selectedPackID {
                await selectPack(selectedPackID)
            }

        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Pack selection + WebSocket

    func selectPack(_ packID: String) async {
        selectedPackID = packID
        guard let userID = SessionStore.loggedInUserID else { return }

        // Load stickers from cache first if we have them
        if stickerMap[packID] == nil,
           let cached = cache.loadAll().first(where: { $0.id == packID }) {
            stickerMap[packID] = cached.stickers
        }

        // Connect WebSocket for real-time updates on this pack
        wsClient.onEvent = { [weak self] event in
            guard let self else { return }
            Task { await self.handleWebSocketEvent(event, userID: userID) }
        }
        wsClient.connect(packID: packID)

        // Fetch fresh stickers if not already loaded
        if stickerMap[packID] == nil {
            await refreshPackFull(packID: packID, userID: userID)
        }
    }

    func stickers(for packID: String) -> [Sticker] {
        stickerMap[packID] ?? []
    }

    func previewSticker(for packID: String) -> Sticker? {
        stickers(for: packID).first
    }

    // MARK: - WebSocket event handling

    private func handleWebSocketEvent(_ event: PackWebSocketEvent, userID: String) async {
        guard event.eventType == "pack_updated" else { return }
        let cachedVersion = cache.cachedVersion(for: event.packId) ?? -1
        guard event.packVersion > cachedVersion else { return }
        await refreshPackFull(packID: event.packId, userID: userID)
    }

    private func refreshPackFull(packID: String, userID: String) async {
        if packID == selectedPackID { isLoadingPack = true }
        do {
            let full = try await APIClient.shared.fetchPackFull(packID: packID, requesterID: userID)
            cache.upsertFromFull(full)
            stickerMap[full.id] = full.stickers
            // Update pack version in the list
            if let idx = packs.firstIndex(where: { $0.id == full.id }) {
                packs[idx].packVersion = full.packVersion
            }
        } catch {
            // Silently ignore — stale data is still usable
        }
        if packID == selectedPackID { isLoadingPack = false }
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

extension Notification.Name {
    static let patchPalsMessagesExtensionDidBecomeActive = Notification.Name("patchPalsMessagesExtensionDidBecomeActive")
}
