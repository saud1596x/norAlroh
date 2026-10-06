import XCTest

final class NoorLaunchTests: XCTestCase {
    func testEntranceCanBeSkippedAndDoesNotRepeatDuringNavigation() {
        let app = XCUIApplication(); app.launch()
        let skip = app.buttons["launch.skip"]
        if skip.waitForExistence(timeout: 3) {
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "00-intro"
            shot.lifetime = .keepAlways; add(shot); skip.tap()
        }
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 15))
        selectNoorTab("الصلاة", in: app)
        selectNoorTab("اليوم", in: app)
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["launch.skip"].exists)
    }
}
