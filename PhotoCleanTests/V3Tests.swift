import XCTest
import UIKit

final class V3Tests: XCTestCase {
    private func calendar(_ zone: String = "Asia/Tokyo") -> Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: zone) ?? .current
        return result
    }
    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, calendar: Calendar) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
    }
    private func asset(_ id: String, bytes: Int64 = 1) -> PhotoAsset {
        PhotoAsset(id: id, created: Date(timeIntervalSince1970: 0), modified: Date(timeIntervalSince1970: 0), bytes: bytes)
    }

    func testDemoDatesNeverExceedLaunchAndSpanFourteenMonths() throws {
        for zone in ["Asia/Tokyo", "America/Los_Angeles", "Pacific/Kiritimati"] {
            let c = calendar(zone)
            for now in [try date(2026, 11, 15, 9, calendar: c), try date(2026, 11, 1, calendar: c),
                        try date(2024, 3, 1, calendar: c), try date(2026, 3, 8, 3, calendar: c)] {
                let photos = DemoCatalog.makeAssets(now: now, calendar: c)
                XCTAssertEqual(photos.count, 14 * 172 + 12)
                XCTAssertTrue(photos.allSatisfy { $0.created <= now && $0.modified <= now })
                let months = AnalysisCore.months(photos, calendar: c)
                XCTAssertEqual(months.count, 14)
                XCTAssertEqual(months.first?.id, CalendarKey.month(now, calendar: c))
                XCTAssertTrue(zip(photos, photos.dropFirst()).allSatisfy { pair in pair.0.created >= pair.1.created })
            }
        }
    }
    func testDemoMetadataIsStableForTheSameLaunchAnchor() {
        let now = Date(timeIntervalSince1970: 1_794_701_000)
        XCTAssertEqual(DemoCatalog.makeAssets(now: now, calendar: calendar()), DemoCatalog.makeAssets(now: now, calendar: calendar()))
    }
    func testAllTenScenesAndPhoneScreenshotsAppearEachMonth() {
        let photos = DemoCatalog.makeAssets(now: Date(), calendar: calendar())
        for month in AnalysisCore.months(photos, calendar: calendar()) {
            let stills = month.assets.filter { !$0.isVideo && !$0.screenshot }
            XCTAssertEqual(Set(stills.map { DemoCatalog.appearance($0).scene.rawValue }).count, 10)
            XCTAssertFalse(month.assets.filter(\.screenshot).isEmpty)
        }
        XCTAssertTrue(photos.filter(\.isVideo).allSatisfy { $0.duration > 0 })
    }
    func testDuplicateAppearancesMatchAndSimilarShotsVaryWithinAScene() {
        let duplicates = (0..<4).map { DemoCatalog.appearance(asset("demo-\($0)")) }
        XCTAssertTrue(duplicates.allSatisfy { $0 == duplicates[0] })
        let similar = (4..<8).map { DemoCatalog.appearance(asset("demo-\($0)")) }
        XCTAssertEqual(Set(similar.map(\.seed)).count, 4)
        XCTAssertEqual(Set(similar.map { $0.scene.rawValue }).count, 1)
        let burst = (40..<46).map { DemoCatalog.appearance(asset("demo-\($0)")) }
        XCTAssertEqual(Set(burst.map { $0.scene.rawValue }).count, 1)
    }
    func testDemoDuplicateSequencesRemainWithinAnalysisTimeWindow() throws {
        let c = calendar()
        for now in [try date(2026, 11, 1, calendar: c), try date(2026, 11, 15, 9, calendar: c)] {
            let photos = DemoCatalog.makeAssets(now: now, calendar: c)
            for month in 0..<14 {
                for group in 0..<3 {
                    let ids = Set((0..<4).map { "demo-\(month * 172 + group * 4 + $0)" })
                    let members = photos.filter { ids.contains($0.id) }.sorted { $0.created < $1.created }
                    XCTAssertEqual(members.count, 4)
                    XCTAssertLessThanOrEqual(try XCTUnwrap(members.last).created.timeIntervalSince(try XCTUnwrap(members.first).created), 600)
                    XCTAssertEqual(Set(members.map { CalendarKey.day($0.created, calendar: c) }).count, 1)
                }
            }
        }
    }
    func testCapacityDeduplicatesOverlappingScreenshotAndPhotoSelections() {
        let a = asset("photo", bytes: 123)
        var b = asset("video", bytes: 456); b.isVideo = true
        var c = asset("screenshot", bytes: 789); c.screenshot = true; c.approximate = true
        let summary = HomeCapacity(reclaimable: [a, b, c, c, a])
        XCTAssertEqual(summary.values, [123, 456, 789])
        XCTAssertEqual(summary.total, 1368); XCTAssertTrue(summary.approximate)
        XCTAssertEqual(HomeCapacity(reclaimable: []).values, [0, 0, 0])
        XCTAssertEqual(HomeCapacity(reclaimable: [asset("bad", bytes: -100)]).total, 0)
    }
    func testCapacityNumberAndUnitComeFromByteCountFormatter() {
        for bytes in [Int64(0), 999, 999_999, 1_200_000, 8_900_000_000, 1_200_000_000_000] {
            let parts = Bytes.components(bytes)
            let f = ByteCountFormatter(); f.countStyle = .file
            f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
            f.includesActualByteCount = false; f.allowsNonnumericFormatting = false
            let full = f.string(fromByteCount: bytes)
            XCTAssertFalse(parts.number.isEmpty); XCTAssertFalse(parts.unit.isEmpty)
            XCTAssertTrue(full.contains(parts.number)); XCTAssertTrue(full.contains(parts.unit))
            XCTAssertNotNil(parts.number.rangeOfCharacter(from: .decimalDigits))
        }
    }
    func testRendererUsesRequestedPixelDimensionsForPortraitAndLandscape() throws {
        let look = DemoCatalog.appearance(asset("demo-15"))
        for size in [CGSize(width: 40, height: 44), CGSize(width: 300, height: 400), CGSize(width: 320, height: 180)] {
            let image = DemoSceneRenderer.draw(look, size: size)
            let cg = try XCTUnwrap(image.cgImage)
            XCTAssertEqual(cg.width, Int(size.width)); XCTAssertEqual(cg.height, Int(size.height))
            XCTAssertEqual(image.scale, 1)
        }
    }
    func testDuplicatePixelsAreIdenticalAndSimilarPixelsDiffer() throws {
        let size = CGSize(width: 120, height: 160)
        func png(_ index: Int) throws -> Data {
            try XCTUnwrap(DemoSceneRenderer.draw(DemoCatalog.appearance(asset("demo-\(index)")), size: size).pngData())
        }
        XCTAssertEqual(try png(0), try png(1))
        XCTAssertNotEqual(try png(4), try png(5))
    }
    func testEveryRenderedSceneHasDistinctPixelsAndScreenshotIsDistinct() throws {
        let images = try DemoCatalog.Scene.allCases.map { scene in
            try XCTUnwrap(DemoSceneRenderer.draw(.init(scene: scene, seed: 123, screenshot: false), size: CGSize(width: 120, height: 160)).pngData())
        }
        XCTAssertEqual(Set(images).count, 10)
        let screenshot = try XCTUnwrap(DemoSceneRenderer.draw(.init(scene: .sunset, seed: 123, screenshot: true), size: CGSize(width: 120, height: 160)).pngData())
        XCTAssertFalse(images.contains(screenshot))
    }
}
