import Foundation

struct AnalysisResult: Sendable {
    var similar: [PhotoGroup] = []
    var duplicates: [PhotoGroup] = []
    var analyzed = 0
    var total = 0
    var skippedCloud = 0
    var failed = 0
    var complete = false
    func restricted(to current: [String: PhotoAsset]) -> AnalysisResult {
        func refresh(_ groups: [PhotoGroup]) -> [PhotoGroup] {
            groups.compactMap { group in
                let photos = group.assets.compactMap { previous -> PhotoAsset? in
                    guard var asset = current[previous.id], asset.cacheKey == previous.cacheKey else { return nil }
                    asset.sharpness = previous.sharpness
                    return asset
                }
                guard photos.count > 1, let best = AnalysisCore.best(photos) else { return nil }
                return PhotoGroup(assets: photos, bestID: best.id)
            }
        }
        var result = self
        result.similar = refresh(similar); result.duplicates = refresh(duplicates)
        return result
    }
}

struct AnalysisDay: Sendable {
    let id: String
    let assets: [PhotoAsset]
    static func newestFirst(_ assets: [PhotoAsset], calendar: Calendar = .current) -> [AnalysisDay] {
        Dictionary(grouping: assets.filter { !$0.isVideo }) { CalendarKey.day($0.created, calendar: calendar) }
            .map { AnalysisDay(id: $0.key, assets: $0.value.sorted { $0.id < $1.id }) }
            .sorted { $0.id > $1.id }
    }
}

struct AnalysisDays {
    struct Completed {
        let input: [PhotoAsset]
        let result: AnalysisResult
    }
    private(set) var completed: [String: Completed] = [:]
    mutating func reconcile(_ days: [AnalysisDay]) {
        let current = Dictionary(uniqueKeysWithValues: days.map { ($0.id, $0.assets) })
        completed = completed.filter { key, value in
            current[key] == value.input && value.result.skippedCloud == 0 && value.result.failed == 0
        }
    }
    mutating func record(_ day: AnalysisDay, result: AnalysisResult) {
        completed[day.id] = Completed(input: day.assets, result: result)
    }
    func result(total: Int) -> AnalysisResult {
        var result = AnalysisResult(total: total)
        for key in completed.keys.sorted(by: >) {
            guard let day = completed[key]?.result else { continue }
            result.similar.append(contentsOf: day.similar)
            result.duplicates.append(contentsOf: day.duplicates)
            result.analyzed += day.analyzed
            result.skippedCloud += day.skippedCloud
            result.failed += day.failed
        }
        return result
    }
}

struct ProgressThrottle {
    var last: TimeInterval = -.infinity
    let interval: TimeInterval = 0.5
    func delay(at now: TimeInterval) -> TimeInterval { max(0, interval - (now - last)) }
    mutating func take(at now: TimeInterval) -> Bool {
        guard delay(at: now) == 0 else { return false }
        last = now
        return true
    }
}
