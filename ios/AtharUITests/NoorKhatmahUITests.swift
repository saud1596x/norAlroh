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
        assertProgress(app, pages: 0)
        capture(app, "khatmah-active-plan")
        app.buttons["khatmah.read"].tap()
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
        XCTAssertTrue(app.buttons["home.khatmah"].waitForExistence(timeout: 30)); app.buttons["home.khatmah"].tap()
        assertProgress(app, pages: 20)
        capture(app, "khatmah-progress-restored")
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
