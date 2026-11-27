import Foundation
import XCTest

final class ChallengeCodeTests: XCTestCase {
    func testInvitationAndBareCodeRoundTrip() {
        let url = ShareText.downloadURL(id: "6835040441")
        let invitation = ChallengeCode.invitation(goal: 250, downloadURL: url)
        XCTAssertTrue(invitation.contains("\nPC1.250\n"))
        XCTAssertTrue(invitation.hasSuffix("https://apps.apple.com/app/id6835040441"))
        XCTAssertEqual(ChallengeCode.decode(invitation), 250)
        XCTAssertEqual(ChallengeCode.decode("Message\r\n  PC1.250  \r\nLink"), 250)
        XCTAssertEqual(ChallengeCode.decode(ChallengeCode.encode(goal: 1)), 1)
        XCTAssertEqual(ChallengeCode.decode(ChallengeCode.encode(goal: 10_000)), 10_000)
    }

    func testIgnoresMalformedCodesAndOtherText() {
        for text in ["Clean up together", "PC2.250", "PC1.", "PC1.0", "PC1.-10", "PC1.+10", "PC1.0250",
                     "PC1.10001", "PC1.２５０", "PC1.25.0", "https://example.test/PC1.250"] {
            XCTAssertNil(ChallengeCode.decode(text), text)
        }
    }

    func testChallengeGoalPersistsAndOldDataStillDecodes() throws {
        let decoder = JSONDecoder()
        var data = try decoder.decode(AppData.self, from: Data("{\"version\":1,\"onboarded\":true}".utf8))
        XCTAssertNil(data.challengeGoal)
        data.challengeGoal = 250
        let restored = try decoder.decode(AppData.self, from: JSONEncoder().encode(data))
        XCTAssertEqual(restored.challengeGoal, 250)
        XCTAssertTrue(restored.onboarded)
        let invalid = try decoder.decode(AppData.self, from: Data("{\"challengeGoal\":10001}".utf8))
        XCTAssertNil(invalid.challengeGoal)
    }
}
