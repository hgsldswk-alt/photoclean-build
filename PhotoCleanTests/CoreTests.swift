import Foundation
import XCTest

final class CoreTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0) ?? .current; return c
    }
    private var date: Date { Date(timeIntervalSince1970: 1_700_035_200) }
    private func photo(_ id: String, seconds: Double = 0, width: Int = 100, height: Int = 100, favorite: Bool = false,
                       burst: String? = nil, pick: Bool = false, sharpness: Double = 0) -> PhotoAsset {
        PhotoAsset(id: id, created: date.addingTimeInterval(seconds), modified: date.addingTimeInterval(seconds), width: width, height: height,
            bytes: 1_000_000, favorite: favorite, burst: burst, burstPick: pick, sharpness: sharpness)
    }
    private func groups(_ assets: [PhotoAsset], duplicate: Bool = false, d: Float = 0.1) -> [PhotoGroup] {
        AnalysisCore.groups(assets, duplicates: duplicate, calendar: calendar) { _, _ in d }
    }
    func testEmptyGroups() { XCTAssertTrue(groups([]).isEmpty) }
    func testSinglePhotoIsNotGroup() { XCTAssertTrue(groups([photo("a")]).isEmpty) }
    func testSimilarThresholdStrict() {
        XCTAssertTrue(groups([photo("a"), photo("b")], d: AnalysisCore.similarThreshold).isEmpty)
        XCTAssertEqual(groups([photo("a"), photo("b")], d: 0.349).count, 1)
    }
    func testDuplicateThresholdStrict() {
        XCTAssertTrue(groups([photo("a"), photo("b")], duplicate: true, d: 0.05).isEmpty)
        XCTAssertEqual(groups([photo("a"), photo("b")], duplicate: true, d: 0.049).count, 1)
    }
    func testDuplicateRequiresBothDimensions() {
        XCTAssertTrue(groups([photo("a"), photo("b", width: 50, height: 200)], duplicate: true, d: 0.01).isEmpty)
    }
    func testSimilarAllowsDifferentDimensions() { XCTAssertEqual(groups([photo("a"), photo("b", width: 200)]).count, 1) }
    func testTimeWindowInclusive() { XCTAssertEqual(groups([photo("a"), photo("b", seconds: 600)]).count, 1) }
    func testOutsideTimeWindow() { XCTAssertTrue(groups([photo("a"), photo("b", seconds: 601)]).isEmpty) }
    func testSameDayRequired() {
        let day = calendar.startOfDay(for: date)
        var a = photo("a"), b = photo("b")
        a.created = day.addingTimeInterval(86390); b.created = day.addingTimeInterval(86410)
        XCTAssertTrue(groups([a,b]).isEmpty)
    }
    func testOnlyThirtyAhead() {
        let photos = (0..<80).map { photo(String($0), seconds: Double($0)) }
        let pairs = AnalysisCore.candidates(photos, calendar: calendar)
        XCTAssertTrue(pairs.allSatisfy { $0.1 - $0.0 <= 30 })
        XCTAssertEqual(pairs.filter { $0.0 == 0 }.count, 30)
    }
    func testUnionFindTransitivity() {
        let result = AnalysisCore.groups([photo("a"), photo("b", seconds: 500), photo("c", seconds: 1000)], duplicates: false, calendar: calendar) { _, _ in 0.1 }
        XCTAssertEqual(result.count, 1); XCTAssertEqual(result.first?.assets.count, 3)
    }
    func testUnknownDistanceSkipped() { XCTAssertTrue(AnalysisCore.groups([photo("a"), photo("b")], duplicates: false) { _, _ in nil }.isEmpty) }
    func testNaNDistanceSkipped() { XCTAssertTrue(groups([photo("a"), photo("b")], d: .nan).isEmpty) }
    func testVideosExcludedFromSimilarity() {
        var video = photo("b"); video.isVideo = true
        XCTAssertTrue(groups([photo("a"), video]).isEmpty)
    }
    func testBurstGroupsOutsideWindowWithoutFeatures() {
        let assets = [photo("a", burst: "burst"), photo("b", seconds: 2000, burst: "burst")]
        XCTAssertEqual(AnalysisCore.groups(assets, duplicates: false) { _, _ in nil }.count, 1)
        XCTAssertTrue(AnalysisCore.groups(assets, duplicates: true) { _, _ in nil }.isEmpty)
    }
    func testFavoriteWinsResolution() {
        XCTAssertEqual(AnalysisCore.best([photo("a", width: 800), photo("b", favorite: true)])?.id, "b")
    }
    func testAllFavoritesNeverPreselected() {
        let group = groups([photo("a", favorite: true), photo("b", favorite: true)]).first
        XCTAssertTrue(group?.selectedIDs.isEmpty == true)
    }
    func testSystemBurstPickWinsResolution() { XCTAssertEqual(AnalysisCore.best([photo("a", width: 800), photo("b", pick: true)])?.id, "b") }
    func testResolutionWinsSharpness() { XCTAssertEqual(AnalysisCore.best([photo("a", width: 800), photo("b", sharpness: 900)])?.id, "a") }
    func testSharpnessWinsModification() { XCTAssertEqual(AnalysisCore.best([photo("a", sharpness: 4), photo("b", seconds: 10)])?.id, "a") }
    func testNewestModificationBreaksTie() { XCTAssertEqual(AnalysisCore.best([photo("a"), photo("b", seconds: 1)])?.id, "b") }
    func testTieIsDeterministic() { XCTAssertEqual(AnalysisCore.best([photo("z"), photo("a")])?.id, "a") }
    func testBestPhotoNotPreselected() {
        let group = groups([photo("a", sharpness: 9), photo("b")]).first
        XCTAssertEqual(group?.selectedIDs, Set(["b"]))
    }
    func testFirstDayQuota200() {
        let q = Quota(firstDay: CalendarKey.day(date, calendar: calendar))
        XCTAssertEqual(q.remaining(at: date, pro: false, calendar: calendar), 200)
        XCTAssertTrue(q.permits(200, at: date, pro: false, calendar: calendar))
        XCTAssertFalse(q.permits(201, at: date, pro: false, calendar: calendar))
    }
    func testDailyQuota50() {
        let q = Quota(firstDay: "2000-01-01")
        XCTAssertEqual(q.remaining(at: date, pro: false, calendar: calendar), 50)
    }
    func testQuotaMidnightRollover() {
        let first = calendar.startOfDay(for: date).addingTimeInterval(86399), next = first.addingTimeInterval(2)
        var q = Quota(firstDay: CalendarKey.day(first, calendar: calendar))
        q.record(count: 200, success: true, at: first, calendar: calendar)
        XCTAssertEqual(q.remaining(at: first, pro: false, calendar: calendar), 0)
        XCTAssertEqual(q.remaining(at: next, pro: false, calendar: calendar), 50)
    }
    func testQuotaTimeZoneUsesLocalCalendarAndNeverResetsLedger() {
        var east = calendar; east.timeZone = TimeZone(secondsFromGMT: 9*3600) ?? .current
        let nearMidnight = calendar.startOfDay(for: date).addingTimeInterval(20*3600)
        var q = Quota(firstDay: "2000-01-01")
        q.record(count: 50, success: true, at: nearMidnight, calendar: calendar)
        XCTAssertEqual(q.remaining(at: nearMidnight, pro: false, calendar: east), 50)
        q.record(count: 50, success: true, at: nearMidnight, calendar: east)
        XCTAssertEqual(q.remaining(at: nearMidnight, pro: false, calendar: calendar), 0)
        XCTAssertEqual(q.remaining(at: nearMidnight, pro: false, calendar: east), 0)
    }
    func testProUnlimited() { XCTAssertTrue(Quota().permits(100000, at: date, pro: true)); XCTAssertEqual(Quota().remaining(at: date, pro: true), Int.max) }
    func testCancelDoesNotConsume() {
        var q = Quota(firstDay: "2000-01-01"); q.record(count: 40, success: false, at: date)
        XCTAssertEqual(q.remaining(at: date, pro: false), 50)
    }
    func testSuccessConsumesExactlyActualCount() {
        var q = Quota(firstDay: "2000-01-01"); q.record(count: 17, success: true, at: date)
        XCTAssertEqual(q.remaining(at: date, pro: false), 33)
    }
    func testZeroAndNegativeDeletionRejected() {
        XCTAssertFalse(Quota().permits(0, at: date, pro: true)); XCTAssertFalse(Quota().permits(-1, at: date, pro: true))
    }
    func testMonthGroupingNewestFirst() {
        var a = photo("a"), b = photo("b"); a.created = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)) ?? date
        b.created = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1)) ?? date
        XCTAssertEqual(AnalysisCore.months([a,b], calendar: calendar).map(\.id), ["2026-02","2026-01"])
    }
    func testCoreReviewRequiresThreeActionsOnTwoLocalDates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let firstDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 23)))
        let nextDay = firstDay.addingTimeInterval(2 * 3600)
        let empty = try JSONDecoder().decode(CoreReviewProgress.self, from: Data("{}".utf8))
        XCTAssertFalse(empty.isEligible)
        var progress = CoreReviewProgress.recording(empty, at: firstDay, calendar: calendar)
        var twoDays = progress
        twoDays.record(at: nextDay, calendar: calendar)
        XCTAssertFalse(twoDays.isEligible)
        progress.record(at: firstDay, calendar: calendar)
        XCTAssertFalse(progress.isEligible)

        var sameDay = progress
        sameDay.record(at: firstDay, calendar: calendar)
        XCTAssertFalse(sameDay.isEligible)

        let data = try JSONEncoder().encode(progress)
        progress = try JSONDecoder().decode(CoreReviewProgress.self, from: data)
        progress.record(at: nextDay, calendar: calendar)
        XCTAssertTrue(progress.isEligible)
    }

    func testMonthReviewedCountIgnoresStaleIDs() {
        XCTAssertEqual(PhotoMonth(id: "2026-01", assets: [photo("a"),photo("b")]).reviewed(["a","removed"]), 1)
    }
    func testScreenshotsOnly() { var a = photo("a"); a.screenshot = true; XCTAssertEqual(AnalysisCore.screenshots([a,photo("b")]).map(\.id), ["a"]) }
    func testLargeVideosTopThirtyOrFiftyMB() {
        let videos = (0..<40).map { n -> PhotoAsset in var a = photo(String(n)); a.isVideo = true; a.bytes = Int64(n)*1_000_000; return a }
        let selected = AnalysisCore.largeVideos(videos)
        XCTAssertEqual(selected.count, 30); XCTAssertEqual(selected.first?.bytes, 39_000_000)
        let large = videos.map { a -> PhotoAsset in var b = a; b.bytes += 50_000_000; return b }
        XCTAssertEqual(AnalysisCore.largeVideos(large).count, 40)
    }
    func testStatsByCleanupMonthAndTotals() {
        var stats = Stats(); _ = stats.record([photo("a"),photo("b")], at: date, calendar: calendar)
        XCTAssertEqual(stats.total, CleanupTotal(bytes: 2_000_000, count: 2))
        XCTAssertEqual(stats.monthly[CalendarKey.month(date, calendar: calendar)]?.count, 2)
    }
    func testMilestonesAreOnlyReturnedOnce() {
        var stats = Stats(), a = photo("a"); a.bytes = 5_000_000_000
        XCTAssertEqual(stats.record([a], at: date), ["gb-1","gb-5"])
        a.bytes = 1; XCTAssertTrue(stats.record([a], at: date).isEmpty)
    }
    func testCountMilestones() { XCTAssertEqual(Stats.milestones(CleanupTotal(bytes: 0,count: 10000)), ["photos-1000","photos-10000"]) }
    func testEmptyCleanupDoesNotIncrementStats() { var s = Stats(); _ = s.record([], at: date); XCTAssertEqual(s.successfulCleanups, 0) }
    func testReviewRequiresTwoLargeCleanupsTwoDaysAndNewVersion() {
        var s = Stats(); s.largeCleanups = 2
        XCTAssertTrue(ReviewGate.eligible(stats: s, firstOpen: date, now: date.addingTimeInterval(2*86400), version: "1", reviewedVersion: nil, afterPaywallOrError: false))
        XCTAssertFalse(ReviewGate.eligible(stats: s, firstOpen: date, now: date, version: "1", reviewedVersion: nil, afterPaywallOrError: false))
        XCTAssertFalse(ReviewGate.eligible(stats: s, firstOpen: date, now: date.addingTimeInterval(3*86400), version: "1", reviewedVersion: "1", afterPaywallOrError: false))
        XCTAssertFalse(ReviewGate.eligible(stats: s, firstOpen: date, now: date.addingTimeInterval(3*86400), version: "1", reviewedVersion: nil, afterPaywallOrError: true))
        s.largeCleanups = 1
        XCTAssertFalse(ReviewGate.eligible(stats: s, firstOpen: date, now: date.addingTimeInterval(3*86400), version: "1", reviewedVersion: nil, afterPaywallOrError: false))
    }
    func testOldPartialStoreDecodesDefaults() throws {
        let data = try JSONDecoder().decode(AppData.self, from: Data("{\"version\":1}".utf8))
        XCTAssertTrue(data.basket.isEmpty); XCTAssertFalse(data.entitlement.purchasedPro); XCTAssertFalse(data.reminderEnabled)
    }
    func testMistypedOptionalFieldDoesNotLoseOtherData() throws {
        let data = try JSONDecoder().decode(AppData.self, from: Data("{\"version\":1,\"onboarded\":true,\"basket\":42}".utf8))
        XCTAssertTrue(data.onboarded); XCTAssertTrue(data.basket.isEmpty)
    }
    func testCorruptStoreFailsExplicitly() { XCTAssertThrowsError(try JSONDecoder().decode(AppData.self, from: Data("broken".utf8))) }
    func testFutureVersionRejected() { XCTAssertThrowsError(try JSONDecoder().decode(AppData.self, from: Data("{\"version\":999}".utf8))) }
    func testStoreRoundTripIncludesBasketProgressQuotaAndStats() throws {
        let name = "photoclean.test." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name)); defer { defaults.removePersistentDomain(forName: name) }
        var data = AppData(); data.basket = ["a"]; data.reviewed["2026-01"] = ["b"]
        data.quota.record(count: 7, success: true, at: date); _ = data.stats.record([photo("a")], at: date)
        try Store.save(data, to: defaults); let loaded = try Store.load(from: defaults)
        XCTAssertEqual(loaded.basket, data.basket); XCTAssertEqual(loaded.reviewed, data.reviewed); XCTAssertEqual(loaded.quota, data.quota); XCTAssertEqual(loaded.stats, data.stats)
    }
    func testShareCaptionAlwaysContainsProtocolHashtags() { XCTAssertTrue(ShareText.caption(bytes: 1234, count: 3).contains(ShareText.hashtags)) }
    func testPlaceholderAppStoreIDHasNoQRURL() { XCTAssertNil(ShareText.downloadURL(id: "__APP_STORE_ID__")); XCTAssertNil(ShareText.downloadURL(id: "")); XCTAssertNil(ShareText.downloadURL(id: "0")) }
    func testNumericAppStoreIDMakesCorrectURL() { XCTAssertEqual(ShareText.downloadURL(id: "123456")?.absoluteString, "https://apps.apple.com/app/id123456") }
    func testBytesUsesFormatterAndClampsNegatives() {
        XCTAssertEqual(Bytes.format(-1), Bytes.format(0)); XCTAssertFalse(Bytes.format(1_000_000).isEmpty)
        XCTAssertEqual(Bytes.total([photo("a"),photo("b")]), 2_000_000)
    }
    func testMalformedMonthRejected() { XCTAssertNil(CalendarKey.monthDate("2026-99")); XCTAssertNil(CalendarKey.monthDate("not-a-month")) }
}
