import XCTest


final class NoorNavigationTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testNativeHomeSaudiCitySelectionAndAdhkarSearch() throws {
        let app = XCUIApplication(); launchNoorApp(app)
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 15))
        attach(app, name: "الرئيسية")
        selectNoorTab("الصلاة", in: app)
        let city = app.buttons["prayer.city"]
        XCTAssertTrue(city.waitForExistence(timeout: 5)); city.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("جدة")
        let jeddah = app.buttons["city.sa-105343"]
        XCTAssertTrue(jeddah.waitForExistence(timeout: 5)); jeddah.tap()
        XCTAssertTrue(app.staticTexts["جدة"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["اتجاه القبلة"].exists)
        attach(app, name: "مواقيت جدة")
        selectNoorTab("الأذكار", in: app)
        let adhkarSearch = app.searchFields.firstMatch
        XCTAssertTrue(adhkarSearch.waitForExistence(timeout: 5)); adhkarSearch.tap(); adhkarSearch.typeText("النوم")
        let sleep = app.staticTexts["أذكار النوم"].firstMatch
        XCTAssertTrue(sleep.waitForExistence(timeout: 5)); sleep.tap()
        XCTAssertTrue(app.buttons["زيادة عداد الذكر"].waitForExistence(timeout: 5))
        attach(app, name: "جلسة أذكار النوم")
    }
    func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testArabicSurahSearchAndInteractiveTextReader() {
        let app = XCUIApplication(); launchNoorApp(app)
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 15))
        selectNoorTab("المصحف", in: app)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("١١٤")
        let surah = app.buttons["surah.114"]
        XCTAssertTrue(surah.waitForExistence(timeout: 5)); surah.tap()
        let page = app.descendants(matching: .any).matching(identifier: "reader.page.ready").firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 120))
        let verse = app.buttons["reader.verse.114:1"]
        XCTAssertTrue(verse.waitForExistence(timeout: 10)); verse.press(forDuration: 0.6)
        XCTAssertTrue(app.buttons["verse.tafsir"].waitForExistence(timeout: 10))
        attach(app, name: "قراءة سورة الناس")
    }
}


extension XCTestCase {
    func openNoorHomeTools(_ app: XCUIApplication) {
        let tools = app.buttons["home.tools"]
        for _ in 0..<8 {
            if tools.exists && tools.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(tools.exists && tools.isHittable, app.debugDescription)
        if tools.value as? String != "مفتوح" { tools.tap() }
    }

    func openNoorSettingsSection(_ title: String, in app: XCUIApplication) {
        let section = app.buttons[title].firstMatch
        for _ in 0..<8 {
            if section.exists && section.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(section.exists && section.isHittable, app.debugDescription)
        section.tap()
    }

    func launchNoorApp(_ app: XCUIApplication) {
        app.launch()
        let guest = app.buttons["welcome.continue"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guest.exists || app.buttons["home.resume"].exists
        }, object: nil)
        guard XCTWaiter.wait(for: [ready], timeout: 20) == .completed else {
            XCTFail("Neither first-use continuation nor home is available: \(app.debugDescription)")
            return
        }
        if guest.exists { guest.tap() }
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if system.alerts.firstMatch.waitForExistence(timeout: 3) {
            let allow = system.alerts.buttons.matching(NSPredicate(format: "label IN %@", ["Allow", "السماح", "سماح"])).firstMatch
            if allow.exists { allow.tap() }
        }
    }

    func selectNoorTab(_ title: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        // iPadOS exposes the floating top tabs outside XCUIElementTypeTabBar.
        let matches = app.buttons.matching(NSPredicate(format: "label == %@", title))
        guard matches.firstMatch.waitForExistence(timeout: 10),
              let button = matches.allElementsBoundByIndex.first(where: { $0.isHittable }) else {
            XCTFail("Navigation tab is unavailable: \(title)", file: file, line: line); return
        }
        button.tap()
    }
}
