import Foundation

struct Quota: Codable, Equatable {
    var firstDay: String = CalendarKey.day(Date())
    var used: [String: Int] = [:]
    func limit(at date: Date, calendar: Calendar = .current) -> Int { CalendarKey.day(date, calendar: calendar) == firstDay ? 200 : 50 }
    func remaining(at date: Date, pro: Bool, calendar: Calendar = .current) -> Int {
        pro ? Int.max : max(0, limit(at: date, calendar: calendar) - max(0, used[CalendarKey.day(date, calendar: calendar)] ?? 0))
    }
    func permits(_ count: Int, at date: Date, pro: Bool, calendar: Calendar = .current) -> Bool {
        count > 0 && count <= remaining(at: date, pro: pro, calendar: calendar)
    }
    func batchCount(selected: Int, at date: Date, pro: Bool, calendar: Calendar = .current) -> Int {
        min(max(0, selected), remaining(at: date, pro: pro, calendar: calendar))
    }
    mutating func record(count: Int, success: Bool, at date: Date, calendar: Calendar = .current) {
        guard success, count > 0 else { return }
        used[CalendarKey.day(date, calendar: calendar), default: 0] += count
    }
}

struct Entitlement: Codable, Equatable {
    var purchasedPro = false
    var proStartedAt: Date?
}
