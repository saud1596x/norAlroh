import XCTest

final class NoorMushafStudyUITests: XCTestCase {
    private var application: XCUIApplication?
    override func setUpWithError() throws { continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }
    override func tearDownWithError() throws {
        if let run = testRun, run.failureCount > 0, let application { print("STUDY_FAILURE_HIERARCHY\n" + application.debugDescription) }
        XCUIDevice.shared.orientation = .portrait
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
