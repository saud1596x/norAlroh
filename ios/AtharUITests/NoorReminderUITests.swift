import XCTest

/// Owner policy v2 replaces the old custom-frequency editors. These tests do not
/// grant permissions or claim that a simulator delivered a real prayer alarm.
final class NoorReminderUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testFixedPolicyIsExplainedBeforePermissionsWithoutCustomization() {
        let app = XCUIApplication(); launchNoorApp(app); openReminders(app)
        for id in ["notifications.policy.prayers", "notifications.policy.salawat", "notifications.policy.quiet"] {
            XCTAssertTrue(app.descendants(matching: .any)[id].exists, id)
        }
        XCTAssertTrue(app.staticTexts["❀ اللهم صلِّ على نبينا محمد ﷺ ❀"].exists)
        XCTAssertFalse(app.datePickers.firstMatch.exists)
        XCTAssertFalse(app.pickers.firstMatch.exists)
        XCTAssertFalse(app.switches.firstMatch.exists)
        XCTAssertFalse(XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch.exists,
                       "Opening the description must not itself request permission")
        capture(app, "fixed-policy-before-permissions")
    }
    func testPolicyAndIndependentPermissionStatusRemainAvailableAfterRelaunch() {
        let app = XCUIApplication(); launchNoorApp(app); openReminders(app)
        app.terminate(); launchNoorApp(app); openReminders(app)
        for id in ["notifications.status.prayers", "notifications.status.messages", "notifications.systemSettings"] {
            let element = app.descendants(matching: .any)[id]
            for _ in 0..<6 {
                if element.exists && element.isHittable && app.frame.contains(element.frame) { break }
                app.swipeUp()
            }
            XCTAssertTrue(element.exists && element.isHittable, id)
        }
        XCTAssertFalse(app.buttons["reminders.morning"].exists)
        XCTAssertFalse(app.buttons["reminder.save"].exists)
        capture(app, "fixed-policy-independent-status")
    }
    private func openReminders(_ app: XCUIApplication) {
        tapVisible(app.buttons["app.settings"], app: app)
        tapVisible(app.buttons["settings.reminders"], app: app)
        XCTAssertTrue(app.navigationBars["التنبيهات"].waitForExistence(timeout: 10))
    }
    private func tapVisible(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<8 {
            if element.exists && element.isHittable && app.frame.contains(element.frame) { break }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable && app.frame.contains(element.frame))
        XCTAssertGreaterThanOrEqual(element.frame.height, 44 - 0.000001)
        element.tap()
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
