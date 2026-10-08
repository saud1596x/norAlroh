import XCTest

final class NoorLaunchTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testFirstWelcomeGuestContinuationPersistsAfterRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["-NoorAcceptanceShowWelcome"]
        app.launch()
        let guest = app.buttons["welcome.continue"]
        XCTAssertTrue(guest.waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["welcome.title"].exists)
        XCTAssertTrue(guest.isHittable)
        capture(app, name: "welcome-first-use")
        guest.tap()
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 15))
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["welcome.continue"].exists)
        capture(app, name: "welcome-choice-after-relaunch")
    }

    func testEntranceCanBeSkippedAndDoesNotRepeatDuringNavigation() {
        let app = XCUIApplication(); app.launch()
        let skip = app.buttons["launch.skip"]
        if skip.waitForExistence(timeout: 3) {
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "00-intro"
            shot.lifetime = .keepAlways; add(shot); skip.tap()
        }
        let guest = app.buttons["welcome.continue"]
        if guest.waitForExistence(timeout: 4) { guest.tap() }
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 15))
        selectNoorTab("الصلاة", in: app)
        selectNoorTab("اليوم", in: app)
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["launch.skip"].exists)
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
