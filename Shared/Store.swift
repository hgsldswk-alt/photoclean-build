import Foundation

struct AppData: Codable {
    var version = 1
    var firstOpen = Date()
    var onboarded = false
    var reviewed: [String: Set<String>] = [:]
    var basket: Set<String> = []
    var quota = Quota()
    var stats = Stats()
    var entitlement = Entitlement()
    var reminderEnabled = false
    var reminderOffered = false
    var cloudWarningShown = false
    var challengeGoal: Int?
    var reviewedVersion: String?
    var widgetNewCount = 0
    var widgetUnreviewed = 0
    var widgetMonth = CalendarKey.month(Date())
    init() {}
    enum CodingKeys: String, CodingKey {
        case version, firstOpen, onboarded, reviewed, basket, quota, stats, entitlement, reminderEnabled
        case reminderOffered, cloudWarningShown, challengeGoal, reviewedVersion, widgetNewCount, widgetUnreviewed, widgetMonth
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? c.decode(Int.self, forKey: .version)) ?? 1
        guard version == 1 else { throw CocoaError(.coderReadCorrupt) }
        firstOpen = (try? c.decode(Date.self, forKey: .firstOpen)) ?? Date()
        onboarded = (try? c.decode(Bool.self, forKey: .onboarded)) ?? false
        reviewed = (try? c.decode([String: Set<String>].self, forKey: .reviewed)) ?? [:]
        basket = (try? c.decode(Set<String>.self, forKey: .basket)) ?? []
        quota = (try? c.decode(Quota.self, forKey: .quota)) ?? Quota(firstDay: CalendarKey.day(firstOpen))
        stats = (try? c.decode(Stats.self, forKey: .stats)) ?? Stats()
        entitlement = (try? c.decode(Entitlement.self, forKey: .entitlement)) ?? Entitlement()
        reminderEnabled = (try? c.decode(Bool.self, forKey: .reminderEnabled)) ?? false
        reminderOffered = (try? c.decode(Bool.self, forKey: .reminderOffered)) ?? false
        cloudWarningShown = (try? c.decode(Bool.self, forKey: .cloudWarningShown)) ?? false
        if let goal = try? c.decode(Int.self, forKey: .challengeGoal), ChallengeCode.goalRange.contains(goal) {
            challengeGoal = goal
        }
        reviewedVersion = try? c.decode(String.self, forKey: .reviewedVersion)
        widgetNewCount = max(0, (try? c.decode(Int.self, forKey: .widgetNewCount)) ?? 0)
        widgetUnreviewed = max(0, (try? c.decode(Int.self, forKey: .widgetUnreviewed)) ?? 0)
        widgetMonth = (try? c.decode(String.self, forKey: .widgetMonth)) ?? CalendarKey.month(Date())
    }
}

enum Store {
    static var groupID: String { Bundle.main.object(forInfoDictionaryKey: "PhotoCleanAppGroup") as? String ?? "group.com.hgsldswk.photoclean" }
    static var defaults: UserDefaults { UserDefaults(suiteName: groupID) ?? .standard }
    static let key = "photoclean.data.v1"
    static func load(from defaults: UserDefaults = defaults) throws -> AppData {
        guard let raw = defaults.data(forKey: key) else { return AppData() }
        return try JSONDecoder().decode(AppData.self, from: raw)
    }
    static func save(_ data: AppData, to defaults: UserDefaults = defaults) throws { defaults.set(try JSONEncoder().encode(data), forKey: key) }
}
