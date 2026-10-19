import XCTest

final class NoorContinuousReaderUITests: XCTestCase {
    @MainActor func testOnlyTrackedRecitersAreSearchableSelectedAndPersistWithoutStartingAudio() {
        executionTimeAllowance = 180
        let app = XCUIApplication(); launchNoorApp(app)
        selectNoorTab("المصحف", in: app)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 15)); search.tap(); search.typeText("١١٤")
        let surah = app.buttons["surah.114"]
        XCTAssertTrue(surah.waitForExistence(timeout: 10)); surah.tap()
        let picker = app.buttons["reader.reciters"]
        XCTAssertTrue(picker.waitForExistence(timeout: 120))
        let viewport = app.descendants(matching: .any)["reader.page.ready"]
        waitForVisibleReader(viewport)
        let visibility = app.buttons["reader.textVisibility"]
        XCTAssertTrue(visibility.exists)
        let mic = app.buttons["reader.study"], jump = app.buttons["reader.jump"]
        XCTAssertTrue(mic.isHittable); XCTAssertTrue(jump.isHittable)
        XCTAssertFalse(mic.frame.intersects(jump.frame), "Page navigation cannot sit underneath the microphone")
        XCTAssertFalse(mic.frame.intersects(visibility.frame), "Visibility keeps its own touch area")
        let more = app.buttons["reader.more"]
        XCTAssertTrue(more.isHittable, "Options are discoverable without a hidden long press")
        more.tap()
        XCTAssertTrue(app.buttons["reader.options.close"].waitForExistence(timeout: 5), "Options have their own button, separate from immediate microphone capture")
        XCTAssertFalse(app.buttons["study.pause"].exists)
        app.buttons["reader.options.close"].tap()
        XCTAssertTrue(mic.waitForExistence(timeout: 5))
        let readerScreenshot = XCTAttachment(screenshot: app.screenshot())
        readerScreenshot.name = "reader-controls-spaced-no-overlap"; readerScreenshot.lifetime = .keepAlways; add(readerScreenshot)
        more.tap()
        XCTAssertTrue(app.buttons["reader.tajweed"].waitForExistence(timeout: 5))
        for title in ["اختيار مقطع التسميع", "تسجيلاتي", "الحفظ والمراجعة"] {
            XCTAssertFalse(app.buttons[title].exists,"Recitation stays inside the Mushaf without a workspace/history route")
        }
        let tajweed = app.buttons["reader.tajweed"]
        XCTAssertTrue(tajweed.isHittable)
        if tajweed.value as? String == "متوقفة" { tajweed.tap() }
        let enabledColors = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "مفعّلة"), object: tajweed)
        XCTAssertEqual(XCTWaiter.wait(for: [enabledColors], timeout: 5), .completed,
                       "The full-width colors action must actually enable the stored mode")
        let closeOptions = app.buttons["reader.options.close"]
        XCTAssertTrue(closeOptions.isHittable, "Options always have an explicit close button")
        closeOptions.tap()
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        waitForVisibleReader(viewport, mode: "ألوان التجويد مفعّلة")
        let colorScreenshot = XCTAttachment(screenshot: app.screenshot())
        colorScreenshot.name = "tajweed-reader-full-screen"; colorScreenshot.lifetime = .keepAlways; add(colorScreenshot)
        more.tap()
        XCTAssertTrue(tajweed.waitForExistence(timeout: 5)); tajweed.tap()
        closeOptions.tap()
        waitForVisibleReader(viewport, mode: "القراءة العادية")
        viewport.swipeLeft()
        print("NOOR_PAGE_AFTER_SWIPE \(jump.label.debugDescription)")
        let previousPage = XCTNSPredicateExpectation(predicate: NSPredicate { object, _ in
            guard let element = object as? XCUIElement else { return false }
            return Self.pageNumbers(element.label) == [603, 604]
        }, object: jump)
        XCTAssertEqual(XCTWaiter.wait(for: [previousPage], timeout: 10), .completed,
                       "A real RTL swipe turns exactly one page. Actual: \(jump.label.debugDescription)")
        app.buttons["reader.next"].tap()
        print("NOOR_PAGE_AFTER_NEXT \(jump.label.debugDescription)")
        let lastPage = XCTNSPredicateExpectation(predicate: NSPredicate { object, _ in
            guard let element = object as? XCUIElement else { return false }
            return Self.pageNumbers(element.label) == [604, 604]
        }, object: jump)
        XCTAssertEqual(XCTWaiter.wait(for: [lastPage], timeout: 10), .completed,
                       "The next button returns to604. Actual: \(jump.label.debugDescription)")
        XCTAssertFalse(app.buttons["reader.next"].isEnabled, "Last page cannot overshoot")
        let verse = app.buttons["reader.verse.112:1"]
        XCTAssertTrue(verse.waitForExistence(timeout: 10)); verse.tap()
        let closeVerse = app.buttons["verse.tools.close"]
        XCTAssertTrue(closeVerse.waitForExistence(timeout: 5))
        let selectionProof = XCTAttachment(screenshot: app.screenshot())
        selectionProof.name = "actual-ayah-yellow-selection-and-clear-actions"; selectionProof.lifetime = .keepAlways; add(selectionProof)
        closeVerse.tap()
        if visibility.value as? String == "الآيات مخفية" { visibility.tap() }
        XCTAssertEqual(visibility.value as? String, "الآيات ظاهرة")
        visibility.tap()
        XCTAssertEqual(visibility.value as? String, "الآيات مخفية")
        XCTAssertTrue(app.buttons["reader.study"].exists)
        visibility.tap()
        XCTAssertEqual(visibility.value as? String, "الآيات ظاهرة")
        let readingHeight = viewport.frame.height
        more.tap()
        let fullScreen = app.buttons["قراءة بملء الشاشة"]
        XCTAssertTrue(fullScreen.waitForExistence(timeout: 5)); fullScreen.tap()
        let hiddenControls = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: more)
        XCTAssertEqual(XCTWaiter.wait(for: [hiddenControls], timeout: 5), .completed)
        waitForVisibleReader(viewport, mode: "القراءة العادية")
        XCTAssertGreaterThan(viewport.frame.height, readingHeight + 44,
                             "Hiding tools must reclaim their actual reading space")
        let fullScreenProof = XCTAttachment(screenshot: app.screenshot())
        fullScreenProof.name = "full-screen-reclaimed-reading-space"; fullScreenProof.lifetime = .keepAlways; add(fullScreenProof)
        viewport.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.01)).tap()
        XCTAssertTrue(more.waitForExistence(timeout: 5), "A blank margin tap restores the reader tools")
        picker.tap()
        for removed in ["Hudhaify_64kbps", "Maher_AlMuaiqly_64kbps", "surah:54:54", "surah:21181:340"] {
            XCTAssertFalse(app.buttons["reader.reciter.\(removed)"].exists, "Untimed sources must not reappear")
        }
        let reciterSearch = app.searchFields.firstMatch
        XCTAssertTrue(reciterSearch.waitForExistence(timeout: 10))
        reciterSearch.tap(); reciterSearch.typeText("الشريم")
        let voice = app.buttons["reader.reciter.surah:31:31"]
        XCTAssertTrue(voice.waitForExistence(timeout: 10), "The exact word-timed whole-surah recording is searchable")
        voice.tap()
        XCTAssertTrue(picker.waitForExistence(timeout: 10)); picker.tap()
        let selectedSearch = app.searchFields.firstMatch
        XCTAssertTrue(selectedSearch.waitForExistence(timeout: 10))
        selectedSearch.tap(); selectedSearch.typeText("الشريم")
        XCTAssertTrue(voice.waitForExistence(timeout: 10))
        XCTAssertEqual(voice.value as? String, "محدد")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "word-timed-reciter-selected-and-searchable"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["إغلاق"].tap()
        XCTAssertTrue(app.buttons["reader.study"].exists)
        XCTAssertFalse(app.staticTexts["study.result.saved"].exists)
    }
    /// Preserve the exact page/total assertion without depending on invisible
    /// bidi formatting inserted around localized Arabic interpolation.
    private static func pageNumbers(_ label: String) -> [Int] {
        label.split { $0.wholeNumberValue == nil }.map { digits in
            digits.reduce(0) { value, digit in value * 10 + (digit.wholeNumberValue ?? 0) }
        }
    }
    @MainActor private func waitForVisibleReader(_ viewport: XCUIElement, mode: String? = nil) {
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate { object, _ in
            guard let element = object as? XCUIElement else { return false }
            return element.exists && element.isHittable && (mode == nil || element.value as? String == mode)
        }, object: viewport)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 15), .completed,
                       "Capture the visible completed reader, not a loading or covered canvas. Actual mode: \(String(describing: viewport.value))")
    }
}
