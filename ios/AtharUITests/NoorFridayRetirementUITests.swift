import XCTest

final class NoorFridayRetirementUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testSettingsRetiredWhileKahfAndSalawatRemainUsableAfterRelaunch() {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting"]; app.launch()
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 30))
        inspectSettings(app)
        selectNoorTab("المصحف", in: app)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("الكهف")
        let kahf = app.buttons["surah.18"]
        XCTAssertTrue(kahf.waitForExistence(timeout: 10)); kahf.tap()
        let page = app.descendants(matching: .any).matching(identifier: "reader.page.ready").firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 120))
        XCTAssertTrue(app.buttons["reader.verse.18:1"].waitForExistence(timeout: 15))
        capture(app, "kahf-preserved-after-friday-settings-retirement")
        app.buttons["إغلاق المصحف"].tap()
        selectNoorTab("الأذكار", in: app)
        let dhikrSearch = app.searchFields.firstMatch
        XCTAssertTrue(dhikrSearch.waitForExistence(timeout: 10)); dhikrSearch.tap(); dhikrSearch.typeText("فضل الصلاة على النبي")
        let salawat = app.buttons["adhkar.group.hisn-107"]
        XCTAssertTrue(salawat.waitForExistence(timeout: 10)); salawat.tap()
        let start = app.buttons["ابدأ جلسة الذكر"]
        for _ in 0..<4 {
            if start.exists && start.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(start.exists && start.isHittable); start.tap()
        XCTAssertTrue(app.buttons["زيادة عداد الذكر"].waitForExistence(timeout: 10))
        capture(app, "salawat-content-and-counter-preserved")
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 30))
        inspectSettings(app)
    }
    private func inspectSettings(_ app: XCUIApplication) {
        let settings = app.buttons["app.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10)); settings.tap()
        XCTAssertTrue(app.navigationBars["الإعدادات"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["إعدادات يوم الجمعة"].exists)
        capture(app, "account-settings-without-friday-options")
        let about = app.staticTexts["عن نور الروح"].firstMatch
        for _ in 0..<6 {
            if about.exists && about.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(about.exists && about.isHittable)
        let capability = app.staticTexts["settings.studyCapability"]
        XCTAssertTrue(capability.waitForExistence(timeout: 5))
        XCTAssertTrue(capability.label.contains("بتقييم ذاتي"))
        XCTAssertTrue(capability.label.contains("لا يوجد تصحيح صوتي آلي مفعّل"))
        XCTAssertFalse(capability.label.contains("تقارن الكلمات"))
        XCTAssertFalse(app.buttons["إعدادات يوم الجمعة"].exists)
        XCTAssertFalse(app.buttons["تفعيل تذكيرات الجمعة"].exists)
        app.buttons["تم"].tap()
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
