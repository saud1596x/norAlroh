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
        XCTAssertTrue(picker.waitForExistence(timeout: 120)); picker.tap()
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
