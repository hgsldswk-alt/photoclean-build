import Foundation

enum AnalysisCore {
    static let duplicateThreshold: Float = 0.05
    static let similarThreshold: Float = 0.35
    static let timeWindow: TimeInterval = 600
    static let lookAhead = 30

    static func months(_ assets: [PhotoAsset], calendar: Calendar = .current) -> [PhotoMonth] {
        Dictionary(grouping: assets) { CalendarKey.month($0.created, calendar: calendar) }
            .map { PhotoMonth(id: $0.key, assets: $0.value.sorted { $0.created > $1.created }) }
            .sorted { $0.id > $1.id }
    }
    static func screenshots(_ assets: [PhotoAsset]) -> [PhotoAsset] { assets.filter(\.screenshot) }
    static func largeVideos(_ assets: [PhotoAsset]) -> [PhotoAsset] {
        let videos = assets.filter(\.isVideo).sorted { $0.bytes == $1.bytes ? $0.id < $1.id : $0.bytes > $1.bytes }
        return videos.enumerated().filter { $0.offset < 30 || $0.element.bytes >= 50_000_000 }.map { $0.element }
    }
    static func best(_ assets: [PhotoAsset]) -> PhotoAsset? {
        assets.sorted { a, b in
            if a.favorite != b.favorite { return a.favorite }
            if a.burstPick != b.burstPick { return a.burstPick }
            if a.pixels != b.pixels { return a.pixels > b.pixels }
            if a.sharpness != b.sharpness { return a.sharpness > b.sharpness }
            if a.modified != b.modified { return a.modified > b.modified }
            return a.id < b.id
        }.first
    }
    static func candidates(_ assets: [PhotoAsset], calendar: Calendar = .current) -> [(Int, Int)] {
        var result: [(Int, Int)] = []
        for i in assets.indices {
            let end = min(assets.count, i + lookAhead + 1)
            guard i + 1 < end else { continue }
            for j in (i + 1)..<end {
                guard assets[j].created.timeIntervalSince(assets[i].created) <= timeWindow else { break }
                guard calendar.isDate(assets[i].created, inSameDayAs: assets[j].created) else { continue }
                result.append((i, j))
            }
        }
        return result
    }
    static func groups(_ input: [PhotoAsset], duplicates: Bool, calendar: Calendar = .current,
                       distance: (PhotoAsset, PhotoAsset) -> Float?) -> [PhotoGroup] {
        let result = classify(input, calendar: calendar, distance: distance)
        return duplicates ? result.duplicates : result.similar
    }
    static func classify(_ input: [PhotoAsset], calendar: Calendar = .current,
                         distance: (PhotoAsset, PhotoAsset) -> Float?) -> (similar: [PhotoGroup], duplicates: [PhotoGroup]) {
        let assets = input.filter { !$0.isVideo }.sorted { $0.created == $1.created ? $0.id < $1.id : $0.created < $1.created }
        var similar = UnionFind(count: assets.count)
        var duplicates = UnionFind(count: assets.count)
        for i in assets.indices {
            let end = min(assets.count, i + lookAhead + 1)
            guard i + 1 < end else { continue }
            for j in (i + 1)..<end {
                guard assets[j].created.timeIntervalSince(assets[i].created) <= timeWindow else { break }
                guard calendar.isDate(assets[i].created, inSameDayAs: assets[j].created),
                      let d = distance(assets[i], assets[j]), d.isFinite, d >= 0 else { continue }
                let sameSize = assets[i].width == assets[j].width && assets[i].height == assets[j].height
                if d < duplicateThreshold && sameSize { duplicates.join(i, j) }
                if d < similarThreshold { similar.join(i, j) }
            }
        }
        var bursts: [String: Int] = [:]
        for (i, photo) in assets.enumerated() {
            guard let id = photo.burst else { continue }
            let key = CalendarKey.day(photo.created, calendar: calendar) + "|" + id
            if let first = bursts[key] { similar.join(first, i) } else { bursts[key] = i }
        }
        let duplicateGroups = makeGroups(assets, union: &duplicates)
        let duplicateIDs = Set(duplicateGroups.flatMap { $0.assets.map(\.id) })
        return (makeGroups(assets, union: &similar, excluding: duplicateIDs), duplicateGroups)
    }
    private static func makeGroups(_ assets: [PhotoAsset], union: inout UnionFind,
                                   excluding ids: Set<String> = []) -> [PhotoGroup] {
        var buckets: [Int: [PhotoAsset]] = [:]
        for i in assets.indices where !ids.contains(assets[i].id) { buckets[union.root(i), default: []].append(assets[i]) }
        return buckets.values.compactMap { photos in
            guard photos.count > 1, let pick = best(photos) else { return nil }
            return PhotoGroup(assets: photos.sorted { a, b in
                if a.id == b.id { return false }
                if a.id == pick.id { return true }; if b.id == pick.id { return false }
                return a.created == b.created ? a.id < b.id : a.created > b.created
            }, bestID: pick.id)
        }.sorted { ($0.assets.first?.created ?? .distantPast) > ($1.assets.first?.created ?? .distantPast) }
    }
}

struct UnionFind {
    private var parents: [Int]
    private var ranks: [Int]
    init(count: Int) { parents = Array(0..<count); ranks = Array(repeating: 0, count: count) }
    mutating func root(_ i: Int) -> Int {
        let parent = parents[i]
        if parent != i { parents[i] = root(parent) }
        return parents[i]
    }
    mutating func join(_ a: Int, _ b: Int) {
        let x = root(a), y = root(b)
        guard x != y else { return }
        if ranks[x] < ranks[y] { parents[x] = y }
        else { parents[y] = x; if ranks[x] == ranks[y] { ranks[x] += 1 } }
    }
}
