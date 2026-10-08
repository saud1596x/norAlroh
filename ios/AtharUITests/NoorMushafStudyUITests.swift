import XCTest

final class NoorMushafStudyUITests: XCTestCase {
    private var application: XCUIApplication?
    override func setUpWithError() throws { continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }
    override func tearDownWithError() throws {
        if let run = testRun, run.failureCount > 0, let application { print("STUDY_FAILURE_HIERARCHY\n" + application.debugDescription) }
        XCUIDevice.shared.orientation = .portrait
    }
    func testActualRepeatControlsPersistAndGapCancels() {
        let app = XCUIApplication(); application = app; app.launch()
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
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 20)); app.buttons["home.resume"].tap()
        XCTAssertTrue(verse.waitForExistence(timeout: 120)); verse.press(forDuration: 0.6); app.buttons["verse.repeat"].tap()
        XCTAssertTrue(count.waitForExistence(timeout: 10))
        XCTAssertTrue(numbers(count.label).contains(4)); XCTAssertTrue(numbers(delay.label).contains(2))
        capture(app, "repeat-options-restored-after-relaunch")
        app.buttons["verse.sheet.close"].tap()
    }
    func testDailyGoalPersistsAndCompletedPracticeCountsOnce() {
        let app = XCUIApplication(); application = app; app.launch()
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 20)); app.buttons["home.resume"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "reader.page.ready").firstMatch.waitForExistence(timeout: 120))
        app.buttons["reader.study"].tap()
        let goal = app.buttons["study.goal.open"]
        for _ in 0..<3 { if goal.exists && goal.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(goal.isHittable); goal.tap()
        let enabled = app.switches["study.goal.enabled"]
        XCTAssertTrue(enabled.waitForExistence(timeout: 10))
        let control = enabled.switches.firstMatch
        XCTAssertTrue(control.exists); XCTAssertTrue(control.isHittable)
        XCTAssertEqual(control.value as? String, "0"); control.tap()
        XCTAssertEqual(control.value as? String, "1")
        let target = app.staticTexts["study.goal.target"]
        XCTAssertTrue(target.waitForExistence(timeout: 10)); XCTAssertTrue(numbers(target.label).contains(7))
        XCTAssertGreaterThanOrEqual(app.buttons["study.goal.increase"].frame.height, 44)
        XCTAssertGreaterThanOrEqual(app.buttons["study.goal.decrease"].frame.height, 44)
        app.buttons["study.goal.increase"].tap(); XCTAssertTrue(numbers(target.label).contains(8))
        app.buttons["study.goal.decrease"].tap(); XCTAssertTrue(numbers(target.label).contains(7))
        capture(app, "study-goal-configured-with-real-controls")
        app.buttons["study.goal.save"].tap()
        let progress = app.staticTexts["study.goal.progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 10)); XCTAssertTrue(progress.isHittable); XCTAssertEqual(numbers(progress.label), [0, 7])
        app.buttons["study.setup.close"].tap(); app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 20)); app.buttons["home.resume"].tap()
        XCTAssertTrue(app.buttons["reader.study"].waitForExistence(timeout: 120)); app.buttons["reader.study"].tap()
        for _ in 0..<3 { if progress.exists && progress.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(progress.waitForExistence(timeout: 10)); XCTAssertTrue(progress.isHittable); XCTAssertEqual(numbers(progress.label), [0, 7])
        capture(app, "study-goal-restored-after-relaunch")
        app.swipeDown(); app.buttons["study.scope"].tap(); app.buttons["نطاق آيات"].tap()
        app.buttons["study.start"].tap()
        XCTAssertTrue(app.buttons["study.remembered"].waitForExistence(timeout: 10)); app.buttons["study.remembered"].tap()
        XCTAssertTrue(app.staticTexts["study.result.saved"].waitForExistence(timeout: 10))
        app.buttons["study.result.close"].tap(); app.buttons["reader.study"].tap()
        for _ in 0..<3 { if progress.exists && progress.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(progress.waitForExistence(timeout: 10)); XCTAssertTrue(progress.isHittable); XCTAssertEqual(numbers(progress.label), [1, 7])
        capture(app, "study-goal-counts-completed-self-session")
        app.buttons["study.setup.close"].tap(); app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 20)); app.buttons["home.resume"].tap()
        XCTAssertTrue(app.buttons["reader.study"].waitForExistence(timeout: 120)); app.buttons["reader.study"].tap()
        for _ in 0..<3 { if progress.exists && progress.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(progress.waitForExistence(timeout: 10)); XCTAssertTrue(progress.isHittable); XCTAssertEqual(numbers(progress.label), [1, 7])
        capture(app, "study-goal-progress-restored-after-relaunch")
        app.buttons["study.setup.close"].tap()
    }
    func testFormerVoiceEntryOpensActualInlineMushafWithoutModelOrAccount() {
        let app = XCUIApplication(); application = app; app.launch()
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 20))
        selectNoorTab("الحفظ", in: app)
        let entry = app.buttons["hifz.speech"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        if !entry.isHittable { app.swipeUp() }
        XCTAssertTrue(entry.isHittable); entry.tap()
        XCTAssertTrue(app.buttons["study.start"].waitForExistence(timeout: 120), "Actual reader setup opens directly from the former voice entry")
        XCTAssertFalse(app.buttons["speech.prepare"].exists)
        XCTAssertFalse(app.buttons["speech.listen"].exists)
        capture(app, "inline-entry-without-model-or-account")
        app.buttons["study.start"].tap()
        XCTAssertTrue(app.buttons["study.finish"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "reader.page.ready").firstMatch.exists)
        XCTAssertTrue(app.buttons["study.mic"].isHittable)
        XCTAssertTrue(app.buttons["study.revealWord"].isHittable)
        capture(app, "former-voice-entry-now-actual-mushaf-session")
        app.buttons["study.finish"].tap()
        XCTAssertTrue(app.staticTexts["study.result.saved"].waitForExistence(timeout: 10))
        XCTAssertEqual(numbers(app.staticTexts["study.result.answered"].label).first, 0)
        app.buttons["study.result.close"].tap()
        app.buttons["إغلاق المصحف"].tap()
        XCTAssertTrue(app.buttons["hifz.speech"].waitForExistence(timeout: 10), "Leaving returns to the same navigation context")
    }
    func testInlinePageSessionRevealPauseResumeAndPartialFinishSurviveRelaunch() {
        let app = XCUIApplication(); application = app; app.launch()
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 20)); app.buttons["home.resume"].tap()
        let page = app.descendants(matching: .any).matching(identifier: "reader.page.ready").firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 120))
        app.buttons["reader.jump"].tap()
        let number = app.textFields["reader.pageNumber"]
        XCTAssertTrue(number.waitForExistence(timeout: 5)); number.tap(); number.typeText("604"); app.buttons["انتقل"].tap()
        XCTAssertTrue(app.buttons["reader.verse.112:1"].waitForExistence(timeout: 30))
        app.buttons["reader.study"].tap()
        XCTAssertTrue(app.buttons["study.start"].waitForExistence(timeout: 5)); app.buttons["study.start"].tap()
        XCTAssertTrue(app.buttons["study.revealWord"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["reader.jump"].exists, "Session stays in the Mushaf and replaces only its tools")
        let first = app.descendants(matching: .any).matching(identifier: "reader.verse.112:1").firstMatch
        XCTAssertFalse(app.buttons["reader.verse.112:1"].exists, "Locked study text must not pretend to be an actionable verse button")
        XCTAssertTrue(first.label.contains("مخفي"), "Hidden Quran must not leak through VoiceOver")
        let originalFrame = first.frame
        for id in ["study.revealWord", "study.revealAll", "study.listen", "study.remembered", "study.review", "study.skip", "study.pause", "study.finish", "study.mic", "study.recordings"] {
            let action = app.buttons[id]; XCTAssertTrue(action.isHittable, id)
            XCTAssertGreaterThanOrEqual(action.frame.width, 44, id); XCTAssertGreaterThanOrEqual(action.frame.height, 44, id)
            XCTAssertFalse(action.frame.intersects(first.frame), id)
        }
        app.buttons["study.mic"].tap()
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let denialNames = ["Don’t Allow", "Don't Allow", "عدم السماح", "لا تسمح"]
        let deny = system.buttons.matching(NSPredicate(format: "label IN %@", argumentArray: [denialNames])).firstMatch
        let appeared = deny.waitForExistence(timeout: 15)
        if !appeared { print("STUDY_PERMISSION_SYSTEM_HIERARCHY\n" + system.debugDescription); capture(app, "study-permission-failure-actual-screen") }
        XCTAssertTrue(appeared, "Exercise actual iOS microphone denial after the system prompt exists")
        deny.tap()
        XCTAssertTrue(app.buttons["متابعة التسميع"].waitForExistence(timeout: 10))
        app.buttons["متابعة التسميع"].tap()
        XCTAssertTrue(app.buttons["study.remembered"].isEnabled, "Microphone denial must not block self recitation")
        capture(app, "study-604-hidden-controls")
        app.buttons["study.revealWord"].tap()
        XCTAssertEqual(first.frame, originalFrame, "Revealing a word must not reflow Quran")
        capture(app, "study-604-progressive-reveal")
        app.buttons["study.pause"].tap()
        XCTAssertFalse(app.buttons["study.remembered"].isEnabled)
        XCTAssertFalse(app.buttons["study.revealWord"].isEnabled)
        XCTAssertEqual(first.frame, originalFrame)
        capture(app, "study-604-paused")
        app.buttons["study.pause"].tap(); app.buttons["study.revealAll"].tap()
        XCTAssertFalse(first.label.contains("مخفي")); XCTAssertEqual(first.frame, originalFrame)
        app.buttons["study.remembered"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "reader.verse.112:2").firstMatch.label.contains("مخفي"))
        app.buttons["study.review"].tap()
        capture(app, "study-604-two-answers")
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 20)); app.buttons["home.resume"].tap()
        XCTAssertTrue(page.waitForExistence(timeout: 120)); app.buttons["reader.study"].tap()
        XCTAssertTrue(app.buttons["study.resume"].waitForExistence(timeout: 5)); app.buttons["study.resume"].tap()
        XCTAssertTrue(app.buttons["study.finish"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "reader.verse.112:3").firstMatch.label.contains("مخفي"))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "reader.verse.112:1").firstMatch.label.contains("مخفي"))
        capture(app, "study-604-restored")
        app.buttons["study.finish"].tap()
        XCTAssertTrue(app.staticTexts["study.result.saved"].waitForExistence(timeout: 10))
        XCTAssertEqual(numbers(app.staticTexts["study.result.answered"].label), [2, 15])
        XCTAssertEqual(numbers(app.staticTexts["study.result.helped"].label), [1, 1])
        capture(app, "study-partial-result-persisted")
        app.buttons["study.result.close"].tap(); app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 20)); app.buttons["home.resume"].tap()
        XCTAssertTrue(page.waitForExistence(timeout: 120)); app.buttons["reader.study"].tap()
        XCTAssertTrue(app.staticTexts["study.result.saved"].waitForExistence(timeout: 5))
        XCTAssertEqual(numbers(app.staticTexts["study.result.answered"].label), [2, 15])
        capture(app, "study-result-restored-after-second-relaunch")
        app.buttons["study.scope"].tap(); app.buttons["سورة"].tap()
        app.buttons["study.start"].tap()
        for ayah in 1...4 {
            let verse = app.descendants(matching: .any).matching(identifier: "reader.verse.112:\(ayah)").firstMatch
            XCTAssertTrue(verse.waitForExistence(timeout: 10))
            XCTAssertTrue(verse.label.contains("مخفي"))
            app.buttons["study.remembered"].tap()
        }
        XCTAssertTrue(app.staticTexts["study.result.saved"].waitForExistence(timeout: 10))
        XCTAssertEqual(numbers(app.staticTexts["study.result.answered"].label), [4, 4])
        capture(app, "study-full-surah-completed")
        app.buttons["study.result.close"].tap(); app.buttons["reader.study"].tap()
        app.buttons["study.scope"].tap(); app.buttons["نطاق آيات"].tap()
        app.buttons["study.start"].tap()
        XCTAssertTrue(app.buttons["study.skip"].waitForExistence(timeout: 10)); app.buttons["study.skip"].tap()
        XCTAssertTrue(app.staticTexts["study.result.saved"].waitForExistence(timeout: 10))
        XCTAssertEqual(numbers(app.staticTexts["study.result.answered"].label), [0, 1])
        XCTAssertEqual(numbers(app.staticTexts["study.result.skipped"].label), [1])
        XCTAssertEqual(numbers(app.staticTexts["study.result.helped"].label), [0, 0])
        capture(app, "study-range-skip-without-false-assessment")

    }
    func testMicCaptureBackgroundResumeAndPlaybackAreRealAndDurable() {
        // CI grants the simulator's actual OS microphone permission before this
        // separate journey. No app test mode or invented recording is injected.
        let app = XCUIApplication(); application = app; app.launch()
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 20)); app.buttons["home.resume"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "reader.page.ready").firstMatch.waitForExistence(timeout: 120))
        app.buttons["reader.jump"].tap()
        let jump = app.textFields["reader.pageNumber"]
        XCTAssertTrue(jump.waitForExistence(timeout: 5)); jump.tap(); jump.typeText("604"); app.buttons["انتقل"].tap()
        XCTAssertTrue(app.buttons["reader.verse.112:1"].waitForExistence(timeout: 30))
        app.buttons["reader.study"].tap()
        XCTAssertTrue(app.buttons["study.start"].waitForExistence(timeout: 10)); app.buttons["study.start"].tap()
        XCTAssertTrue(app.buttons["study.mic"].waitForExistence(timeout: 10)); app.buttons["study.mic"].tap()
        let status = app.staticTexts["study.status"]
        let captured = NSPredicate { object, _ in
            guard let text = object as? XCUIElement else { return false }
            let label = text.label
            return label.contains("تسجيل محلي") && (5...59).contains(where: { label.contains(String(format: "0:%02d", $0)) })
        }
        let recording = expectation(for: captured, evaluatedWith: status)
        wait(for: [recording], timeout: 20)
        capture(app, "study-actual-microphone-recording")
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertFalse(app.buttons["study.remembered"].isEnabled, "Background must pause and finalize the recording")
        capture(app, "study-background-paused-with-durable-take")
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 20)); app.buttons["home.resume"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "reader.page.ready").firstMatch.waitForExistence(timeout: 120))
        app.buttons["reader.study"].tap()
        XCTAssertTrue(app.buttons["study.resume"].waitForExistence(timeout: 10)); app.buttons["study.resume"].tap()
        XCTAssertTrue(app.buttons["study.recordings"].waitForExistence(timeout: 10)); app.buttons["study.recordings"].tap()
        let play = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "study.recording.play.")).firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 10), "A real decodable recording must survive termination")
        XCTAssertGreaterThanOrEqual(play.frame.height, 44)
        capture(app, "study-recording-restored-and-playable")
        play.tap()
        let playing = expectation(for: NSPredicate(format: "label CONTAINS %@", "إيقاف المقطع"), evaluatedWith: play)
        wait(for: [playing], timeout: 5)
        capture(app, "study-real-recording-playback")
        play.tap(); app.buttons["study.recordings.close"].tap()
        app.buttons["study.finish"].tap()
        XCTAssertTrue(app.staticTexts["study.result.saved"].waitForExistence(timeout: 10))
        XCTAssertEqual(numbers(app.staticTexts["study.result.answered"].label), [0, 15])
        XCTAssertEqual(numbers(app.staticTexts["study.result.helped"].label), [0, 0], "Recording must never invent a Quran assessment or assistance")
        capture(app, "study-recording-finish-without-automatic-grades")
    }
    private func numbers(_ text: String) -> [Int] {
        text.split { $0.wholeNumberValue == nil }.map { $0.reduce(0) { $0 * 10 + ($1.wholeNumberValue ?? 0) } }
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
}
