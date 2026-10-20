import XCTest

final class NoorMushafStudyUITests: XCTestCase {
    private var application: XCUIApplication?
    override func setUpWithError() throws { continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }
    override func tearDownWithError() throws {
        if let run = testRun, run.failureCount > 0, let application { print("STUDY_FAILURE_HIERARCHY\n" + application.debugDescription) }
        XCUIDevice.shared.orientation = .portrait
    }
    func testActualRepeatControlsPersistAndGapCancels() throws {
        let app = XCUIApplication(); application = app; launchNoorApp(app)
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 20)); app.buttons["home.resume"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "reader.page.ready").firstMatch.waitForExistence(timeout: 120))
        app.buttons["reader.jump"].tap()
        let jump = app.textFields["reader.pageNumber"]
        XCTAssertTrue(jump.waitForExistence(timeout: 5)); jump.tap(); jump.typeText("604"); app.buttons["انتقل"].tap()
        let verse = app.buttons["reader.verse.112:1"]
        XCTAssertTrue(verse.waitForExistence(timeout: 30)); verse.press(forDuration: 0.6)
        try revealNoorVerseAction("verse.repeat", in: app).tap()
        let count = app.steppers["verse.repeat.count"]
        let delay = app.steppers["verse.repeat.delay"]
        XCTAssertTrue(count.waitForExistence(timeout: 10)); XCTAssertTrue(delay.exists)
        count.buttons["verse.repeat.count-Increment"].tap()
        delay.buttons["verse.repeat.delay-Increment"].tap(); delay.buttons["verse.repeat.delay-Increment"].tap()
        capture(app, "repeat-actual-count-and-delay-controls")
        app.buttons["verse.repeat.start"].tap()
        let stop = app.buttons["reader.audio.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 45), "Actual network Quran playback must start")
        let waiting = expectation(for: NSPredicate(format: "label CONTAINS %@", "المهلة"), evaluatedWith: stop)
        wait(for: [waiting], timeout: 30)
        capture(app, "repeat-real-gap-with-visible-stop")
        stop.tap()
        XCTAssertTrue(app.buttons["reader.study"].waitForExistence(timeout: 5))
        let cancelled = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: stop)
        wait(for: [cancelled], timeout: 5)
        app.terminate(); launchNoorApp(app)
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 20)); app.buttons["home.resume"].tap()
        XCTAssertTrue(verse.waitForExistence(timeout: 120)); verse.press(forDuration: 0.6)
        try revealNoorVerseAction("verse.repeat", in: app).tap()
        XCTAssertTrue(count.waitForExistence(timeout: 10))
        XCTAssertTrue(numbers(count.label).contains(4)); XCTAssertTrue(numbers(delay.label).contains(2))
        capture(app, "repeat-options-restored-after-relaunch")
        app.buttons["verse.sheet.close"].tap()
    }
    // Real capture journeys remain in the full microphone suite. The user
    // removed dedicated setup/history/grade screens; capture is still actual.
    func testOneTapStartsActualInlineMicrophoneWithoutSetupOrAccount() {
        let app = XCUIApplication(); application = app;openReader(app)
        app.buttons["reader.study"].tap()
        XCTAssertTrue(app.staticTexts["study.elapsed"].waitForExistence(timeout:60))
        XCTAssertTrue(app.buttons["study.pause"].isHittable)
        XCTAssertTrue(app.descendants(matching:.any)["reader.page.ready"].exists)
        XCTAssertFalse(app.buttons["recitation.scope.start"].exists)
        XCTAssertFalse(app.buttons["hifz.speech"].exists)
        capture(app,"one-tap-inline-actual-microphone")
        app.buttons["study.finish"].tap()
        XCTAssertTrue(app.buttons["reader.study"].waitForExistence(timeout:30))
        XCTAssertFalse(app.staticTexts["study.result.saved"].exists)
        XCTAssertFalse(app.staticTexts["study.result.helped"].exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format:"label == %@","إغلاق المصحف")).count,1)
        app.buttons["إغلاق المصحف"].tap()
        XCTAssertTrue(app.buttons["surah.1"].waitForExistence(timeout:10),
                      "Stopping and closing returns to the ordinary Mushaf index, even with an active daily ward")
    }
    func testFirstMicrophoneAllowStartsCaptureFromTheOriginalTap() {
        // XCTest resets the real Simulator microphone permission first.
        // No injected permission result, source PCM or pre-grant is used here.
        let app = XCUIApplication(); application = app
        app.resetAuthorizationStatus(for: .microphone)
        openReader(app)
        let page = app.descendants(matching: .any).matching(identifier: "reader.page.ready").firstMatch
        let frame = page.frame
        app.buttons["reader.study"].tap()
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = system.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 15), "First microphone permission must be an actual OS dialog")
        let text = alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ").lowercased()
        guard text.contains("microphone") || text.contains("ميكروفون") else {
            XCTFail("Unexpected system dialog; do not approve another permission: \(text)"); return
        }
        let allow = alert.buttons.matching(NSPredicate(format: "label IN %@", ["Allow", "OK", "السماح", "سماح", "موافق"])).firstMatch
        XCTAssertTrue(allow.isHittable); allow.tap()
        let elapsed = app.staticTexts["study.elapsed"]
        XCTAssertTrue(elapsed.waitForExistence(timeout: 30))
        let actualFrames = expectation(for: NSPredicate { _, _ in
            let label = elapsed.label // One actual accessibility snapshot per poll.
            return (5...59).contains { label.contains(String(format: "0:%02d", $0)) }
        }, evaluatedWith: elapsed)
        wait(for: [actualFrames], timeout: 30)
        XCTAssertEqual(page.frame, frame)
        XCTAssertTrue(app.buttons["study.pause"].isHittable)
        XCTAssertFalse(app.buttons["recitation.scope.start"].exists)
        capture(app, "first-system-microphone-allow-without-second-tap")
        app.buttons["study.finish"].tap()
        XCTAssertTrue(app.buttons["reader.study"].waitForExistence(timeout: 30))
    }
    func testInlinePageVisibilitySurvivesPauseButNewLaunchHasNoRecordingHistory() {
        let app = XCUIApplication(); application = app
        openReader(app, page: 604)
        let visibility = app.buttons["reader.textVisibility"]
        if visibility.value as? String != "الآيات مخفية" { visibility.tap() }
        app.buttons["reader.study"].tap()
        XCTAssertTrue(app.staticTexts["study.elapsed"].waitForExistence(timeout: 60))
        let first = app.buttons["reader.verse.112:1"]
        XCTAssertTrue(first.waitForExistence(timeout: 10)); XCTAssertTrue(first.label.contains("مخفي"))
        let originalFrame = first.frame
        for id in ["study.pause", "study.finish", "study.options"] {
            let action = app.buttons[id]
            XCTAssertTrue(action.isHittable, id)
            XCTAssertGreaterThanOrEqual(action.frame.width, 44, id)
            XCTAssertGreaterThanOrEqual(action.frame.height, 44, id)
            XCTAssertFalse(action.frame.intersects(first.frame), "Controls must not cover Quran ink")
        }
        capture(app, "37-practice-mushaf-hidden")
        first.press(forDuration: 0.6)
        let oneWord = app.buttons["كشف الكلمة التالية"]
        XCTAssertTrue(oneWord.waitForExistence(timeout: 5)); oneWord.tap()
        let paused = expectation(for: NSPredicate(format: "label CONTAINS %@", "استئناف"), evaluatedWith: app.buttons["study.pause"])
        wait(for: [paused], timeout: 20)
        XCTAssertEqual(first.frame, originalFrame, "A textual hint cannot reflow Quran glyphs")
        XCTAssertTrue(first.label.contains("مخفي"), "One hint must not expose the entire ayah to VoiceOver")
        capture(app, "38-practice-mushaf-hint")
        XCTAssertTrue(app.buttons["study.pause"].waitForExistence(timeout: 60))
        XCTAssertTrue(app.buttons["study.pause"].label.contains("استئناف"))
        XCTAssertTrue(first.label.contains("مخفي"))
        XCTAssertEqual(first.frame, originalFrame)
        first.press(forDuration: 0.6); app.buttons["كشف الآية كاملة"].tap()
        let exposed = expectation(for: NSPredicate(format: "NOT (label CONTAINS %@)", "مخفي"), evaluatedWith: first)
        wait(for: [exposed], timeout: 10)
        XCTAssertTrue(app.buttons["reader.verse.112:2"].label.contains("مخفي"), "Revealing one ayah cannot reveal the rest of the passage")
        XCTAssertEqual(first.frame, originalFrame)
        capture(app, "39-practice-mushaf-revealed")
        app.buttons["study.finish"].tap()
        XCTAssertTrue(app.buttons["reader.study"].waitForExistence(timeout: 30), "Stopping returns to the same Mushaf")
        XCTAssertFalse(app.staticTexts["study.result.saved"].exists)
        XCTAssertFalse(app.staticTexts["study.result.answered"].exists, "Heard-word evidence is not a subjective remembered-answer count")
        capture(app, "native-hint-assistance-result-without-history")
        app.buttons["إغلاق المصحف"].tap()
        app.terminate(); openReader(app, page: 604)
        XCTAssertTrue(app.buttons["reader.study"].exists)
        XCTAssertFalse(app.buttons["study.finish"].exists)
        XCTAssertFalse(app.buttons["study.recordings"].exists)
        app.buttons["إغلاق المصحف"].tap()
    }
    func testMicCaptureBackgroundResumeStaysInMushafWithoutHistory() {
        executionTimeAllowance = 180
        // The full CI journey grants the simulator's actual OS permission for
        // this class after the independent denial journeys have completed.
        let app = XCUIApplication(); application = app
        openReader(app, page: 604)
        app.buttons["reader.study"].tap()
        let elapsed = app.staticTexts["study.elapsed"]
        XCTAssertTrue(elapsed.waitForExistence(timeout: 60))
        let captured = NSPredicate { object, _ in
            guard let text = object as? XCUIElement else { return false }
            return (5...59).contains { text.label.contains(String(format: "0:%02d", $0)) }
        }
        let recording = expectation(for: captured, evaluatedWith: elapsed)
        wait(for: [recording], timeout: 30)
        capture(app, "17-recitation-controls")
        XCUIDevice.shared.press(.home); app.activate()
        let paused = expectation(for: NSPredicate(format: "label CONTAINS %@", "استئناف"), evaluatedWith: app.buttons["study.pause"])
        wait(for: [paused], timeout: 20)
        capture(app, "study-background-paused-with-temporary-audio")
        let beforeResume = elapsed.label
        app.buttons["study.pause"].tap()
        let advanced = expectation(for: NSPredicate { _, _ in elapsed.label != beforeResume }, evaluatedWith: elapsed)
        wait(for: [advanced], timeout: 30)
        app.buttons["study.pause"].tap()
        let pausedAgain = expectation(for: NSPredicate(format: "label CONTAINS %@", "استئناف"), evaluatedWith: app.buttons["study.pause"])
        wait(for: [pausedAgain], timeout: 20)
        app.buttons["study.options"].tap()
        XCTAssertFalse(app.buttons["study.recordings"].exists)
        app.buttons["study.reciters"].tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout:10))
        app.buttons["إغلاق"].tap()
        XCTAssertTrue(app.buttons["study.pause"].waitForExistence(timeout:10))
        capture(app,"actual-capture-resumed-with-inline-reader-controls")
        app.buttons["study.finish"].tap()
        XCTAssertTrue(app.buttons["reader.study"].waitForExistence(timeout: 30), "Stopping returns to the same Mushaf")
        XCTAssertFalse(app.staticTexts["study.result.saved"].exists)
        XCTAssertFalse(app.staticTexts["study.result.helped"].exists)
        capture(app, "study-recording-finish-without-automatic-grades")
        app.buttons["reader.more"].tap()
        XCTAssertTrue(app.buttons["reader.options.close"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["تسجيلاتي"].exists)
        XCTAssertFalse(app.buttons["الحفظ والمراجعة"].exists)
        app.buttons["reader.options.close"].tap();app.buttons["إغلاق المصحف"].tap()
    }

    private func openReader(_ app: XCUIApplication, page: Int? = nil) {
        launchNoorApp(app)
        // Home intentionally replaces ordinary resume with the reading-only
        // daily ward/completed message when a plan exists. Exercise the actual
        // public Mushaf route instead of requiring the previous test to erase
        // its real plan or accidentally opening a ward without a microphone.
        selectNoorTab("المصحف", in: app)
        let targetChapter = page == 604 ? 112 : 1
        // A distant List row is not materialized until it is found/scrolled.
        // Use the same public search that users see, never seed navigation.
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap(); search.typeText(String(targetChapter) + "\n")
        let surah = app.buttons["surah.\(targetChapter)"]
        XCTAssertTrue(surah.waitForExistence(timeout: 10)); surah.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "reader.page.ready").firstMatch.waitForExistence(timeout: 120))
        if let page {
            XCTAssertTrue(app.buttons["reader.jump"].waitForExistence(timeout: 10))
            app.buttons["reader.jump"].tap()
            let field = app.textFields["reader.pageNumber"]
            XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText(String(page)); app.buttons["انتقل"].tap()
            XCTAssertTrue(app.buttons["reader.verse.112:1"].waitForExistence(timeout: 30))
        }
    }
    private func numbers(_ text: String) -> [Int] {
        text.split { $0.wholeNumberValue == nil }.map { $0.reduce(0) { $0 * 10 + ($1.wholeNumberValue ?? 0) } }
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
}
