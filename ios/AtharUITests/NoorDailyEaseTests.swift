import XCTest

final class NoorDailyEaseTests: XCTestCase {
    func testSeparateMorningAndEveningOpenReadableSessions() {
        continueAfterFailure = false
        let app = XCUIApplication(); launchNoorApp(app)
        selectNoorTab("الأذكار", in: app)
        let morning = app.buttons["adhkar.morning"]
        XCTAssertTrue(morning.waitForExistence(timeout: 15))
        morning.tap()
        XCTAssertTrue(app.navigationBars["أذكار الصباح"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["dhikr.quran.2.255"].waitForExistence(timeout: 10))
        attach(app, "morning-reading")
        app.navigationBars.buttons.firstMatch.tap()
        let evening = app.buttons["adhkar.evening"]
        XCTAssertTrue(evening.waitForExistence(timeout: 10)); evening.tap()
        XCTAssertTrue(app.navigationBars["أذكار المساء"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["dhikr.quran.2.255"].waitForExistence(timeout: 10))
        attach(app, "evening-reading")
    }
    private func attach(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name
        image.lifetime = .keepAlways; add(image)
    }
}
