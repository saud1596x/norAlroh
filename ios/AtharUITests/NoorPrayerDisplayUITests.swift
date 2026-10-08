import XCTest

final class NoorPrayerDisplayUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor func testPrayerDatesClocksAndCityPersistAcrossRestart() {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting"]; launchNoorApp(app)
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 30))
        selectNoorTab("الصلاة", in: app)
        assertDatesAndClock(app)
        capture(app, "prayer-dates-and-clock")
        app.buttons["prayer.city"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("جدة")
        let city = app.buttons["city.sa-105343"]
        XCTAssertTrue(city.waitForExistence(timeout: 10)); city.tap()
        XCTAssertEqual(app.buttons["prayer.city"].value as? String, "جدة")
        assertDatesAndClock(app)
        let fajr = app.staticTexts["prayer.time.fajr"]
        XCTAssertTrue(fajr.waitForExistence(timeout: 10))
        assertClock(fajr.label)
        capture(app, "prayer-city-changed")
        app.terminate(); launchNoorApp(app)
        selectNoorTab("الصلاة", in: app)
        XCTAssertTrue(app.buttons["prayer.city"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["prayer.city"].value as? String, "جدة")
        assertDatesAndClock(app)
        capture(app, "prayer-city-restored")
    }
    @MainActor private func assertDatesAndClock(_ app: XCUIApplication) {
        for id in ["prayer.gregorian", "prayer.hijri"] {
            let date = app.staticTexts[id]
            XCTAssertTrue(date.waitForExistence(timeout: 10))
            XCTAssertFalse(date.label.isEmpty)
            XCTAssertTrue(date.label.allSatisfy { $0.wholeNumberValue == nil || "0123456789".contains($0) })
        }
        let next = app.staticTexts["prayer.nextTime"]
        XCTAssertTrue(next.waitForExistence(timeout: 10)); assertClock(next.label)
    }
    private func assertClock(_ value: String) {
        XCTAssertNotNil(value.range(of: #"^(?:[01][0-9]|2[0-3]):[0-5][0-9]$"#, options: .regularExpression))
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
