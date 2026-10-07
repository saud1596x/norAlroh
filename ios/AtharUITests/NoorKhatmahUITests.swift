import XCTest
final class NoorKhatmahUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor func testPreviewConfirmationPauseAndRelaunch() throws {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting"]; app.launch()
        XCTAssertTrue(app.buttons["home.khatmah"].waitForExistence(timeout: 30))
        openJourney(app)
        XCTAssertTrue(app.buttons["khatmah.setup"].waitForExistence(timeout: 10)); app.buttons["khatmah.setup"].tap()
        app.swipeUp(); app.swipeUp()
        XCTAssertTrue(app.buttons["khatmah.preview"].waitForExistence(timeout: 10)); app.buttons["khatmah.preview"].tap()
        capture(app, "khatmah-plan-preview")
        app.swipeUp(); app.swipeUp(); app.swipeUp()
        XCTAssertTrue(app.buttons["khatmah.adopt"].waitForExistence(timeout: 10)); app.buttons["khatmah.adopt"].tap()
        XCTAssertTrue(app.buttons["khatmah.read"].waitForExistence(timeout: 10))
        assertProgress(app, pages: 0)
        capture(app, "khatmah-active-plan")
        app.buttons["khatmah.read"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "reader.page.ready").firstMatch.waitForExistence(timeout: 120))
        XCTAssertTrue(app.buttons["reader.jump"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["reader.previous"].isEnabled)
        capture(app, "khatmah-reader-entry")
        app.buttons["إغلاق المصحف"].tap()
        XCTAssertTrue(app.buttons["khatmah.read"].waitForExistence(timeout: 10))
        assertProgress(app, pages: 0)
        app.buttons["khatmah.confirm"].tap()
        XCTAssertTrue(app.buttons["khatmah.saveReading"].waitForExistence(timeout: 10)); app.buttons["khatmah.saveReading"].tap()
        assertProgress(app, pages: 20)
        capture(app, "khatmah-confirmed-progress")
        app.buttons["khatmah.pause"].tap()
        XCTAssertTrue(app.staticTexts["الرحلة متوقفة مؤقتًا"].waitForExistence(timeout: 10))
        app.buttons["khatmah.pause"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["home.khatmah"].waitForExistence(timeout: 30)); openJourney(app)
        assertProgress(app, pages: 20)
        capture(app, "khatmah-progress-restored")
        app.buttons["إغلاق"].tap()
        let journey = app.buttons["home.myJourney"]
        // Home's lazy grid creates this link only when it approaches the
        // viewport. Do not wait for an offscreen, uncreated element first.
        for _ in 0..<6 {
            if journey.exists && journey.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(journey.waitForExistence(timeout: 10))
        XCTAssertTrue(journey.isHittable)
        journey.tap()
        XCTAssertTrue(app.staticTexts["journey.summary"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["journey.summary"].label.contains("20 صفحات جديدة"))
        let session = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "journey.session.")).firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 10))
        for _ in 0..<4 where !session.isHittable { app.swipeUp() }
        XCTAssertTrue(session.isHittable)
        capture(app, "my-journey-confirmed-timeline")
        session.tap()
        XCTAssertTrue(app.navigationBars["تفاصيل القراءة"].waitForExistence(timeout: 10))
        capture(app, "my-journey-session-detail")
        app.buttons["إغلاق"].tap()
        let previousMonth = app.buttons["journey.previousMonth"]
        for _ in 0..<4 where !previousMonth.isHittable { app.swipeDown() }
        XCTAssertTrue(previousMonth.isHittable)
        previousMonth.tap()
        app.buttons["journey.day.1"].tap()
        XCTAssertTrue(app.staticTexts["لا توجد قراءة مؤكدة في هذا اليوم."].waitForExistence(timeout: 10))
        capture(app, "my-journey-calendar-empty-day")
    }
    @MainActor private func openJourney(_ app: XCUIApplication) {
        let button = app.buttons["home.khatmah"]
        // Scroll only when needed; a full-screen swipe can move this already
        // visible card out of view on a larger iPhone.
        if !button.isHittable { app.swipeUp() }
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in button.isHittable }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 10), .completed)
        button.tap()
        XCTAssertTrue(app.staticTexts["رحلة الختمة"].waitForExistence(timeout: 10))
    }
    @MainActor private func assertProgress(_ app: XCUIApplication, pages: Int, file: StaticString = #filePath, line: UInt = #line) {
        let count = app.staticTexts["khatmah.completedPages"]
        XCTAssertTrue(count.waitForExistence(timeout: 10), file: file, line: line)
        XCTAssertEqual(count.label, "\(pages) من 604 صفحة", file: file, line: line)
        XCTAssertEqual(count.value as? String, String(pages), file: file, line: line)
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
