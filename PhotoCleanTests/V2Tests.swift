import XCTest

final class V2Tests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }
    private var date: Date { Date(timeIntervalSince1970: 1_700_035_200) }
    private func photo(_ id: String, seconds: Double = 0) -> PhotoAsset {
        PhotoAsset(id: id, created: date.addingTimeInterval(seconds), modified: date, width: 100, height: 100, bytes: 10)
    }
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func nativeData<T>(_ values: [T]) -> Data { values.withUnsafeBytes { Data($0) } }
    func testEuclideanDistance() throws {
        XCTAssertEqual(try XCTUnwrap(FeatureVector.distance([0, 0], [3, 4])), 5, accuracy: 0.00001)
        XCTAssertEqual(try XCTUnwrap(FeatureVector.distance([1, 2, 3], [1, 2, 3])), 0)
        XCTAssertEqual(FeatureVector.distance([2, 3], [4, 5]), FeatureVector.distance([4, 5], [2, 3]))
    }
    func testDistanceRejectsInvalidVectors() {
        XCTAssertNil(FeatureVector.distance([], []))
        XCTAssertNil(FeatureVector.distance([0], [0, 1]))
        XCTAssertNil(FeatureVector.distance([.nan], [0]))
        XCTAssertNil(FeatureVector.distance([.infinity], [0]))
    }
    func testReadNativeFloatAndDoubleElements() {
        XCTAssertEqual(FeatureVector.read(nativeData([Float(0.125), -2]), count: 2, element: .float), [0.125, -2])
        XCTAssertEqual(FeatureVector.read(nativeData([Double(0.125), -2]), count: 2, element: .double), [0.125, -2])
    }
    func testReadElementsRejectsTruncatedAndNonfiniteData() {
        XCTAssertNil(FeatureVector.read(Data([0]), count: 1, element: .float))
        XCTAssertNil(FeatureVector.read(Data(), count: 0, element: .double))
        XCTAssertNil(FeatureVector.read(nativeData([Double.infinity]), count: 1, element: .double))
        XCTAssertNil(FeatureVector.read(nativeData([Double.greatestFiniteMagnitude]), count: 1, element: .double))
        XCTAssertNil(FeatureVector.read(nativeData([Float.nan]), count: 1, element: .float))
    }
    func testFeatureCacheRoundTrip768Floats() {
        let entries = ["asset|123": FeatureEntry(vector: (0..<768).map { Float($0) / 768 }, sharpness: 12.75),
                       "另一张|456": FeatureEntry(vector: [-1, 0, 2.5], sharpness: 0)]
        let data = FeatureCacheCodec.encode(entries)
        XCTAssertEqual(FeatureCacheCodec.decode(data), entries)
        XCTAssertLessThan(data.count, 4_000)
        XCTAssertEqual(FeatureCacheCodec.decode(FeatureCacheCodec.encode([:])), [:])
    }
    func testEveryTruncatedCachePrefixIsIgnored() {
        let data = FeatureCacheCodec.encode(["a|0": FeatureEntry(vector: [1, 2, 3], sharpness: 4)])
        for end in 0..<data.count { XCTAssertNil(FeatureCacheCodec.decode(Data(data.prefix(end))), "Prefix \(end)") }
    }
    func testEverySingleByteCacheCorruptionIsIgnored() {
        let data = FeatureCacheCodec.encode(["a|0": FeatureEntry(vector: [1, 2, 3], sharpness: 4)])
        for i in data.indices {
            var corrupt = data; corrupt[i] ^= 0x80
            XCTAssertNil(FeatureCacheCodec.decode(corrupt), "Byte \(i)")
        }
        XCTAssertNil(FeatureCacheCodec.decode(Data("invalid".utf8)))
        var trailing = data; trailing.append(0)
        XCTAssertNil(FeatureCacheCodec.decode(trailing))
    }
    func testDuplicateCacheKeysAndNonfiniteVectorsRejected() {
        let entry = FeatureEntry(vector: [1], sharpness: 0)
        var data = FeatureCacheCodec.header(count: 2)
        data.append(FeatureCacheCodec.record(key: "a", entry: entry))
        data.append(FeatureCacheCodec.record(key: "a", entry: entry))
        XCTAssertNil(FeatureCacheCodec.decode(data))
        XCTAssertNil(FeatureCacheCodec.decode(FeatureCacheCodec.encode(["a": FeatureEntry(vector: [.nan], sharpness: 0)])))
    }
    func testMonthRewriteInvalidatesOnlyChangedMonthAndPreservesOtherDays() throws {
        let directory = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let january = directory.appendingPathComponent("2026-01.bin"), february = directory.appendingPathComponent("2026-02.bin")
        let first = FeatureEntry(vector: [0.1, 0.2], sharpness: 8)
        let second = FeatureEntry(vector: [0.3, 0.4], sharpness: 16)
        var jan = FeatureMonthFile(url: january), feb = FeatureMonthFile(url: february)
        try jan.rewrite(keeping: ["a|1", "b|1"], adding: ["a|1": first])
        try jan.rewrite(keeping: ["a|1", "b|1"], adding: ["b|1": second])
        try feb.rewrite(keeping: ["c|1"], adding: ["c|1": first])
        let untouched = try Data(contentsOf: february)
        try jan.rewrite(keeping: ["a|2", "b|1"], adding: ["a|2": second])
        let loaded = FeatureMonthFile(url: january)
        XCTAssertNil(loaded.entry(for: "a|1"))
        XCTAssertEqual(loaded.entry(for: "a|2"), second)
        XCTAssertEqual(loaded.entry(for: "b|1"), second)
        XCTAssertEqual(try Data(contentsOf: february), untouched)
    }
    func testCorruptMonthCanBeRebuilt() throws {
        let directory = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("2026-01.bin")
        try Data([0, 1, 2]).write(to: url)
        var file = FeatureMonthFile(url: url)
        XCTAssertTrue(file.keys.isEmpty); XCTAssertNil(file.entry(for: "a"))
        let entry = FeatureEntry(vector: [1, 2], sharpness: 9)
        try file.rewrite(keeping: ["a"], adding: ["a": entry])
        XCTAssertEqual(FeatureMonthFile(url: url).entry(for: "a"), entry)
    }
    func testStreamingMonthRejectsLateTruncationAndCorruption() throws {
        let directory = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("2026-01.bin")
        let entry = FeatureEntry(vector: [1, 2], sharpness: 9)
        let valid = FeatureCacheCodec.encode(["a": entry, "b": entry])
        try Data(valid.dropLast()).write(to: url)
        XCTAssertTrue(FeatureMonthFile(url: url).keys.isEmpty)
        var corrupt = valid; corrupt[corrupt.count - 1] ^= 0x40
        try corrupt.write(to: url)
        XCTAssertTrue(FeatureMonthFile(url: url).keys.isEmpty)
    }
    func testDaysNewestFirstAndCalendarBoundary() {
        let start = calendar.startOfDay(for: date)
        var a = photo("a"), b = photo("b"), video = photo("v")
        a.created = start.addingTimeInterval(86390); b.created = start.addingTimeInterval(86410); video.isVideo = true
        let days = AnalysisDay.newestFirst([a, b, video], calendar: calendar)
        XCTAssertEqual(days.count, 2); XCTAssertEqual(days.first?.assets.map(\.id), ["b"])
        var east = calendar; east.timeZone = TimeZone(secondsFromGMT: 9 * 3600) ?? .current
        XCTAssertEqual(AnalysisDay.newestFirst([a, b], calendar: east).count, 1)
    }
    func testCompletedDaysSurviveRefreshWhileChangedAndRemovedDaysInvalidate() {
        let a = photo("a"), b = photo("b", seconds: 86400)
        let inputs = AnalysisDay.newestFirst([a, b], calendar: calendar)
        var ledger = AnalysisDays()
        for day in inputs { ledger.record(day, result: AnalysisResult(analyzed: 1, total: 1, complete: true)) }
        ledger.reconcile(inputs)
        XCTAssertEqual(ledger.result(total: 2).analyzed, 2)
        var changed = b; changed.modified = date.addingTimeInterval(5)
        ledger.reconcile(AnalysisDay.newestFirst([a, changed], calendar: calendar))
        XCTAssertEqual(ledger.completed.count, 1)
        ledger.reconcile([]); XCTAssertTrue(ledger.completed.isEmpty)
    }
    func testCloudAndFailedDaysRetryOnNextRefresh() {
        let day = AnalysisDay(id: "day", assets: [photo("a")])
        var ledger = AnalysisDays()
        ledger.record(day, result: AnalysisResult(analyzed: 1, total: 1, skippedCloud: 1, complete: true))
        ledger.reconcile([day]); XCTAssertTrue(ledger.completed.isEmpty)
        ledger.record(day, result: AnalysisResult(analyzed: 1, total: 1, failed: 1, complete: true))
        ledger.reconcile([day]); XCTAssertTrue(ledger.completed.isEmpty)
    }
    func testProgressiveDaysAppendGroupsAndCounters() {
        let a = photo("a"), b = photo("b"), group = PhotoGroup(assets: [photo("a"), photo("b")], bestID: "a")
        var ledger = AnalysisDays()
        ledger.record(AnalysisDay(id: "today", assets: [a, b]), result: AnalysisResult(similar: [group], analyzed: 2, total: 2, complete: true))
        let partial = ledger.result(total: 50_000)
        XCTAssertEqual(partial.similar.count, 1); XCTAssertEqual(partial.analyzed, 2); XCTAssertFalse(partial.complete)
        ledger.record(AnalysisDay(id: "yesterday", assets: []), result: AnalysisResult(duplicates: [group], analyzed: 3, total: 3, complete: true))
        XCTAssertEqual(ledger.result(total: 50_000).analyzed, 5)
        XCTAssertEqual(ledger.result(total: 50_000).duplicates.count, 1)
    }
    func testUIProgressNeverPublishesMoreThanTwicePerSecond() {
        var throttle = ProgressThrottle()
        XCTAssertTrue(throttle.take(at: 1))
        XCTAssertFalse(throttle.take(at: 1.1)); XCTAssertFalse(throttle.take(at: 1.499))
        XCTAssertEqual(throttle.delay(at: 1.25), 0.25, accuracy: 0.00001)
        XCTAssertTrue(throttle.take(at: 1.5)); XCTAssertFalse(throttle.take(at: 1.8))
    }
    @MainActor func testLibraryNotificationsDebounceIntoOneRefresh() async {
        let debouncer = RefreshDebouncer(delay: .milliseconds(30))
        let refreshed = expectation(description: "One refresh after the last change")
        var calls = 0
        for _ in 0..<20 { debouncer.schedule { calls += 1; refreshed.fulfill() } }
        XCTAssertEqual(calls, 0)
        await fulfillment(of: [refreshed], timeout: 2)
        XCTAssertEqual(calls, 1)
    }
    func testDuplicateMembersExcludedFromSimilarAndDistancesComputedOnce() {
        let assets = [photo("a"), photo("b"), photo("c"), photo("d")]
        var calls = 0
        let groups = AnalysisCore.classify(assets, calendar: calendar) { a, b in
            calls += 1
            return Set([a.id, b.id]) == Set(["a", "b"]) ? 0.01 : 0.1
        }
        XCTAssertEqual(calls, 6)
        XCTAssertEqual(Set(groups.duplicates.flatMap { $0.assets.map(\.id) }), ["a", "b"])
        XCTAssertEqual(Set(groups.similar.flatMap { $0.assets.map(\.id) }), ["c", "d"])
    }
    func testDuplicateExclusionDropsSimilarSingleton() {
        let groups = AnalysisCore.classify([photo("a"), photo("b"), photo("c")]) { a, b in
            Set([a.id, b.id]) == Set(["a", "b"]) ? 0.01 : 0.1
        }
        XCTAssertEqual(groups.duplicates.count, 1); XCTAssertTrue(groups.similar.isEmpty)
    }
    func testBurstCannotJoinDifferentCalendarDays() {
        var a = photo("a"), b = photo("b", seconds: 86400)
        a.burst = "burst"; b.burst = "burst"
        XCTAssertTrue(AnalysisCore.classify([a, b], calendar: calendar) { _, _ in nil }.similar.isEmpty)
    }
    func testPublishedGroupsRemoveDeletedAndChangedAssetsAndRefreshSizes() {
        let a = photo("a"), b = photo("b"), c = photo("c")
        let state = AnalysisResult(similar: [PhotoGroup(assets: [a, b, c], bestID: "a")])
        var updated = b; updated.bytes = 200; updated.favorite = true
        let filtered = state.restricted(to: ["a": a, "b": updated])
        XCTAssertEqual(filtered.similar.first?.assets.count, 2)
        XCTAssertEqual(filtered.similar.first?.bestID, "b")
        XCTAssertEqual(filtered.similar.first?.assets.first { $0.id == "b" }?.bytes, 200)
        updated.modified = date.addingTimeInterval(1)
        XCTAssertTrue(state.restricted(to: ["a": a, "b": updated]).similar.isEmpty)
    }
    func testResourceSizesRoundTripReuseAndModifiedKeyInvalidation() throws {
        let directory = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("sizes.json")
        var a = photo("a"), b = photo("b"), cache = ResourceSizeCache()
        cache.entries[a.cacheKey] = ResourceSizeCache.Entry(bytes: 123, approximate: false)
        cache.entries[b.cacheKey] = ResourceSizeCache.Entry(bytes: 456, approximate: true)
        try cache.save(url); cache = ResourceSizeCache.load(url)
        XCTAssertTrue(cache.apply(to: &a)); XCTAssertEqual(a.bytes, 123); XCTAssertFalse(a.approximate)
        XCTAssertTrue(cache.apply(to: &b)); XCTAssertTrue(b.approximate)
        a.modified = date.addingTimeInterval(1)
        XCTAssertFalse(cache.apply(to: &a))
        cache.retain([a, b]); XCTAssertEqual(cache.entries.count, 1)
        try Data("broken".utf8).write(to: url)
        XCTAssertTrue(ResourceSizeCache.load(url).entries.isEmpty)
    }
    func testHashtagsFollowAllThreeLanguagesAndRegionalVariants() {
        XCTAssertEqual(ShareText.hashtags(language: "zh-Hans"), "#相册清理 #iPhone内存不足 #断舍离")
        for language in ["zh-Hant", "zh-TW", "zh_HK", "zh-MO"] {
            XCTAssertEqual(ShareText.hashtags(language: language), "#相簿清理 #iPhone容量不足 #斷捨離")
        }
        XCTAssertEqual(ShareText.hashtags(language: "en"), "#photocleaner #iphonestorage #declutter")
        XCTAssertEqual(ShareText.hashtags(language: "fr"), ShareText.hashtags(language: "en"))
    }
    func testPartialQuotaDeletesOnlyRemainingAndKeepsRemainder() {
        let key = CalendarKey.day(date, calendar: calendar)
        var quota = Quota(firstDay: key, used: [key: 197])
        let basket = (0..<12).map { String($0) }
        let count = quota.batchCount(selected: basket.count, at: date, pro: false, calendar: calendar)
        XCTAssertEqual(count, 3)
        let deleted = Array(basket.prefix(count)), remainder = Array(basket.dropFirst(count))
        quota.record(count: deleted.count, success: true, at: date, calendar: calendar)
        XCTAssertEqual(remainder.count, 9)
        XCTAssertEqual(quota.remaining(at: date, pro: false, calendar: calendar), 0)
    }
    func testPartialQuotaBoundsZeroProCancelAndMidnight() {
        var quota = Quota(firstDay: CalendarKey.day(date, calendar: calendar))
        XCTAssertEqual(quota.batchCount(selected: 3, at: date, pro: false, calendar: calendar), 3)
        XCTAssertEqual(quota.batchCount(selected: -1, at: date, pro: true, calendar: calendar), 0)
        XCTAssertEqual(quota.batchCount(selected: 50_000, at: date, pro: true, calendar: calendar), 50_000)
        quota.record(count: 197, success: true, at: date, calendar: calendar)
        quota.record(count: 3, success: false, at: date, calendar: calendar)
        XCTAssertEqual(quota.batchCount(selected: 12, at: date, pro: false, calendar: calendar), 3)
        XCTAssertEqual(quota.batchCount(selected: 3, at: date.addingTimeInterval(86400), pro: false, calendar: calendar), 3)
        quota.record(count: 3, success: true, at: date, calendar: calendar)
        XCTAssertEqual(quota.batchCount(selected: 12, at: date, pro: false, calendar: calendar), 0)
    }
    func testKeepAllSurvivesProgressiveUpdatesAndNewGroupsArePreselected() {
        let first = PhotoGroup(assets: [photo("a"), photo("b")], bestID: "a")
        let second = PhotoGroup(assets: [photo("c"), photo("d")], bestID: "c")
        var selection = GroupSelection(); selection.update([first])
        XCTAssertEqual(selection.selected, ["b"])
        selection.keepAll(first); selection.update([first, second])
        XCTAssertEqual(selection.selected, ["d"])
        selection.update([first]); XCTAssertTrue(selection.selected.isEmpty)
    }
    func testSwipeWaitsForLoadingThenReceivesMonthAssets() {
        var session = SwipeSession()
        session.sync([], reviewed: [], fetching: true)
        XCTAssertFalse(session.loaded); XCTAssertTrue(session.loading(fetching: true))
        session.sync([photo("a"), photo("b")], reviewed: [], fetching: true)
        XCTAssertEqual(session.current?.id, "a"); XCTAssertFalse(session.loading(fetching: true))
    }
    func testSwipeSyncPreservesProgressUndoAndAcceptsArrivingAssets() {
        let a = photo("a"), b = photo("b"), c = photo("c")
        var session = SwipeSession(); session.sync([a, b], reviewed: [], fetching: true)
        XCTAssertTrue(session.advance("a", wasBasket: true))
        session.sync([a, b, c], reviewed: ["a"], fetching: false)
        XCTAssertEqual(session.index, 1); XCTAssertEqual(session.current?.id, "b")
        let undone = session.undo()
        XCTAssertEqual(undone?.photo.id, "a"); XCTAssertEqual(undone?.basket, true)
        XCTAssertEqual(session.photos.count, 3)
    }
    func testSwipeOnlyShowsFinishedAfterFetchCompletesAndHandlesExternalRemoval() {
        var session = SwipeSession()
        session.sync([], reviewed: [], fetching: false)
        XCTAssertTrue(session.loaded); XCTAssertFalse(session.loading(fetching: false))
        session.sync([photo("a")], reviewed: [], fetching: false)
        XCTAssertTrue(session.advance("a", wasBasket: false))
        XCTAssertTrue(session.loading(fetching: true))
        session.sync([], reviewed: ["a"], fetching: false)
        XCTAssertEqual(session.index, 0); XCTAssertTrue(session.history.isEmpty)
        XCTAssertFalse(session.advance("a", wasBasket: false))
    }
    func testStorageSegmentsCoverCapacityAndClampInvalidInputs() {
        let usage = StorageUsage(total: 100, free: 20, reclaimable: 30)
        XCTAssertEqual(usage.used, 0.5); XCTAssertEqual(usage.reclaimable, 0.3); XCTAssertEqual(usage.free, 0.2)
        let overflow = StorageUsage(total: 100, free: 20, reclaimable: 200)
        XCTAssertEqual(overflow.used, 0); XCTAssertEqual(overflow.reclaimable, 0.8)
        XCTAssertEqual(StorageUsage(total: 0, free: 20, reclaimable: 30).free, 1)
        XCTAssertEqual(StorageUsage(total: 100, free: 200, reclaimable: -1).free, 1)
    }
}
