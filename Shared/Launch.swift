import Foundation

enum Launch {
    static let freePeriod = false
    static let trialDays: Double = 30
    static var isFree: Bool {
        guard freePeriod else { return false }
        let args = ProcessInfo.processInfo.arguments
        return !(args.contains("-paid-mode") || args.contains("-paywall") || args.contains("-quota-left"))
    }
}

extension Entitlement {
    func hasPro(at now: Date) -> Bool {
        if Launch.isFree || purchasedPro { return true }
        guard !Launch.freePeriod else { return false }
        guard let start = proStartedAt else { return true }
        return now < start.addingTimeInterval(Launch.trialDays * 86400)
    }
    func trialDaysLeft(at now: Date) -> Int? {
        guard !Launch.isFree, !purchasedPro else { return nil }
        guard let start = proStartedAt else { return Int(Launch.trialDays) }
        let left = start.addingTimeInterval(Launch.trialDays * 86400).timeIntervalSince(now) / 86400
        return left > 0 ? Int(left.rounded(.up)) : 0
    }
}
