import Foundation

struct CleanupTotal: Codable, Equatable {
    var bytes: Int64 = 0
    var count = 0
}

struct Stats: Codable, Equatable {
    var monthly: [String: CleanupTotal] = [:]
    var reached: Set<String> = []
    var successfulCleanups = 0
    var largeCleanups = 0
    var total: CleanupTotal { monthly.values.reduce(CleanupTotal()) { CleanupTotal(bytes: $0.bytes + $1.bytes, count: $0.count + $1.count) } }
    static func milestones(_ total: CleanupTotal) -> Set<String> {
        var ids = Set<String>()
        for gb in [1, 5, 10] where total.bytes >= Int64(gb) * 1_000_000_000 { ids.insert("gb-\(gb)") }
        for count in [1000, 10000] where total.count >= count { ids.insert("photos-\(count)") }
        return ids
    }
    mutating func record(_ assets: [PhotoAsset], at now: Date, calendar: Calendar = .current) -> Set<String> {
        guard !assets.isEmpty else { return [] }
        let key = CalendarKey.month(now, calendar: calendar)
        var value = monthly[key] ?? CleanupTotal()
        value.bytes += Bytes.total(assets); value.count += assets.count; monthly[key] = value
        successfulCleanups += 1; if assets.count >= 30 { largeCleanups += 1 }
        let new = Self.milestones(total).subtracting(reached); reached.formUnion(new); return new
    }
    init() {}
    enum CodingKeys: String, CodingKey { case monthly, reached, successfulCleanups, largeCleanups }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        monthly = (try? c.decode([String: CleanupTotal].self, forKey: .monthly)) ?? [:]
        monthly = monthly.filter { $0.value.bytes >= 0 && $0.value.count >= 0 }
        reached = (try? c.decode(Set<String>.self, forKey: .reached)) ?? []
        successfulCleanups = max(0, (try? c.decode(Int.self, forKey: .successfulCleanups)) ?? 0)
        largeCleanups = max(0, (try? c.decode(Int.self, forKey: .largeCleanups)) ?? 0)
    }
}

enum ReviewGate {
    static func eligible(stats: Stats, firstOpen: Date, now: Date, version: String, reviewedVersion: String?, afterPaywallOrError: Bool) -> Bool {
        stats.largeCleanups >= 2 && now.timeIntervalSince(firstOpen) >= 2 * 86400 && reviewedVersion != version && !afterPaywallOrError
    }
}

struct CleanupReceipt {
    var count = 0
    var bytes: Int64 = 0
    var approximate = false
    var date = Date()
    var before: Int64 = 0
    var milestones: Set<String> = []
}

