import XCTest

@MainActor final class FlowUITests: XCTestCase {
    private var app = XCUIApplication()
    override func setUp() { continueAfterFailure = false }
    private func launch(_ extra: [String] = [], reset: Bool = true, keepClipboard: Bool = false, pasteText: String? = nil) {
        app.launchArguments = ["-demo", "-ui-testing", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
            + (reset ? ["-reset"] : []) + (keepClipboard ? ["-keep-clipboard"] : []) + extra
        app.launchEnvironment["PHOTOCLEAN_UI_TEST_PASTE_BASE64"] = pasteText.map { Data($0.utf8).base64EncodedString() }
        app.launch()
    }
    private func shot(_ name: String) throws {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        if let directory = ProcessInfo.processInfo.environment["TEST_RUNNER_SHOTS_DIR"], !directory.isEmpty {
            do {
                let url = URL(fileURLWithPath: directory, isDirectory: true)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                try png.write(to: url.appendingPathComponent(name + ".png"))
            } catch {
                let note = XCTAttachment(string: "Use xcresult screenshot attachment: \(error)"); note.lifetime = .keepAlways; add(note)
            }
        }
    }
    private func wait(_ condition: @escaping () -> Bool) -> Bool {
        let exp = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        return XCTWaiter.wait(for: [exp], timeout: 12) == .completed
    }
    private func tap(_ id: String) {
        let element = app.buttons[id].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 10), id)
        for _ in 0..<6 { if element.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(wait { element.isHittable && element.isEnabled }, id); element.tap()
    }
    private func progress(_ n: Int) {
        XCTAssertTrue(wait { self.app.staticTexts["swipeProgress"].label.hasPrefix("\(n) /") })
    }
    func testOnboardingSwipeUndoReviewDeleteAndShare() throws {
        launch(["-onboarding"])
        XCTAssertTrue(app.buttons["startCleaning"].waitForExistence(timeout: 10)); try shot("01-onboarding")
        tap("startCleaning")
        XCTAssertTrue(app.buttons["startMonthSwipe"].waitForExistence(timeout: 10)); try shot("02-home")
        tap("startMonthSwipe"); progress(0)
        let card = app.descendants(matching: .any).matching(identifier: "swipeCard").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10)); card.swipeLeft(); progress(1); try shot("03-swipe-left")
        card.swipeRight(); progress(2); try shot("04-swipe-right")
        tap("swipeDelete"); progress(3); try shot("04a-third-delete")
        tap("swipeKeep"); progress(4); try shot("04b-fourth-keep")
        tap("swipeDelete"); progress(5); try shot("04c-fifth-delete")
        tap("swipeUndo"); progress(4); try shot("05-undo")
        tap("swipeKeep"); progress(5); try shot("05b-fifth-kept-after-undo")
        tap("swipeReview")
        XCTAssertTrue(app.staticTexts["basketCount"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["basketCount"].label.contains("2")); try shot("06-review")
        tap("confirmDelete")
        XCTAssertTrue(app.buttons["openShare"].waitForExistence(timeout: 10))
        XCTAssertTrue(wait { self.app.staticTexts["deletedCount"].label.contains("2") }); try shot("07-celebration")
        XCTAssertTrue(app.descendants(matching: .any)["keptPhotos"].exists)
        tap("openShare")
        XCTAssertTrue(app.buttons["shareImage"].waitForExistence(timeout: 10)); try shot("08-share-card")
        tap("copyCaption"); tap("shareImage")
        XCTAssertTrue(app.staticTexts["share.requested"].waitForExistence(timeout: 10))
        try shot("09-share-requested")
    }
    func testSimilarToggleAndDelete() throws {
        launch(["-similar"])
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "select-")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 15)); try shot("10-similar")
        let old = first.value as? String
        first.tap(); XCTAssertTrue(wait { (first.value as? String) != old }); try shot("11-similar-toggle")
        first.tap(); XCTAssertTrue(wait { (first.value as? String) == old })
        tap("reviewCategory"); try shot("12-similar-review")
        tap("confirmDelete")
        XCTAssertTrue(app.buttons["openShare"].waitForExistence(timeout: 15)); try shot("13-similar-cleaned")
        XCTAssertFalse(app.descendants(matching: .any)["keptPhotos"].exists)
        tap("finishCleanup")
        XCTAssertTrue(app.buttons["startMonthSwipe"].waitForExistence(timeout: 10))
    }
    func testQuotaPaywallTomorrowAndBasketSurviveRelaunch() throws {
        launch(["-review", "-quota-left", "3"])
        XCTAssertTrue(app.staticTexts["basketCount"].waitForExistence(timeout: 10))
        let before = app.staticTexts["basketCount"].label; try shot("14-quota-review")
        tap("confirmDelete")
        XCTAssertTrue(app.buttons["tomorrow"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["quotaExplanation"].label.contains("3")); try shot("15-quota-paywall")
        tap("tomorrow")
        XCTAssertTrue(app.staticTexts["basketCount"].waitForExistence(timeout: 10)); XCTAssertEqual(app.staticTexts["basketCount"].label, before)
        try shot("16-tomorrow-basket-intact")
        tap("closeSheet"); app.terminate(); launch(reset: false)
        tap("openBasket"); XCTAssertEqual(app.staticTexts["basketCount"].label, before); try shot("17-restored-basket")
    }
    func testQuotaCanDeleteFirstThreeAndPreserveRemainingNine() throws {
        launch(["-review", "-quota-left", "3"])
        tap("confirmDelete"); tap("deleteRemainingQuota")
        XCTAssertTrue(app.buttons["openShare"].waitForExistence(timeout: 10))
        XCTAssertTrue(wait { self.app.staticTexts["deletedCount"].label.contains("3") })
        try shot("20-partial-quota-deleted-three")
        tap("finishCleanup"); tap("openBasket")
        XCTAssertTrue(app.staticTexts["basketCount"].label.contains("9"))
        try shot("21-partial-quota-nine-retained")
        tap("confirmDelete")
        XCTAssertTrue(app.buttons["tomorrow"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["deleteRemainingQuota"].exists)
        tap("tomorrow"); tap("closeSheet")
        app.terminate(); launch(reset: false); tap("openBasket")
        XCTAssertTrue(app.staticTexts["basketCount"].label.contains("9"))
    }
    func testDeniedAndSettings() throws {
        launch(["-denied"])
        XCTAssertTrue(app.buttons["openPhotoSettings"].waitForExistence(timeout: 10)); try shot("18-denied")
        app.terminate(); launch()
        tap("openSettings")
        XCTAssertTrue(app.buttons["settingsRestore"].waitForExistence(timeout: 10)); try shot("19-settings")
        tap("closeSheet")
        XCTAssertTrue(app.buttons["startMonthSwipe"].waitForExistence(timeout: 10))
    }
    func testHomeDesignAEntriesAndBackNavigation() throws {
        launch()
        XCTAssertTrue(app.buttons["startMonthSwipe"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["deviceStorageBar"].exists)
        for id in ["similar", "duplicates", "videos", "screenshots"] {
            let row = app.buttons["category-" + id]
            XCTAssertTrue(row.exists)
        }
        try shot("22-home-design-a")
        tap("openMonths")
        let firstMonth = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "month-")).firstMatch
        XCTAssertTrue(firstMonth.waitForExistence(timeout: 10))
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 10)); back.tap()
        tap("category-videos")
        let firstVideo = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "select-video-")).firstMatch
        XCTAssertTrue(firstVideo.waitForExistence(timeout: 10)); try shot("23-home-video-entry")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        tap("category-screenshots")
        let firstScreenshot = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "select-demo-")).firstMatch
        XCTAssertTrue(firstScreenshot.waitForExistence(timeout: 10)); try shot("24-home-screenshot-entry")
    }
    func testPartlyReviewedMonthReturnsToHeroAndBasket() throws {
        launch()
        tap("startMonthSwipe"); progress(0)
        tap("swipeDelete"); progress(1)
        tap("swipeKeep"); progress(2)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let hero = app.buttons["startMonthSwipe"]
        XCTAssertTrue(hero.waitForExistence(timeout: 10))
        XCTAssertTrue(wait { hero.label.contains("已整理 2 /") })
        try shot("25-home-partly-reviewed")
        tap("openBasket")
        XCTAssertTrue(app.staticTexts["basketCount"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["basketCount"].label.contains("1"))
    }
    func testCompletedMonthAndPosterPreview() throws {
        launch(["-months", "-month-complete"])
        let firstMonth = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "month-")).firstMatch
        XCTAssertTrue(firstMonth.waitForExistence(timeout: 10))
        XCTAssertTrue(firstMonth.label.contains("已整理完")); try shot("26-completed-month")
        app.terminate(); launch(["-celebrate"])
        XCTAssertTrue(app.buttons["openShare"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["keptPhotos"].exists)
        XCTAssertTrue(app.buttons["finishCleanup"].isHittable)
        try shot("27-kept-celebration")
        tap("openShare")
        let preview = app.images["sharePreview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        XCTAssertEqual(preview.frame.width / max(1, preview.frame.height), 0.75, accuracy: 0.02)
        try shot("28-poster-preview")
    }

    func testLaunchClipboardPreviewsAndImportsChallengeGoal() throws {
        let invitation = "Clean up together!\r\nPC1.250\r\nhttps://apps.apple.com/app/id6835040441"
        let goalLabel = "目标整理 250 张照片"
        launch(pasteText: invitation)
        let preview = app.staticTexts["challenge.preview.goal"]
        let activeGoal = app.staticTexts["challenge.active.goal"]
        if !preview.waitForExistence(timeout: 10) {
            try shot("29-challenge-preview-missing")
            XCTFail("启动口令未显示预览。\n\(app.debugDescription)")
            return
        }
        XCTAssertEqual(preview.label, goalLabel)
        XCTAssertFalse(activeGoal.exists)
        try shot("29-challenge-preview")
        tap("challenge.import")
        XCTAssertTrue(activeGoal.waitForExistence(timeout: 10))
        XCTAssertEqual(activeGoal.label, goalLabel)
        XCTAssertFalse(preview.exists)
        try shot("30-challenge-imported")

        app.terminate()
        launch(reset: false, pasteText: "PC1.0")
        XCTAssertTrue(activeGoal.waitForExistence(timeout: 10))
        XCTAssertEqual(activeGoal.label, goalLabel)
        XCTAssertFalse(app.buttons["challenge.import"].exists)

        tap("openSettings")
        tap("inviteFriend")
        tap("shareApp")
        XCTAssertTrue(app.staticTexts["share.requested"].waitForExistence(timeout: 10))
        app.terminate()
        launch(keepClipboard: true)
        let paste = app.descendants(matching: .any)["challenge.paste"].firstMatch
        XCTAssertTrue(paste.waitForExistence(timeout: 10))
        XCTAssertFalse(preview.exists)
        XCTAssertTrue(wait { paste.isHittable })
        paste.tap()
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        XCTAssertEqual(preview.label, goalLabel)
    }

    func testStoreJapanese() throws {
        for (name, extra) in [("home", [String]()), ("swipe", ["-swipe"]), ("similar", ["-similar"]),
                              ("celebrate", ["-celebrate"]), ("share", ["-celebrate", "-share"])] {
            app.terminate()
            app.launchArguments = ["-demo", "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"] + extra
            app.launch()
            sleep(4)
            try shot("store-ja-" + name)
        }
    }
}
