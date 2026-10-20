import XCTest

/// Actual UI journey: no injected Quran, words, navigation or microphone audio.
/// Driver timings are reported as driver timings, never physical-phone ASR p95.
final class NoorMushafClosureUITests: XCTestCase {
    private var application: XCUIApplication?
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }
    override func tearDownWithError() throws {
        if let run = testRun, run.failureCount > 0, let app = application {
            print("MUSHAF_CLOSURE_FAILURE_HIERARCHY\n" + app.debugDescription)
            capture(app, "closure-failure")
        }
    }
    @MainActor func testMeasuredReadingJourneyKeepsGeometryAndSurvivesActualCapture() throws {
        executionTimeAllowance = 180
        let app = XCUIApplication(); application = app
        launchNoorApp(app)
        selectNoorTab("المصحف", in: app)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap(); search.typeText("1\n")
        let surah = app.buttons["surah.1"]
        XCTAssertTrue(surah.waitForExistence(timeout: 10))
        let openBegan = ProcessInfo.processInfo.systemUptime
        surah.tap()
        let page = app.descendants(matching: .any).matching(identifier: "reader.page.ready").firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 20))
        print("MUSHAF_UI_DRIVER_OPEN_SECONDS \(ProcessInfo.processInfo.systemUptime - openBegan)")
        setTajweed(false, app: app)
        let visibility = app.buttons["reader.textVisibility"]
        if visibility.value as? String == "الآيات مخفية" { visibility.tap() }
        XCTAssertEqual(visibility.value as? String, "الآيات ظاهرة")
        // Derived from the pinned edition (receipt: mushaf-ui-source-cases.json):
        // openings, first dense grid, Tawba, in-ayah basmala, densest lexical
        // page, final three surahs and the full-line debt verse. No guessed IDs.
        for number in [1, 2, 3, 187, 379, 501, 48, 604, 14] {
            jump(number, app: app)
            XCTAssertFalse(app.descendants(matching: .any)["reader.downloading"].exists)
            assertControlsOutsidePage(app, page: page)
            capture(app, String(format: "closure-page-%03d-normal", number))
        }
        let jumpControl = app.buttons["reader.jump"]
        for (target, forward) in [(15, true), (16, true), (15, false), (14, false)] {
            let began = ProcessInfo.processInfo.systemUptime
            if forward { page.swipeRight() } else { page.swipeLeft() }
            requirePage(target, app: app)
            XCTAssertFalse(app.descendants(matching: .any)["reader.downloading"].exists)
            print("MUSHAF_UI_DRIVER_TURN target=\(target) seconds=\(ProcessInfo.processInfo.systemUptime - began)")
        }
        let first = app.buttons["reader.verse.2:89"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        let readingFrame = page.frame, verseFrame = first.frame
        first.tap()
        waitUntil { !app.buttons["reader.more"].exists }
        XCTAssertFalse(app.scrollViews["verse.actions.panel"].exists,
                       "A short Quran tap toggles chrome; only a long press selects an ayah")
        XCTAssertEqual(page.frame, readingFrame); XCTAssertEqual(first.frame, verseFrame)
        capture(app, "closure-tools-hidden-stable")
        first.tap()
        XCTAssertTrue(app.buttons["reader.more"].waitForExistence(timeout: 5))
        XCTAssertEqual(page.frame, readingFrame); XCTAssertEqual(first.frame, verseFrame)
        first.press(forDuration: 0.6)
        let actions = app.scrollViews["verse.actions.panel"]
        XCTAssertTrue(actions.waitForExistence(timeout: 5))
        XCTAssertEqual(page.frame, readingFrame); XCTAssertEqual(first.frame, verseFrame)
        capture(app, "closure-ayah-selection-stable")
        for id in ["verse.khatmah.stop", "verse.tafsir", "verse.play", "verse.repeat", "verse.bookmark", "verse.hifz"] {
            let action = try revealNoorVerseAction(id, in: app)
            XCTAssertGreaterThanOrEqual(action.frame.width, 44)
            XCTAssertGreaterThanOrEqual(action.frame.height, 44)
            XCTAssertFalse(action.frame.intersects(page.frame), "Tools cannot cover any Quran: \(id)")
            XCTAssertEqual(first.frame, verseFrame)
        }
        app.buttons["verse.tools.close"].tap()
        setTajweed(true, app: app)
        XCTAssertEqual(page.frame, readingFrame)
        capture(app, "closure-tajweed-on")
        setTajweed(false, app: app)
        XCTAssertEqual(page.frame, readingFrame)
        capture(app, "closure-tajweed-off")
        app.buttons["reader.more"].tap()
        let expand = app.buttons["قراءة بملء الشاشة"]
        XCTAssertTrue(expand.waitForExistence(timeout: 5)); expand.tap()
        waitUntil { !app.buttons["reader.more"].exists && page.frame.height > readingFrame.height }
        first.press(forDuration: 0.6)
        XCTAssertTrue(app.scrollViews["verse.actions.panel"].waitForExistence(timeout: 5))
        XCTAssertEqual(page.frame, readingFrame,
                       "Selecting from explicit full screen restores control lanes before showing actions")
        _ = try revealNoorVerseAction("verse.tafsir", in: app)
        XCTAssertFalse(app.scrollViews["verse.actions.panel"].frame.intersects(page.frame))
        app.buttons["verse.tools.close"].tap()
        let beforeCapture = first.frame
        app.buttons["reader.study"].tap()
        // This must be a real system approval, and the original tap must then
        // capture without a second tap. Quiet Simulator input is not ASR proof.
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if system.alerts.firstMatch.waitForExistence(timeout: 5) {
            let allow = system.alerts.buttons.matching(NSPredicate(format: "label IN %@", ["Allow", "السماح", "سماح"])).firstMatch
            XCTAssertTrue(allow.exists); allow.tap()
        }
        let elapsed = app.staticTexts["study.elapsed"]
        XCTAssertTrue(elapsed.waitForExistence(timeout: 20))
        waitUntil(timeout: 20) {
            elapsed.exists && self.numbers(elapsed.label).last.map { $0 >= 5 } == true
        }
        XCTAssertEqual(page.frame, readingFrame); XCTAssertEqual(first.frame, beforeCapture)
        XCTAssertFalse(app.buttons["study.recordings"].exists)
        capture(app, "closure-actual-microphone")
        app.buttons["study.finish"].tap()
        XCTAssertTrue(app.buttons["reader.study"].waitForExistence(timeout: 20))
        requirePage(14, app: app)
        XCTAssertEqual(page.frame, readingFrame); XCTAssertEqual(first.frame, beforeCapture)
        XCTAssertFalse(app.staticTexts["study.result.saved"].exists)
        capture(app, "closure-after-finish-same-page")
        app.buttons["إغلاق المصحف"].tap()
        selectNoorTab("اليوم", in: app)
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 10))
        app.buttons["home.resume"].tap()
        XCTAssertTrue(page.waitForExistence(timeout: 10))
        requirePage(14, app: app)
        XCTAssertTrue(jumpControl.exists)
        capture(app, "closure-restored-position")
    }
    @MainActor func testLargeInterfaceTextKeepsControlsOutsideTheQuran() throws {
        executionTimeAllowance = 120
        let app = XCUIApplication(); application = app
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        launchNoorApp(app)
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 10))
        app.buttons["home.resume"].tap()
        let page = app.descendants(matching: .any).matching(identifier: "reader.page.ready").firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 20))
        jump(14, app: app)
        assertControlsOutsidePage(app, page: page)
        let before = page.frame, first = app.buttons["reader.verse.2:89"]
        let ink = first.frame
        first.tap(); waitUntil { !app.buttons["reader.more"].exists }
        XCTAssertEqual(page.frame, before); XCTAssertEqual(first.frame, ink)
        first.tap(); XCTAssertTrue(app.buttons["reader.more"].waitForExistence(timeout: 5))
        first.press(forDuration: 0.6)
        for id in ["verse.tafsir", "verse.play", "verse.repeat", "verse.bookmark", "verse.hifz"] {
            let action = try revealNoorVerseAction(id, in: app)
            XCTAssertFalse(action.frame.intersects(page.frame), id)
            XCTAssertGreaterThanOrEqual(action.frame.height, 44)
        }
        XCTAssertEqual(page.frame, before); XCTAssertEqual(first.frame, ink)
        capture(app, "closure-large-interface-text")
        app.buttons["verse.tools.close"].tap()
    }
    @MainActor private func setTajweed(_ enabled: Bool, app: XCUIApplication) {
        app.buttons["reader.more"].tap()
        let toggle = app.buttons["reader.tajweed"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if (toggle.value as? String == "مفعّلة") != enabled { toggle.tap() }
        XCTAssertEqual(toggle.value as? String, enabled ? "مفعّلة" : "متوقفة")
        app.buttons["reader.options.close"].tap()
        let page = app.descendants(matching: .any).matching(identifier: "reader.page.ready").firstMatch
        waitUntil {
            page.exists && page.value as? String == (enabled ? "ألوان التجويد مفعّلة" : "القراءة العادية")
        }
    }
    @MainActor private func jump(_ number: Int, app: XCUIApplication) {
        let control = app.buttons["reader.jump"]
        XCTAssertTrue(control.waitForExistence(timeout: 5))
        if numbers(control.label).first == number { return }
        control.tap()
        let field = app.textFields["reader.pageNumber"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText(String(number)); app.buttons["انتقل"].tap()
        requirePage(number, app: app)
    }
    @MainActor private func requirePage(_ number: Int, app: XCUIApplication) {
        waitUntil {
            let control = app.buttons["reader.jump"]
            return control.exists && self.numbers(control.label) == [number, 604]
        }
    }
    @MainActor private func assertControlsOutsidePage(_ app: XCUIApplication, page: XCUIElement) {
        XCTAssertTrue(app.frame.contains(page.frame))
        let controls = ["reader.jump", "reader.study", "reader.more", "reader.textVisibility", "reader.previous", "reader.next"]
        for id in controls {
            let control = app.buttons[id]
            XCTAssertTrue(control.exists, id)
            XCTAssertGreaterThanOrEqual(control.frame.width, 44, id)
            XCTAssertGreaterThanOrEqual(control.frame.height, 44, id)
            XCTAssertFalse(control.frame.intersects(page.frame), "The actual reading viewport must exclude controls: \(id)")
        }
    }
    private func waitUntil(timeout: TimeInterval = 10, _ predicate: @escaping () -> Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in predicate() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed)
    }
    private func numbers(_ text: String) -> [Int] {
        text.split { $0.wholeNumberValue == nil }.map { $0.reduce(0) { $0 * 10 + ($1.wholeNumberValue ?? 0) } }
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
