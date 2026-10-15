import XCTest
final class NoorKhatmahUITests: XCTestCase {
    @MainActor func testHomeContinuesOneTwentyPageWardAndKeepsStopInsideSameAction() {
        let app = XCUIApplication(); launchNoorApp(app)
        tapVisible(app, app.buttons["home.startKhatmah"])
        tapVisible(app, app.buttons["khatmah.setup"])
        app.swipeUp(); app.swipeUp()
        tapVisible(app, app.buttons["khatmah.preview"])
        app.swipeUp(); app.swipeUp(); app.swipeUp()
        tapVisible(app, app.buttons["khatmah.adopt"])
        XCTAssertTrue(app.buttons["khatmah.read"].waitForExistence(timeout: 10))
        app.buttons["إغلاق"].tap()
        app.swipeDown(); app.swipeDown()
        tapVisible(app, app.buttons["home.continueKhatmah"])
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "reader.page.ready").firstMatch.waitForExistence(timeout: 120))
        XCTAssertTrue(app.staticTexts["reader.ward.range"].label.contains("٢٠"))
        app.buttons["reader.jump"].tap()
        let field = app.textFields["reader.pageNumber"]
        XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap(); field.typeText("20")
        app.buttons["انتقل"].tap()
        let end = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == false"), object: app.buttons["reader.next"])
        XCTAssertEqual(XCTWaiter.wait(for: [end], timeout: 20), .completed)
        capture(app, "twenty-page-ward-boundary")
        app.buttons["إغلاق المصحف"].tap()
        tapVisible(app, app.buttons["home.continueKhatmah"])
        XCTAssertTrue(app.buttons["reader.next"].waitForExistence(timeout: 120))
        let resumed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == false"), object: app.buttons["reader.next"])
        XCTAssertEqual(XCTWaiter.wait(for: [resumed], timeout: 30), .completed, "The same action restores page20 without creating a second ward")
        XCTAssertFalse(app.buttons["khatmah.resumeStop"].exists)
        let confirm = app.buttons["reader.ward.confirm"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: confirm)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 30), .completed)
        confirm.tap()
        XCTAssertTrue(app.alerts["أتممت ورد اليوم"].waitForExistence(timeout: 10))
        app.alerts.buttons["العودة للرئيسية"].tap()
        XCTAssertTrue(app.staticTexts["أتممت ورد اليوم"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["home.continueKhatmah"].exists)
        capture(app, "home-ward-completed")
    }
    @MainActor func testKhatmahControlInMushafOpensRealPlanWithoutHiddenHomeTools() {
        let app = XCUIApplication(); launchNoorApp(app)
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 20))
        app.buttons["home.resume"].tap()
        let entry = app.buttons["reader.khatmah"]
        XCTAssertTrue(entry.waitForExistence(timeout: 120))
        XCTAssertTrue(entry.isHittable)
        XCTAssertGreaterThanOrEqual(entry.frame.height, 44)
        entry.tap()
        let setup = app.navigationBars["إعداد الختمة"]
        let journey = app.staticTexts["رحلة الختمة"].firstMatch
        let opened = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in setup.exists || journey.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [opened], timeout: 10), .completed)
        if setup.exists {
            XCTAssertTrue(app.steppers["khatmah.daily"].exists)
            XCTAssertTrue(app.buttons["khatmah.preview"].exists)
        } else {
            XCTAssertTrue(app.buttons["khatmah.read"].exists || app.staticTexts["khatmah.completedPages"].exists)
        }
        capture(app, "mushaf-direct-khatmah-control")
    }
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor func testPreviewConfirmationPauseAndRelaunch() throws {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting"]; launchNoorApp(app)
        openNoorHomeTools(app)
        XCTAssertTrue(app.buttons["home.khatmah"].waitForExistence(timeout: 30))
        openJourney(app)
        XCTAssertTrue(app.buttons["khatmah.setup"].waitForExistence(timeout: 10)); tapVisible(app, app.buttons["khatmah.setup"])
        app.swipeUp(); app.swipeUp()
        XCTAssertTrue(app.buttons["khatmah.preview"].waitForExistence(timeout: 10)); app.buttons["khatmah.preview"].tap()
        capture(app, "khatmah-plan-preview")
        app.swipeUp(); app.swipeUp(); app.swipeUp()
        XCTAssertTrue(app.buttons["khatmah.adopt"].waitForExistence(timeout: 10)); app.buttons["khatmah.adopt"].tap()
        XCTAssertTrue(app.buttons["khatmah.read"].waitForExistence(timeout: 10))
        assertProgress(app, pages: 0)
        capture(app, "khatmah-active-plan")
        tapVisible(app, app.buttons["khatmah.read"])
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "reader.page.ready").firstMatch.waitForExistence(timeout: 120))
        XCTAssertTrue(app.buttons["reader.jump"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["reader.previous"].isEnabled)
        capture(app, "khatmah-reader-entry")
        app.buttons["إغلاق المصحف"].tap()
        XCTAssertTrue(app.buttons["khatmah.read"].waitForExistence(timeout: 10))
        assertProgress(app, pages: 0)
        tapVisible(app, app.buttons["khatmah.confirm"])
        XCTAssertTrue(app.buttons["khatmah.saveReading"].waitForExistence(timeout: 10)); app.buttons["khatmah.saveReading"].tap()
        assertProgress(app, pages: 20)
        capture(app, "khatmah-confirmed-progress")
        tapVisible(app, app.buttons["khatmah.pause"])
        XCTAssertTrue(app.staticTexts["الرحلة متوقفة مؤقتًا"].waitForExistence(timeout: 10))
        tapVisible(app, app.buttons["khatmah.pause"])
        app.terminate(); launchNoorApp(app)
        openNoorHomeTools(app)
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
    @MainActor private func tapVisible(_ app: XCUIApplication, _ button: XCUIElement) {
        for _ in 0..<6 where !button.isHittable { app.swipeUp() }
        XCTAssertTrue(button.waitForExistence(timeout: 10)); XCTAssertTrue(button.isHittable)
        XCTAssertGreaterThanOrEqual(button.frame.height, 44)
        button.tap()
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
