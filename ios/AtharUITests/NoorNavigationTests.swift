import XCTest

final class NoorNavigationTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testNativeHomeSaudiCitySelectionAndAdhkarSearch() throws {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 15))
        attach(app, name: "الرئيسية")
        app.tabBars.buttons["الصلاة"].tap()
        let city = app.buttons["prayer.city"]
        XCTAssertTrue(city.waitForExistence(timeout: 5)); city.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("جدة")
        let jeddah = app.buttons["city.sa-105343"]
        XCTAssertTrue(jeddah.waitForExistence(timeout: 5)); jeddah.tap()
        XCTAssertTrue(app.staticTexts["جدة"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["اتجاه القبلة"].exists)
        attach(app, name: "مواقيت جدة")
        app.tabBars.buttons["الأذكار"].tap()
        let adhkarSearch = app.searchFields.firstMatch
        XCTAssertTrue(adhkarSearch.waitForExistence(timeout: 5)); adhkarSearch.tap(); adhkarSearch.typeText("النوم")
        let sleep = app.staticTexts["أذكار النوم"].firstMatch
        XCTAssertTrue(sleep.waitForExistence(timeout: 5)); sleep.tap()
        let start = app.buttons["ابدأ جلسة الذكر"]
        XCTAssertTrue(start.waitForExistence(timeout: 5)); start.tap()
        XCTAssertTrue(app.buttons["زيادة عداد الذكر"].waitForExistence(timeout: 5))
        attach(app, name: "جلسة أذكار النوم")
    }
    func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testArabicSurahSearchAndFlexibleReader() {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 15))
        app.tabBars.buttons["المصحف"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("١١٤")
        let surah = app.buttons["surah.114"]
        XCTAssertTrue(surah.waitForExistence(timeout: 5)); surah.tap()
        let flexible = app.buttons["reader.flexible"]
        XCTAssertTrue(flexible.waitForExistence(timeout: 5)); flexible.tap()
        XCTAssertTrue(app.buttons["ayah.114.1"].waitForExistence(timeout: 5))
        attach(app, name: "قراءة سورة الناس")
    }
}
