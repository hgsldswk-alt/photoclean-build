import XCTest

final class LaunchTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    func testPaidBuild() { XCTAssertFalse(Launch.freePeriod); XCTAssertFalse(Launch.isFree) }
    func testTrialRunsThirtyDaysFromFirstPaidLaunch() {
        var e = Entitlement(); e.proStartedAt = now
        XCTAssertTrue(e.hasPro(at: now.addingTimeInterval(29 * 86400)))
        XCTAssertFalse(e.hasPro(at: now.addingTimeInterval(31 * 86400)))
        XCTAssertEqual(e.trialDaysLeft(at: now), 30)
        XCTAssertEqual(e.trialDaysLeft(at: now.addingTimeInterval(31 * 86400)), 0)
    }
    func testWidgetBeforeFirstOpenIsNotLocked() { XCTAssertTrue(Entitlement().hasPro(at: now)) }
    func testPurchasedAlwaysPro() {
        var e = Entitlement(); e.purchasedPro = true; e.proStartedAt = now
        XCTAssertTrue(e.hasPro(at: now.addingTimeInterval(400 * 86400))); XCTAssertNil(e.trialDaysLeft(at: now))
    }
    func testAfterTrialDailyLimitApplies() {
        var e = Entitlement(); e.proStartedAt = now
        let later = now.addingTimeInterval(40 * 86400)
        var quota = Quota(); quota.firstDay = CalendarKey.day(now)
        XCTAssertFalse(quota.permits(51, at: later, pro: e.hasPro(at: later)))
        XCTAssertTrue(quota.permits(50, at: later, pro: e.hasPro(at: later)))
    }
    func testOldStoredEntitlementWithoutStartDateDecodes() throws {
        let decoded = try JSONDecoder().decode(Entitlement.self, from: Data(#"{"purchasedPro":false}"#.utf8))
        XCTAssertNil(decoded.proStartedAt); XCTAssertFalse(decoded.purchasedPro)
    }
}
