import XCTest

final class NoorReciterLibraryTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor func testCompletePickerSearchClearsAndNewRecordingsPersistWithoutPlayback() {
        executionTimeAllowance = 120
        let app = XCUIApplication(); launchNoorApp(app)
        selectNoorTab("المصحف", in: app)
        let surahSearch = app.searchFields.firstMatch
        XCTAssertTrue(surahSearch.waitForExistence(timeout: 15)); surahSearch.tap(); surahSearch.typeText("114\n")
        let surah = app.buttons["surah.114"]
        XCTAssertTrue(surah.waitForExistence(timeout: 10)); surah.tap()
        let open = app.buttons["reader.reciters"]
        XCTAssertTrue(open.waitForExistence(timeout: 120))
        let page = app.descendants(matching: .any).matching(identifier: "reader.page.ready").firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 20))
        let original = page.frame
        for (index, choice) in [("surah:1000001:1000001", "العفاسي"), ("surah:1000002:1000002", "ماهر"), ("surah:1000003:1000003", "الحصري")].enumerated() {
            let (identity, query) = choice
            open.tap()
            let search = app.textFields["reader.reciters.search"]
            XCTAssertTrue(search.waitForExistence(timeout: 10))
            XCTAssertFalse(app.keyboards.firstMatch.exists)
            let close = app.buttons["reader.reciters.close"]
            XCTAssertGreaterThanOrEqual(close.frame.height, 44); XCTAssertTrue(close.isHittable)
            for removed in ["surah:31:31", "Saood_ash-Shuraym_128kbps", "Abdul_Basit_Murattal_64kbps", "Abdurrahmaan_As-Sudais_192kbps"] {
                XCTAssertFalse(app.buttons["reader.reciter.\(removed)"].exists, "Partial timing must stay out of the picker")
            }
            if index == 0 {
                search.tap(); search.typeText("قارئ غير موجود\n")
                XCTAssertTrue(app.descendants(matching: .any)["reader.reciters.empty"].waitForExistence(timeout: 5))
                app.buttons["reader.reciters.search.clear"].tap()
                XCTAssertFalse(app.descendants(matching: .any)["reader.reciters.empty"].exists)
            }
            search.tap(); search.typeText(query + "\n")
            XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "reader.voice.")).count, 1)
            let button = app.buttons["reader.reciter.\(identity)"]
            XCTAssertTrue(button.isHittable)
            XCTAssertTrue(button.label.contains("توقيت الكلمات متاح لجميع الآيات"))
            button.tap()
            XCTAssertTrue(open.waitForExistence(timeout: 10))
            XCTAssertEqual(page.frame, original)
            XCTAssertTrue(app.buttons["reader.verse.114:1"].exists)
            XCTAssertFalse(app.buttons["reader.audio.stop"].exists)
            open.tap()
            let selectedSearch = app.textFields["reader.reciters.search"]
            XCTAssertTrue(selectedSearch.waitForExistence(timeout: 10)); selectedSearch.tap(); selectedSearch.typeText(query + "\n")
            XCTAssertEqual(app.buttons["reader.reciter.\(identity)"].value as? String, "محدد")
            app.buttons["reader.reciters.close"].tap()
        }
        app.buttons["إغلاق المصحف"].tap()
        app.terminate(); launchNoorApp(app)
        let resume = app.buttons["home.resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 15)); resume.tap()
        XCTAssertTrue(open.waitForExistence(timeout: 120)); open.tap()
        let restoredSearch = app.textFields["reader.reciters.search"]
        XCTAssertTrue(restoredSearch.waitForExistence(timeout: 10)); restoredSearch.tap(); restoredSearch.typeText("الحصري\n")
        XCTAssertEqual(app.buttons["reader.reciter.surah:1000003:1000003"].value as? String, "محدد")
        XCTAssertFalse(app.buttons["reader.reciter.Saood_ash-Shuraym_128kbps"].exists)
        XCTAssertFalse(app.buttons["reader.audio.stop"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "grouped-reciter-picker-selected-whole-surah"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["reader.reciters.close"].tap()
    }

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
        XCTAssertTrue(reader.waitForExistence(timeout: 10))
        XCTAssertTrue(reader.label.contains("توقيت الكلمات متاح لجميع الآيات"))
        reader.tap()
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
        XCTAssertEqual(app.staticTexts["reader.title"].label, "سُورَةُ النَّاسِ",
                       "Opening surah114 must retain its target on the shared604 face")
        XCTAssertFalse(app.scrollViews["verse.actions.panel"].exists,
                       "An entry target highlights the ayah without opening manual tools")
        XCTAssertFalse(app.buttons["reader.audio.stop"].exists, "Opening the reader alone cannot start playback")
        XCTAssertFalse(app.buttons["study.microphone"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "closure-reader-library-selected-voice-final-surah"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
