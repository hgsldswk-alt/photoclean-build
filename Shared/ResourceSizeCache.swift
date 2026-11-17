import Foundation

struct ResourceSizeCache: Codable {
    struct Entry: Codable, Equatable {
        let bytes: Int64
        let approximate: Bool
    }
    var version = 1
    var entries: [String: Entry] = [:]
    static func load(_ url: URL?) -> ResourceSizeCache {
        guard let url, let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(Self.self, from: data), cache.version == 1,
              cache.entries.values.allSatisfy({ $0.bytes >= 0 }) else { return Self() }
        return cache
    }
    mutating func retain(_ assets: [PhotoAsset]) {
        let keys = Set(assets.map(\.cacheKey))
        entries = entries.filter { keys.contains($0.key) }
    }
    func apply(to asset: inout PhotoAsset) -> Bool {
        guard let entry = entries[asset.cacheKey] else { return false }
        asset.bytes = entry.bytes; asset.approximate = entry.approximate
        return true
    }
    func save(_ url: URL?) throws {
        guard let url else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
