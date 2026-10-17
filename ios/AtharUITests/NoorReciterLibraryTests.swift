import XCTest

final class NoorReciterLibraryTests: XCTestCase {
    func testCompleteReciterLibraryCanFindFinalSurahWithoutStartingRecording() {
        let app = XCUIApplication()
        launchNoorApp(app)
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 15))
        selectNoorTab("المصحف", in: app)
        let library = app.buttons["quran.haramainReciters"]
        XCTAssertTrue(library.waitForExistence(timeout: 10)); library.tap()
        let reader = app.buttons["reciter.54"]
        XCTAssertTrue(reader.waitForExistence(timeout: 10)); reader.tap()
        XCTAssertTrue(app.buttons["reciter.playCompleteQuran"].waitForExistence(timeout: 10))
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("114")
        XCTAssertTrue(app.buttons["reciter.surah.114"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["reciter.surah.1"].exists)
        XCTAssertFalse(app.buttons["study.finish"].exists)
    }
}
