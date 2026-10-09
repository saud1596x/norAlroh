import XCTest

final class NoorReminderUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testIndependentEditorsSaveDaysAndQuietSettingsAcrossRelaunch() {
        let app = XCUIApplication(); launchNoorApp(app)
        openReminders(app)
        for kind in ["dua", "morning", "evening", "salawat", "hifz"] {
            tapVisible(app.buttons["reminders.\(kind)"], app: app)
            let enabled = app.switches["reminder.enabled"]
            XCTAssertTrue(enabled.waitForExistence(timeout: 10))
            // Persist schedules while disabled; no synthetic permission grant or
            // pretend notification delivery is injected into the application.
            if enabled.value as? String == "1" { enabled.tap() }
            let friday = app.switches["reminder.weekday.6"]
            for _ in 0..<5 where !friday.isHittable { app.swipeUp() }
            XCTAssertTrue(friday.isHittable)
            if friday.value as? String == "1" { friday.tap() }
            let quiet = app.switches["reminder.quiet"]
            for _ in 0..<5 where !quiet.isHittable { app.swipeUp() }
            XCTAssertTrue(quiet.isHittable)
            if quiet.value as? String == "0" { quiet.tap() }
            tapVisible(app.buttons["reminder.save"], app: app)
        }
        app.terminate(); launchNoorApp(app); openReminders(app)
        for kind in ["dua", "morning", "evening", "salawat", "hifz"] {
            tapVisible(app.buttons["reminders.\(kind)"], app: app)
            XCTAssertEqual(app.switches["reminder.enabled"].value as? String, "0")
            let friday = app.switches["reminder.weekday.6"]
            for _ in 0..<5 where !friday.isHittable { app.swipeUp() }
            XCTAssertEqual(friday.value as? String, "0")
            let quiet = app.switches["reminder.quiet"]
            for _ in 0..<5 where !quiet.isHittable { app.swipeUp() }
            XCTAssertEqual(quiet.value as? String, "1")
            tapVisible(app.buttons["reminder.save"], app: app)
        }
    }
    private func openReminders(_ app: XCUIApplication) {
        tapVisible(app.buttons["app.settings"], app: app)
        tapVisible(app.buttons["settings.reminders"], app: app)
        XCTAssertTrue(app.buttons["reminders.dua"].waitForExistence(timeout: 10))
    }
    private func tapVisible(_ button: XCUIElement, app: XCUIApplication) {
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        for _ in 0..<6 where !button.isHittable { app.swipeUp() }
        XCTAssertTrue(button.isHittable)
        XCTAssertGreaterThanOrEqual(button.frame.height, 44)
        button.tap()
    }
}
