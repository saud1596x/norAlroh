import XCTest
final class NoorKhatmahUITests: XCTestCase {
    @MainActor func testPreviewConfirmationPauseAndRelaunch() throws {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting"]; app.launch()
        XCTAssertTrue(app.buttons["home.khatmah"].waitForExistence(timeout: 30))
        app.swipeUp(); app.buttons["home.khatmah"].tap()
        XCTAssertTrue(app.buttons["khatmah.setup"].waitForExistence(timeout: 10)); app.buttons["khatmah.setup"].tap()
        app.swipeUp(); app.swipeUp()
        XCTAssertTrue(app.buttons["khatmah.preview"].waitForExistence(timeout: 10)); app.buttons["khatmah.preview"].tap()
        capture(app, "khatmah-plan-preview")
        app.swipeUp(); app.swipeUp(); app.swipeUp()
        XCTAssertTrue(app.buttons["khatmah.adopt"].waitForExistence(timeout: 10)); app.buttons["khatmah.adopt"].tap()
        XCTAssertTrue(app.buttons["khatmah.read"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["0 من 604 صفحة"].exists)
        capture(app, "khatmah-active-plan")
        app.buttons["khatmah.confirm"].tap()
        XCTAssertTrue(app.buttons["khatmah.saveReading"].waitForExistence(timeout: 10)); app.buttons["khatmah.saveReading"].tap()
        XCTAssertTrue(app.staticTexts["20 من 604 صفحة"].waitForExistence(timeout: 10))
        capture(app, "khatmah-confirmed-progress")
        app.buttons["khatmah.pause"].tap()
        XCTAssertTrue(app.staticTexts["الرحلة متوقفة مؤقتًا"].waitForExistence(timeout: 10))
        app.buttons["khatmah.pause"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["home.khatmah"].waitForExistence(timeout: 30)); app.buttons["home.khatmah"].tap()
        XCTAssertTrue(app.staticTexts["20 من 604 صفحة"].waitForExistence(timeout: 10))
        capture(app, "khatmah-progress-restored")
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
