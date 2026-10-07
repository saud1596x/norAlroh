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

        selectNoorTab("المصحف", in: app)
        capture(app, "02-surahs")
        tap(app.buttons["surah.1"], in: app)
        let renderedPage = app.descendants(matching: .any).matching(identifier: "reader.page.ready").firstMatch
        let pageRendered = renderedPage.waitForExistence(timeout: 90)
        capture(app, pageRendered ? "03-mushaf" : "03-mushaf-font-unavailable")
        tap(app.buttons["reader.jump"], in: app)
        XCTAssertTrue(app.textFields["reader.pageNumber"].waitForExistence(timeout: 5))
        capture(app, "04-page-navigation")
        app.buttons["إغلاق"].tap()
        let verse = app.buttons["reader.verse.1:1"]
        XCTAssertTrue(verse.waitForExistence(timeout: 10)); verse.tap()
        XCTAssertTrue(app.buttons["verse.tafsir"].waitForExistence(timeout: 10))
        capture(app, "05-interactive-verse-tools")
        let bookmark = app.buttons["verse.bookmark"]
        XCTAssertTrue(bookmark.waitForExistence(timeout: 10))
        if bookmark.label == "إضافة علامة مرجعية" { bookmark.tap() }
        XCTAssertEqual(bookmark.label, "إزالة العلامة المرجعية")
        app.buttons["verse.tools.close"].tap()
        app.buttons["إغلاق المصحف"].tap()
        XCTAssertTrue(app.buttons["surah.1"].waitForExistence(timeout: 10))

        selectNoorTab("الصلاة", in: app)
        capture(app, "06-prayers")
        tap(app.buttons["prayer.city"], in: app)
        capture(app, "07-saudi-cities")
        app.buttons["تم"].tap()
        tap(app.buttons["اختر الصلوات ووقت التنبيه"], in: app)
        capture(app, "08-notifications")
        back(app)

        selectNoorTab("الأذكار", in: app)
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

        selectNoorTab("الحفظ", in: app)
        capture(app, "12-hifz")
        tap(app.buttons["hifz.speech"], in: app)
        XCTAssertTrue(app.buttons["speech.prepare"].waitForExistence(timeout: 5))
        capture(app, "32-speech-model-setup")
        back(app)
        tap(app.buttons["hifz.plan"], in: app)
        capture(app, "13-hifz-plan")
        tap(app.buttons["hifz.savePlan"], in: app)
        tap(app.buttons["hifz.practice"], in: app)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "reader.page.ready").firstMatch.waitForExistence(timeout: 90))
        capture(app, "37-practice-mushaf-hidden")
        tap(app.buttons["hifz.revealPart"], in: app)
        capture(app, "38-practice-mushaf-hint")
        tap(app.buttons["hifz.revealAll"], in: app)
        capture(app, "39-practice-mushaf-revealed")
        back(app)
        tap(app.buttons["hifz.practice"], in: app)
        XCTAssertTrue(app.buttons["hifz.revealAll"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["hifz.revealAll"].label, "إخفاء النص", "Practice restores reveal state after leaving the screen")
        back(app)
        tap(app.buttons["hifz.test"], in: app)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "reader.page.ready").firstMatch.waitForExistence(timeout: 90))
        capture(app, "14-hifz-test")
        tap(app.buttons["hifz.pause"], in: app)
        tap(app.buttons["hifz.recording"], in: app)
        XCTAssertFalse(app.buttons["recitation.record"].isEnabled)
        tap(app.buttons["hifz.recording.close"], in: app)
        capture(app, "15-hifz-paused")
        tap(app.buttons["hifz.pause"], in: app)
        tap(app.buttons["hifz.reveal"], in: app)
        capture(app, "16-hifz-revealed")
        tap(app.buttons["hifz.recording"], in: app)
        tap(app.buttons["recitation.record"], in: app, performTap: false)
        capture(app, "17-recitation-controls")
        tap(app.buttons["hifz.recording.close"], in: app)
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
        tap(app.buttons["hifz.insights"], in: app)
        capture(app, "36-mastery-map")
        back(app)
        tap(app.buttons["hifz.similarities"], in: app)
        capture(app, "20-similarities")
        back(app)

        tap(app.buttons["app.settings"], in: app)
        capture(app, "21-settings")
        tap(app.buttons["settings.downloads"], in: app)
        XCTAssertTrue(app.buttons["downloads.range"].waitForExistence(timeout: 5))
        capture(app, "40-downloads")
        back(app)
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
        XCTAssertTrue(pageRendered, "The fixed-layout Quran did not render. This recording cannot certify its typography.")
    }

    func testPrayerSettingsExposeIndependentSalawatAndNoCalculationPicker() {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 15))
        selectNoorTab("الصلاة", in: app)
        XCTAssertFalse(app.staticTexts["طريقة الحساب"].exists)
        capture(app, "41-automatic-prayers")
        tap(app.buttons["اختر الصلوات ووقت التنبيه"], in: app)
        XCTAssertTrue(app.navigationBars["تنبيهات الصلاة"].waitForExistence(timeout: 5))
        capture(app, "42-prayer-alert-settings")
        tap(app.switches["تذكير هادئ"], in: app, performTap: false)
        capture(app, "43-salawat-settings")
        XCTAssertFalse(app.staticTexts["طريقة الحساب"].exists)
    }

    private func tap(_ element: XCUIElement, in app: XCUIApplication, performTap: Bool = true) {
        // A lazy List may remove an off-screen row from its snapshot. A
        // `containing(target)` container then disappears during scrolling even
        // though the List itself is still present (CI144). Resolve the current
        // scrolling surface independently of the row on every gesture.
        func scrollingSurface() -> XCUIElement {
            if app.collectionViews.firstMatch.exists { return app.collectionViews.firstMatch }
            if app.scrollViews.firstMatch.exists { return app.scrollViews.firstMatch }
            return app
        }
        func scroll(up: Bool) {
            // SwiftUI may replace its List between an exists check and a swipe
            // (CI151). Gesture against the stable app, within the observed
            // viewport, rather than resolving that transient List a second time.
            let surface = scrollingSurface()
            let visible = surface.frame.intersection(app.frame)
            guard !visible.isEmpty, visible.width > 0, visible.height > 0 else { return }
            let low = CGPoint(x: visible.midX, y: visible.minY + visible.height * 0.75)
            let high = CGPoint(x: visible.midX, y: visible.minY + visible.height * 0.25)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: up ? low.x : high.x, dy: up ? low.y : high.y))
            let end = origin.withOffset(CGVector(dx: up ? high.x : low.x, dy: up ? high.y : low.y))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        func ready() -> Bool {
            guard element.exists else { return false }
            let frame = element.frame
            // Querying isHittable for a zero/off-screen activation frame can
            // fail XCTest itself, rather than return false. Check geometry first.
            guard frame.width > 0, frame.height > 0,
                  frame.minX.isFinite, frame.minY.isFinite,
                  frame.maxX.isFinite, frame.maxY.isFinite,
                  app.frame.contains(frame) else { return false }
            let identifier = element.identifier
            let isNavigationControl = !identifier.isEmpty &&
                app.navigationBars.descendants(matching: .any).matching(identifier: identifier).firstMatch.exists
            let container = scrollingSurface()
            if !isNavigationControl && container != app && container.frame.intersects(frame) {
                // Use the actual scroll/window intersection. A fixed 60pt
                // window inset rejected the fully visible last license row
                // in CI150 (row bottom 902, window bottom 956, inset 896).
                let viewport = container.frame.intersection(app.frame)
                guard !viewport.isEmpty, viewport.contains(frame) else { return false }
                // Visible navigation/tab chrome is a real obstruction, unlike
                // an assumed safe-area margin. Ignore bars behind a sheet.
                for bar in app.navigationBars.allElementsBoundByIndex + app.tabBars.allElementsBoundByIndex {
                    let bounds = bar.frame
                    if bounds.width > 0, bounds.height > 0, app.frame.contains(bounds),
                       bounds.intersects(frame), bar.isHittable { return false }
                }
            }
            return element.isHittable
        }
        // Returning to a long List can restore its scroll position. Search both
        // directions instead of assuming every destination starts at its top.
        if !ready() {
            for _ in 0..<7 {
                if ready() { break }
                scroll(up: false)
            }
        }
        for _ in 0..<14 {
            if ready() { break }
            scroll(up: true)
        }
        if !ready() {
            let description = app.debugDescription
            let hierarchy = XCTAttachment(string: description)
            hierarchy.name = "failed-navigation-hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
            print("NAVIGATION_TARGET_FAILURE \(element.identifier) row=\(element.frame) viewport=\(scrollingSurface().frame.intersection(app.frame))\n\(description)")
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        XCTAssertTrue(ready(), "The entire row must be visible before tapping or capturing it.")
        if performTap { element.tap() }
    }
    private func back(_ app: XCUIApplication) {
        let button = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5)); button.tap()
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
