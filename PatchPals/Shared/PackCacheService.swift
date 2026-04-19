import Foundation

/// Stores pack metadata + stickers locally so the extension can open instantly.
/// Uses the shared App Group so both the main app and the extension can read/write.
final class PackCacheService {
    static let shared = PackCacheService()

    private init() {}

    private var defaults: UserDefaults {
        UserDefaults(suiteName: PatchPalsShared.appGroupIdentifier) ?? .standard
    }

    private let cacheKey = "patchpals_pack_cache_v1"

    // MARK: - Cached pack representation

    struct CachedPack: Codable {
        let id: String
        var name: String
        var description: String?
        let ownerId: String
        var packVersion: Int
        var stickers: [Sticker]
    }

    // MARK: - Read

    func loadAll() -> [CachedPack] {
        guard let data = defaults.data(forKey: cacheKey),
              let packs = try? JSONDecoder().decode([CachedPack].self, from: data)
        else { return [] }
        return packs
    }

    func cachedVersion(for packID: String) -> Int? {
        loadAll().first(where: { $0.id == packID })?.packVersion
    }

    // MARK: - Write

    func upsert(_ pack: CachedPack) {
        var all = loadAll()
        if let idx = all.firstIndex(where: { $0.id == pack.id }) {
            all[idx] = pack
        } else {
            all.append(pack)
        }
        save(all)
    }

    func upsertFromFull(_ full: PackFull) {
        upsert(CachedPack(
            id: full.id,
            name: full.name,
            description: full.description,
            ownerId: full.ownerId,
            packVersion: full.packVersion,
            stickers: full.stickers
        ))
    }

    func remove(packID: String) {
        var all = loadAll()
        all.removeAll { $0.id == packID }
        save(all)
    }

    // MARK: - Private

    private func save(_ packs: [CachedPack]) {
        guard let data = try? JSONEncoder().encode(packs) else { return }
        defaults.set(data, forKey: cacheKey)
    }
}
