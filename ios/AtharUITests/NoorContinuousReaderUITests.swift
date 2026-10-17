import XCTest

final class NoorContinuousReaderUITests: XCTestCase {
    @MainActor func testLastCatalogReciterIsSearchableSelectedAndPersistsWithoutStartingAudio() {
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
        let readerScreenshot = XCTAttachment(screenshot: app.screenshot())
        readerScreenshot.name = "reader-controls-spaced-no-overlap"; readerScreenshot.lifetime = .keepAlways; add(readerScreenshot)
        more.tap()
        XCTAssertTrue(app.buttons["اختيار مقطع التسميع"].waitForExistence(timeout: 5))
        let tajweed = app.switches["reader.tajweed"]
        XCTAssertTrue(tajweed.exists)
        if tajweed.value as? String == "0" { tajweed.tap() }
        XCTAssertEqual(tajweed.value as? String, "1", "The actual colors switch must be on")
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
        picker.tap()
        let reciterSearch = app.searchFields.firstMatch
        XCTAssertTrue(reciterSearch.waitForExistence(timeout: 10))
        reciterSearch.tap(); reciterSearch.typeText("برهجي")
        let voice = app.buttons["reader.reciter.surah:21181:340"]
        XCTAssertTrue(voice.waitForExistence(timeout: 10), "The last catalog entry is not limited to the first five voices")
        voice.tap()
        XCTAssertTrue(picker.waitForExistence(timeout: 10)); picker.tap()
        let selectedSearch = app.searchFields.firstMatch
        XCTAssertTrue(selectedSearch.waitForExistence(timeout: 10))
        selectedSearch.tap(); selectedSearch.typeText("برهجي")
        XCTAssertTrue(voice.waitForExistence(timeout: 10))
        XCTAssertEqual(voice.value as? String, "محدد")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "last-reciter-selected-and-searchable"; screenshot.lifetime = .keepAlways; add(screenshot)
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
