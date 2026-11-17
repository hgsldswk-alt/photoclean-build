import Foundation

struct HomeCapacity {
    let photos: Int64
    let videos: Int64
    let screenshots: Int64
    let approximate: Bool
    var values: [Int64] { [photos, videos, screenshots] }
    var total: Int64 { photos + videos + screenshots }

    init(reclaimable: [PhotoAsset]) {
        var seen = Set<String>()
        var photos: Int64 = 0, videos: Int64 = 0, screenshots: Int64 = 0
        for asset in reclaimable where seen.insert(asset.id).inserted {
            if asset.isVideo { videos += max(0, asset.bytes) }
            else if asset.screenshot { screenshots += max(0, asset.bytes) }
            else { photos += max(0, asset.bytes) }
        }
        self.photos = photos; self.videos = videos; self.screenshots = screenshots
        approximate = reclaimable.contains(where: \.approximate)
    }
}

extension Bytes {
    static func components(_ value: Int64) -> (number: String, unit: String) {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.includesActualByteCount = false
        formatter.allowsNonnumericFormatting = false
        let formatted = formatter.string(fromByteCount: max(0, value))
        formatter.includesCount = false
        let unit = formatter.string(fromByteCount: max(0, value)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !unit.isEmpty, let range = formatted.range(of: unit, options: .backwards) else {
            return (formatted, "")
        }
        var number = formatted
        number.removeSubrange(range)
        return (number.trimmingCharacters(in: .whitespacesAndNewlines), unit)
    }
}
