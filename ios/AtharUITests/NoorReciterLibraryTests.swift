import XCTest

final class NoorReciterLibraryTests: XCTestCase {
    func testTrackedLibraryFindsFinalSurahAndOpensTheSelectedVoiceInMushaf() {
        let app = XCUIApplication()
        launchNoorApp(app)
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 15))
        selectNoorTab("المصحف", in: app)
        let library = app.buttons["quran.haramainReciters"]
        XCTAssertTrue(library.waitForExistence(timeout: 10)); library.tap()
        XCTAssertFalse(app.buttons["reciter.54"].exists, "Ayah-only timing does not qualify")
        XCTAssertFalse(app.buttons["reciter.21181"].exists)
        let reader = app.buttons["reciter.74"]
        XCTAssertTrue(reader.waitForExistence(timeout: 10)); reader.tap()
        XCTAssertTrue(app.buttons["reciter.openMushaf"].waitForExistence(timeout: 10))
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("114")
        XCTAssertTrue(app.buttons["reciter.surah.114"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["reciter.surah.1"].exists)
        app.buttons["reciter.surah.114"].tap()
        let picker = app.buttons["reader.reciters"]
        XCTAssertTrue(picker.waitForExistence(timeout: 120))
        XCTAssertEqual(picker.value as? String, "علي بن عبدالرحمن الحذيفي")
        XCTAssertTrue(app.buttons["reader.verse.114:1"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["reader.audio.stop"].exists, "Opening the reader alone cannot start playback")
        XCTAssertFalse(app.buttons["study.finish"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "closure-reader-library-selected-voice-final-surah"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
