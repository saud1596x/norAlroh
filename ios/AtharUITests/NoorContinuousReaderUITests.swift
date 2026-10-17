import XCTest

final class NoorContinuousReaderUITests: XCTestCase {
    @MainActor func testLastCatalogReciterIsSearchableSelectedAndPersistsWithoutStartingAudio() {
        let app = XCUIApplication(); launchNoorApp(app)
        selectNoorTab("المصحف", in: app)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 15)); search.tap(); search.typeText("١١٤")
        let surah = app.buttons["surah.114"]
        XCTAssertTrue(surah.waitForExistence(timeout: 10)); surah.tap()
        let picker = app.buttons["reader.reciters"]
        XCTAssertTrue(picker.waitForExistence(timeout: 120))
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
        app.buttons["إلغاء"].tap()
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
}
