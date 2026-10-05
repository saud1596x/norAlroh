import XCTest

/// Navigates the shipped UI. No route overrides, generated screen images or seeded results.
final class NoorAllScreensTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testAllScreensWalkthrough() {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 15))
        capture(app, "01-home")
        tap(app.buttons["home.reflection"], in: app)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "reflection.screen").firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["reflection.save"].isEnabled)
        capture(app, "25-reflection")
        back(app)

        app.tabBars.buttons["المصحف"].tap()
        capture(app, "02-surahs")
        tap(app.buttons["surah.1"], in: app)
        let renderedPage = app.descendants(matching: .any).matching(identifier: "reader.page.ready").firstMatch
        let pageRendered = renderedPage.waitForExistence(timeout: 90)
        capture(app, pageRendered ? "03-mushaf" : "03-mushaf-font-unavailable")
        tap(app.buttons["reader.jump"], in: app)
        XCTAssertTrue(app.textFields["reader.pageNumber"].waitForExistence(timeout: 5))
        capture(app, "04-page-navigation")
        app.buttons["إغلاق"].tap()
        tap(app.buttons["reader.flexible"], in: app)
        XCTAssertTrue(app.buttons["ayah.1.1"].waitForExistence(timeout: 5))
        capture(app, "05-flexible-reader")
        app.buttons["ayah.1.1"].tap() // A real bookmark, inspected in the library below.
        back(app); back(app)

        app.tabBars.buttons["الصلاة"].tap()
        capture(app, "06-prayers")
        tap(app.buttons["prayer.city"], in: app)
        capture(app, "07-saudi-cities")
        app.buttons["تم"].tap()
        tap(app.buttons["اختر الصلوات ووقت التنبيه"], in: app)
        capture(app, "08-notifications")
        back(app)

        app.tabBars.buttons["الأذكار"].tap()
        capture(app, "09-adhkar")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("النوم")
        let sleepChapter = app.staticTexts["أذكار النوم"].firstMatch
        XCTAssertTrue(sleepChapter.waitForExistence(timeout: 10), "Sleep adhkar search result must appear before scrolling.")
        tap(sleepChapter, in: app)
        capture(app, "10-dhikr-chapter")
        tap(app.buttons["ابدأ جلسة الذكر"], in: app)
        capture(app, "11-dhikr-session")
        tap(app.buttons["زيادة عداد الذكر"], in: app)

        app.tabBars.buttons["الحفظ"].tap()
        capture(app, "12-hifz")
        tap(app.buttons["hifz.speech"], in: app)
        XCTAssertTrue(app.buttons["speech.prepare"].waitForExistence(timeout: 5))
        capture(app, "32-speech-model-setup")
        back(app)
        tap(app.buttons["hifz.plan"], in: app)
        capture(app, "13-hifz-plan")
        tap(app.buttons["hifz.savePlan"], in: app)
        tap(app.buttons["hifz.test"], in: app)
        capture(app, "14-hifz-test")
        tap(app.buttons["hifz.pause"], in: app)
        XCTAssertFalse(app.buttons["recitation.record"].isEnabled)
        capture(app, "15-hifz-paused")
        tap(app.buttons["hifz.pause"], in: app)
        tap(app.buttons["hifz.reveal"], in: app)
        capture(app, "16-hifz-revealed")
        tap(app.buttons["recitation.record"], in: app, performTap: false)
        capture(app, "17-recitation-controls")
        // Microphone input is not fabricated on a simulator. Real voice validation is separate.
        for _ in 0..<10 {
            if app.staticTexts["hifz.complete"].exists { break }
            tap(app.buttons["hifz.remembered"], in: app)
        }
        XCTAssertTrue(app.staticTexts["hifz.complete"].waitForExistence(timeout: 5))
        app.swipeDown()
        capture(app, "18-hifz-result")
        tap(app.buttons["hifz.resultHistory"], in: app)
        capture(app, "19-hifz-history")
        back(app); back(app)
        tap(app.buttons["hifz.similarities"], in: app)
        capture(app, "20-similarities")
        back(app)

        tap(app.buttons["app.settings"], in: app)
        capture(app, "21-settings")
        tap(app.buttons["settings.library"], in: app)
        capture(app, "22-library")
        back(app)
        tap(app.buttons["settings.privacy"], in: app)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "legal.privacy").firstMatch.waitForExistence(timeout: 5))
        capture(app, "23-privacy")
        back(app)
        tap(app.buttons["settings.terms"], in: app)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "legal.terms").firstMatch.waitForExistence(timeout: 5))
        capture(app, "30-terms")
        back(app)
        tap(app.buttons["settings.support"], in: app)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "legal.support").firstMatch.waitForExistence(timeout: 5))
        capture(app, "31-support")
        back(app)
        tap(app.buttons["settings.sources"], in: app)
        capture(app, "24-sources")
        for (identifier, name) in [("tanzil", "26-tanzil-license"), ("qcf", "27-qcf-license"), ("amiri", "28-amiri-license"), ("adhan", "29-adhan-license"), ("whisperkit", "33-whisperkit-license"), ("whispermodel", "34-whisper-model-license"), ("whispercomponents", "35-whisper-components")] {
            tap(app.buttons["sources.\(identifier)"], in: app)
            XCTAssertTrue(app.staticTexts["license.notice"].waitForExistence(timeout: 5), "The bundled notice must be readable without a network connection.")
            capture(app, name)
            back(app)
        }
        XCTAssertTrue(pageRendered, "The fixed-layout Quran did not render. This recording cannot certify its typography.")
    }

    private func tap(_ element: XCUIElement, in app: XCUIApplication, performTap: Bool = true) {
        for _ in 0..<7 {
            if element.exists && element.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        XCTAssertTrue(element.isHittable)
        if performTap { element.tap() }
    }
    private func back(_ app: XCUIApplication) {
        let button = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5)); button.tap()
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
