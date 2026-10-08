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
        let first = app.buttons["reader.verse.112:1"]
        XCTAssertTrue(first.label.contains("مخفي"), "Hidden Quran must not leak through VoiceOver")
        let originalFrame = first.frame
        for id in ["study.revealWord", "study.revealAll", "study.listen", "study.remembered", "study.review", "study.skip", "study.pause", "study.finish"] {
            let action = app.buttons[id]; XCTAssertTrue(action.isHittable, id)
            XCTAssertGreaterThanOrEqual(action.frame.width, 44, id); XCTAssertGreaterThanOrEqual(action.frame.height, 44, id)
            XCTAssertFalse(action.frame.intersects(first.frame), id)
        }
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
        XCTAssertTrue(app.buttons["reader.verse.112:2"].label.contains("مخفي"))
        app.buttons["study.review"].tap()
        capture(app, "study-604-two-answers")
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 20)); app.buttons["home.resume"].tap()
        XCTAssertTrue(page.waitForExistence(timeout: 120)); app.buttons["reader.study"].tap()
        XCTAssertTrue(app.buttons["study.resume"].waitForExistence(timeout: 5)); app.buttons["study.resume"].tap()
        XCTAssertTrue(app.buttons["study.finish"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["reader.verse.112:3"].label.contains("مخفي"))
        XCTAssertFalse(app.buttons["reader.verse.112:1"].label.contains("مخفي"))
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
    }
    private func numbers(_ text: String) -> [Int] {
        text.split { $0.wholeNumberValue == nil }.map { $0.reduce(0) { $0 * 10 + ($1.wholeNumberValue ?? 0) } }
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
}
