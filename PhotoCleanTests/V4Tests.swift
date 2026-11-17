import XCTest
import SwiftUI
import UIKit

final class V4Tests: XCTestCase {
    private func asset(_ id: String, video: Bool = false) -> PhotoAsset {
        PhotoAsset(id: id, created: Date(timeIntervalSince1970: 0), modified: Date(timeIntervalSince1970: 0), isVideo: video)
    }

    func testCompletedRingUsesTheEntireCircleInByteProportions() {
        let spans = CapacityRing.spans(values: [60, 30, 10], progress: 1)
        XCTAssertEqual(spans[0].start, 0)
        XCTAssertEqual(spans[0].end, 0.6, accuracy: 0.000001)
        XCTAssertEqual(spans[1].end, 0.9, accuracy: 0.000001)
        XCTAssertEqual(spans[2].end, 1, accuracy: 0.000001)
        XCTAssertEqual(spans[1].start, spans[0].end)
        XCTAssertEqual(spans[2].start, spans[1].end)
    }
    func testRingLeavesTrackOnlyForUnanalyzedFraction() {
        let spans = CapacityRing.spans(values: [60, 30, 10], progress: 0.4)
        XCTAssertEqual(spans[2].end, 0.4, accuracy: 0.000001)
        XCTAssertEqual(spans[0].end, 0.24, accuracy: 0.000001)
        XCTAssertEqual(CapacityRing.spans(values: [0, 7, 0], progress: 5)[1].end, 1)
        XCTAssertTrue(CapacityRing.spans(values: [0, -1, 0], progress: 1).allSatisfy { $0.start == 0 && $0.end == 0 })
        XCTAssertTrue(CapacityRing.spans(values: [1, 1, 1], progress: .nan).allSatisfy { $0.end == 0 })
    }
    func testHeroMonthUsesNumericChineseAndAbbreviatedEnglish() {
        for language in ["zh_Hans_CN", "zh_Hant_TW"] {
            let title = CalendarKey.heroMonth("2026-11", locale: Locale(identifier: language))
            XCTAssertTrue(title.contains("11"), title)
            XCTAssertFalse(title.contains("十一"), title)
        }
        XCTAssertEqual(CalendarKey.heroMonth("2026-11", locale: Locale(identifier: "en_US")), "Nov")
    }
    func testMosaicSamplesAreDistinctAndSpanTheWholeMonth() {
        let photos = (0..<13).map { asset("p-\($0)") }
        let sample = PhotoPresentation.samples(photos, limit: 4)
        XCTAssertEqual(sample.map(\.id), ["p-0", "p-4", "p-8", "p-12"])
        XCTAssertEqual(Set(sample.map(\.id)).count, 4)
        XCTAssertEqual(PhotoPresentation.samples(photos, limit: 1).map(\.id), ["p-0"])
    }
    func testMosaicDoesNotDuplicateSparsePhotosOrSampleVideos() {
        let photos = [asset("a"), asset("video", video: true), asset("b")]
        XCTAssertEqual(PhotoPresentation.samples(photos, limit: 4).map(\.id), ["a", "b"])
        XCTAssertTrue(PhotoPresentation.samples(photos, limit: 0).isEmpty)
        XCTAssertTrue(PhotoPresentation.samples([], limit: 4).isEmpty)
    }
    func testKeptPhotosExcludeUnreviewedPendingDeletionAndUnavailableIDs() {
        let month = PhotoMonth(id: "2026-11", assets: [asset("keep"), asset("pending"), asset("unseen"), asset("movie", video: true)])
        let photos = PhotoPresentation.kept(in: month, reviewed: ["keep", "pending", "gone", "movie"], basket: ["pending"])
        XCTAssertEqual(photos.map(\.id), ["keep"])
        XCTAssertTrue(PhotoPresentation.kept(in: nil, reviewed: ["keep"], basket: []).isEmpty)
        XCTAssertTrue(PhotoPresentation.kept(in: month, reviewed: [], basket: []).isEmpty)
    }
    func testKeptStripNeverLeaksPhotosFromAnotherMonth() {
        let month = PhotoMonth(id: "2026-10", assets: [asset("october")])
        XCTAssertTrue(PhotoPresentation.kept(in: month, reviewed: ["november"], basket: []).isEmpty)
    }
    func testDemoDuplicateSceneDiffersFromTheFirstSimilarBurst() {
        let duplicate = DemoCatalog.appearance(asset("demo-0"))
        let burst = DemoCatalog.appearance(asset("demo-40"))
        XCTAssertNotEqual(duplicate.scene, burst.scene)
        XCTAssertEqual(duplicate, DemoCatalog.appearance(asset("demo-1")))
    }
    func testDuplicatePreviewChoosesADifferentSceneWithoutChangingGroupMembership() {
        let sunset = (40..<43).map { asset("demo-\($0)") }
        let stillLife = (0..<4).map { asset("demo-\($0)") }
        let groups = [PhotoGroup(assets: sunset, bestID: sunset[0].id), PhotoGroup(assets: stillLife, bestID: stillLife[0].id)]
        let preview = PhotoPresentation.groupPreview(groups, avoiding: sunset[0], demo: true)
        XCTAssertEqual(preview.map(\.id), Array(stillLife.prefix(3)).map(\.id))
        XCTAssertEqual(groups[0].assets, sunset)
        XCTAssertTrue(PhotoPresentation.groupPreview([], avoiding: sunset[0], demo: true).isEmpty)
    }
    @MainActor func testPosterExports1080By1440ForEmptyNormalAndEstimatedReceipts() throws {
        let receipts = [CleanupReceipt(), CleanupReceipt(count: 128, bytes: 1_480_000_000, before: 9_800_000_000),
                        CleanupReceipt(count: 123_456, bytes: 123_456_789_000, approximate: true, before: 999_999_999_000)]
        for (index, receipt) in receipts.enumerated() {
            let renderer = ImageRenderer(content: ShareCard(receipt: receipt))
            renderer.proposedSize = ProposedViewSize(width: 540, height: 720)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            let cg = try XCTUnwrap(image.cgImage)
            XCTAssertEqual(cg.width, 1080); XCTAssertEqual(cg.height, 1440)
            let attachment = XCTAttachment(image: image)
            attachment.name = "v4-poster-\(index)"; attachment.lifetime = .keepAlways; add(attachment)
        }
    }
}
