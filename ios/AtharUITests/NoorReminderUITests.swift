import XCTest

final class NoorReminderUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws {
        if let testRun, testRun.failureCount > 0 {
            print("REMINDER_FAILURE_SCREEN\n" + XCUIApplication().debugDescription)
        }
    }
    func testIndependentEditorsSaveDaysAndQuietSettingsAcrossRelaunch() {
        let app = XCUIApplication(); launchNoorApp(app)
        openReminders(app)
        for kind in ["dua", "morning", "evening", "salawat", "hifz"] {
            tapVisible(app.buttons["reminders.\(kind)"], app: app)
            let enabled = app.switches["reminder.enabled"]
            XCTAssertTrue(enabled.waitForExistence(timeout: 10))
            // Persist schedules while disabled; no synthetic permission grant or
            // pretend notification delivery is injected into the application.
            setSwitch(enabled, to: "0", app: app)
            let friday = app.switches["reminder.weekday.6"]
            setSwitch(friday, to: "0", app: app)
            let quiet = app.switches["reminder.quiet"]
            setSwitch(quiet, to: "1", app: app)
            saveAndReturnToHub(app)
        }
        app.terminate(); launchNoorApp(app); openReminders(app)
        for kind in ["dua", "morning", "evening", "salawat", "hifz"] {
            tapVisible(app.buttons["reminders.\(kind)"], app: app)
            XCTAssertEqual(app.switches["reminder.enabled"].value as? String, "0")
            let friday = app.switches["reminder.weekday.6"]
            requireVisible(friday, app: app)
            XCTAssertEqual(friday.value as? String, "0")
            let quiet = app.switches["reminder.quiet"]
            requireVisible(quiet, app: app)
            XCTAssertEqual(quiet.value as? String, "1")
            saveAndReturnToHub(app)
        }
    }
    private func openReminders(_ app: XCUIApplication) {
        tapVisible(app.buttons["app.settings"], app: app)
        tapVisible(app.buttons["settings.reminders"], app: app)
        XCTAssertTrue(app.buttons["reminders.dua"].waitForExistence(timeout: 10))
    }
    private func requireVisible(_ element: XCUIElement, app: XCUIApplication) {
        // List may not create an off-screen row until the user scrolls.
        for _ in 0..<8 {
            if element.exists && element.isHittable { break }
            app.swipeUp()
        }
        if !(element.exists && element.isHittable) {
            // Returning from an editor may preserve a List offset below the
            // desired row. Search back toward the top, rather than only down.
            for _ in 0..<8 {
                if element.exists && element.isHittable { break }
                app.swipeDown()
            }
        }
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        XCTAssertTrue(element.isHittable)
    }
    private func setSwitch(_ element: XCUIElement, to expected: String, app: XCUIApplication) {
        requireVisible(element, app: app)
        if element.value as? String != expected {
            // SwiftUI exposes the labelled row as a Switch and nests the
            // actual UIKit control. Native Run4 confirmed that row-centre taps
            // do not toggle it; use the observed child control directly.
            let control = element.switches.firstMatch
            XCTAssertTrue(control.exists)
            XCTAssertTrue(control.isHittable)
            control.tap()
            let toggled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                element.value as? String == expected
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [toggled], timeout: 3), .completed)
        }
        // Verify the real UI change before Save, as well as after relaunch.
        XCTAssertEqual(element.value as? String, expected)
    }
    private func saveAndReturnToHub(_ app: XCUIApplication) {
        tapVisible(app.buttons["reminder.save"], app: app)
        // Do not swipe the next List during the asynchronous Save/dismissal.
        // A missing return now fails here with the actual failure-screen tree.
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !app.buttons["reminder.save"].exists && app.navigationBars["تذكيراتي"].exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 10), .completed)
    }
    private func tapVisible(_ button: XCUIElement, app: XCUIApplication) {
        requireVisible(button, app: app)
        // XCTest can report 44 points as 43.999999999999986 after
        // coordinate conversion; allow floating-point error only.
        XCTAssertGreaterThanOrEqual(button.frame.height, 44 - 0.000001)
        button.tap()
    }
}
