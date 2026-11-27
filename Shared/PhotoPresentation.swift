import Foundation

enum PhotoPresentation {
    static func groupPreview(_ groups: [PhotoGroup], avoiding reference: PhotoAsset?, demo: Bool) -> [PhotoAsset] {
        guard let reference else { return Array((groups.first?.assets ?? []).prefix(3)) }
        let preferred = groups.first { group in
            guard let first = group.assets.first else { return false }
            if demo { return DemoCatalog.appearance(first).scene != DemoCatalog.appearance(reference).scene }
            return !Calendar.current.isDate(first.created, inSameDayAs: reference.created)
        }
        let chosen = preferred ?? groups.last
        let assets = chosen?.assets ?? []
        return Array(assets.prefix(3))
    }
    static func samples(_ assets: [PhotoAsset], limit: Int) -> [PhotoAsset] {
        let photos = assets.filter { !$0.isVideo }
        guard limit > 0, !photos.isEmpty else { return [] }
        guard photos.count > limit else { return photos }
        guard limit > 1 else { return [photos[0]] }
        return (0..<limit).map { photos[$0 * (photos.count - 1) / (limit - 1)] }
    }

    static func kept(in month: PhotoMonth?, reviewed: Set<String>, basket: Set<String>) -> [PhotoAsset] {
        let kept = (month?.assets ?? []).filter { reviewed.contains($0.id) && !basket.contains($0.id) }
        return samples(kept, limit: 5)
    }
}

extension CalendarKey {
    static func heroMonth(_ key: String, locale: Locale = .current) -> String {
        guard let date = monthDate(key) else { return key }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter.string(from: date)
    }
}

enum CapacityRing {
    static func spans(values: [Int64], progress: Double) -> [(start: Double, end: Double)] {
        let weights = values.map { Double(max(0, $0)) }
        let total = weights.reduce(0, +)
        guard total > 0 else { return values.map { _ in (0, 0) } }
        let extent = progress.isFinite ? min(1, max(0, progress)) : 0
        var cursor = 0.0
        return weights.map { weight in
            let start = cursor
            cursor += weight / total * extent
            return (start, cursor)
        }
    }
}
