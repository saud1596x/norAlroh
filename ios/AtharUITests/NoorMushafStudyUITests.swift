import XCTest

final class NoorMushafStudyUITests: XCTestCase {
    private var application: XCUIApplication?
    override func setUpWithError() throws { continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }
    override func tearDownWithError() throws {
        if let run = testRun, run.failureCount > 0, let application { print("STUDY_FAILURE_HIERARCHY\n" + application.debugDescription) }
        XCUIDevice.shared.orientation = .portrait
    }
    func testActualRepeatControlsPersistAndGapCancels() {
        let app = XCUIApplication(); application = app; launchNoorApp(app)
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 20)); app.buttons["home.resume"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "reader.page.ready").firstMatch.waitForExistence(timeout: 120))
        app.buttons["reader.jump"].tap()
        let jump = app.textFields["reader.pageNumber"]
        XCTAssertTrue(jump.waitForExistence(timeout: 5)); jump.tap(); jump.typeText("604"); app.buttons["انتقل"].tap()
        let verse = app.buttons["reader.verse.112:1"]
        XCTAssertTrue(verse.waitForExistence(timeout: 30)); verse.press(forDuration: 0.6)
        app.buttons["verse.repeat"].tap()
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
        XCTAssertTrue(verse.waitForExistence(timeout: 120)); verse.press(forDuration: 0.6); app.buttons["verse.repeat"].tap()
        XCTAssertTrue(count.waitForExistence(timeout: 10))
        XCTAssertTrue(numbers(count.label).contains(4)); XCTAssertTrue(numbers(delay.label).contains(2))
        capture(app, "repeat-options-restored-after-relaunch")
        app.buttons["verse.sheet.close"].tap()
    }
    // These journeys exercise the current one-tap acoustic reader. The old
    // self-grading setup is separately covered in memorization tests; it must
    // not be mistaken for the real microphone engine.
    // These journeys exercise the current one-tap acoustic reader. The old
    // self-grading setup is separately covered in memorization tests; it must
    // not be mistaken for the real microphone engine.
    func testFormerVoiceEntryOpensActualInlineMushafWithBundledModelWithoutAccount() {
        let app = XCUIApplication(); application = app
        openReader(app)
        app.buttons["reader.study"].press(forDuration: 0.6)
        app.buttons["الحفظ والمراجعة"].tap()
        let entry = app.buttons["hifz.speech"]
        XCTAssertTrue(entry.waitForExistence(timeout: 15))
        for _ in 0..<6 where !entry.isHittable { app.swipeUp() }
        XCTAssertTrue(entry.isHittable); entry.tap()
        XCTAssertTrue(app.staticTexts["study.elapsed"].waitForExistence(timeout: 60), "Bundled model must prepare and start the actual microphone")
        XCTAssertTrue(app.buttons["study.pause"].isHittable)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "reader.page.ready").firstMatch.exists)
        XCTAssertFalse(app.buttons["speech.prepare"].exists)
        XCTAssertFalse(app.buttons["speech.listen"].exists)
        capture(app, "former-voice-entry-now-real-inline-microphone")
        app.buttons["study.finish"].tap()
        XCTAssertTrue(app.staticTexts["study.result.saved"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.staticTexts["study.result.helped"].exists, "Acoustic tracking cannot invent an old self-assessment score")
        app.buttons["study.result.close"].tap(); app.buttons["إغلاق المصحف"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 10), "Leaving must restore the actual memorization navigation context")
        app.buttons["reader.memorization.close"].tap()
        app.buttons["إغلاق المصحف"].tap()
    }
    func testInlinePageSessionRevealPauseResumeAndPartialFinishSurviveRelaunch() {
        let app = XCUIApplication(); application = app
        openReader(app, page: 604)
        app.buttons["reader.study"].press(forDuration: 0.6)
        app.buttons["اختيار مقطع التسميع"].tap()
        XCTAssertTrue(app.buttons["recitation.scope.start"].waitForExistence(timeout: 10))
        app.buttons["تدريب إضافي"].tap()
        let closed = app.switches["recitation.scope.closedText"]
        XCTAssertTrue(closed.waitForExistence(timeout: 5))
        if closed.value as? String != "1" { closed.tap() }
        capture(app, "32-inline-mushaf-study-setup")
        app.buttons["recitation.scope.start"].tap()
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
        first.tap()
        let oneWord = app.buttons["كشف الكلمة التالية"]
        XCTAssertTrue(oneWord.waitForExistence(timeout: 5)); oneWord.tap()
        let paused = expectation(for: NSPredicate(format: "label CONTAINS %@", "استئناف"), evaluatedWith: app.buttons["study.pause"])
        wait(for: [paused], timeout: 20)
        XCTAssertEqual(first.frame, originalFrame, "A textual hint cannot reflow Quran glyphs")
        XCTAssertTrue(first.label.contains("مخفي"), "One hint must not expose the entire ayah to VoiceOver")
        capture(app, "38-practice-mushaf-hint")
        app.terminate(); launchNoorApp(app); app.buttons["home.resume"].tap()
        XCTAssertTrue(app.buttons["study.pause"].waitForExistence(timeout: 60))
        XCTAssertTrue(app.buttons["study.pause"].label.contains("استئناف"))
        XCTAssertTrue(first.label.contains("مخفي"))
        XCTAssertEqual(first.frame, originalFrame)
        first.tap(); app.buttons["كشف الآية كاملة"].tap()
        let exposed = expectation(for: NSPredicate(format: "NOT (label CONTAINS %@)", "مخفي"), evaluatedWith: first)
        wait(for: [exposed], timeout: 10)
        XCTAssertTrue(app.buttons["reader.verse.112:2"].label.contains("مخفي"), "Revealing one ayah cannot reveal the rest of the passage")
        XCTAssertEqual(first.frame, originalFrame)
        capture(app, "39-practice-mushaf-revealed")
        app.buttons["study.finish"].tap()
        XCTAssertTrue(app.staticTexts["study.result.saved"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.staticTexts["study.result.answered"].exists, "Heard-word evidence is not a subjective remembered-answer count")
        capture(app, "native-hint-assistance-result-after-recovery")
        app.buttons["study.result.close"].tap(); app.buttons["إغلاق المصحف"].tap()
    }
    func testMicCaptureBackgroundResumeAndPlaybackAreRealAndDurable() {
        // The full CI journey grants the simulator's actual OS permission for
        // this class after the independent denial journeys have completed.
        let app = XCUIApplication(); application = app
        openReader(app, page: 604)
        app.buttons["reader.study"].tap()
        let elapsed = app.staticTexts["study.elapsed"]
        XCTAssertTrue(elapsed.waitForExistence(timeout: 60))
        let captured = NSPredicate { object, _ in
            guard let text = object as? XCUIElement else { return false }
            return text.label.contains("تسجيل محلي") && (5...59).contains { text.label.contains(String(format: "0:%02d", $0)) }
        }
        let recording = expectation(for: captured, evaluatedWith: elapsed)
        wait(for: [recording], timeout: 30)
        capture(app, "17-recitation-controls")
        XCUIDevice.shared.press(.home); app.activate()
        let paused = expectation(for: NSPredicate(format: "label CONTAINS %@", "استئناف"), evaluatedWith: app.buttons["study.pause"])
        wait(for: [paused], timeout: 20)
        capture(app, "study-background-paused-with-durable-take")
        app.terminate(); launchNoorApp(app); app.buttons["home.resume"].tap()
        XCTAssertTrue(app.buttons["study.pause"].waitForExistence(timeout: 60))
        XCTAssertTrue(app.buttons["study.pause"].label.contains("استئناف"))
        let beforeResume = elapsed.label
        app.buttons["study.pause"].tap()
        let advanced = expectation(for: NSPredicate { _, _ in elapsed.label != beforeResume }, evaluatedWith: elapsed)
        wait(for: [advanced], timeout: 30)
        app.buttons["study.pause"].tap()
        let pausedAgain = expectation(for: NSPredicate(format: "label CONTAINS %@", "استئناف"), evaluatedWith: app.buttons["study.pause"])
        wait(for: [pausedAgain], timeout: 20)
        app.buttons["study.options"].tap(); app.buttons["study.recordings"].tap()
        let play = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "study.recording.play.")).firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 15), "An actual decodable microphone take must survive termination")
        XCTAssertGreaterThanOrEqual(play.frame.height, 44)
        XCTAssertGreaterThanOrEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "study.recording.play.")).count, 2,
            "Resume must retain the first closed take and save a distinct second take")
        capture(app, "study-recording-restored-and-playable")
        play.tap()
        let playing = expectation(for: NSPredicate(format: "label CONTAINS %@", "إيقاف مؤقت"), evaluatedWith: play)
        wait(for: [playing], timeout: 10)
        capture(app, "study-real-recording-playback")
        play.tap(); app.buttons["study.recordings.close"].tap()
        app.buttons["study.finish"].tap()
        XCTAssertTrue(app.staticTexts["study.result.saved"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.staticTexts["study.result.helped"].exists)
        capture(app, "study-recording-finish-without-automatic-grades")
        app.buttons["study.result.close"].tap()
        app.buttons["reader.study"].press(forDuration: 0.6); app.buttons["تسجيلاتي"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "study.recording.session.")).firstMatch.waitForExistence(timeout: 15))
        capture(app, "native-durable-recording-history")
        app.buttons["إغلاق"].tap(); app.buttons["إغلاق المصحف"].tap()
    }
    private func openReader(_ app: XCUIApplication, page: Int? = nil) {
        launchNoorApp(app)
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 20)); app.buttons["home.resume"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "reader.page.ready").firstMatch.waitForExistence(timeout: 120))
        if let page {
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
