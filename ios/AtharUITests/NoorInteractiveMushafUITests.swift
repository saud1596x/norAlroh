import XCTest

final class NoorInteractiveMushafUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testPersistedReferenceRecordingTransportRemovalAndRelaunch() {
        // seed-recording-ui.py installs repeated authentic reference audio,
        // explicitly identified as a fixture. No live capture/ASR claim.
        let app = XCUIApplication(); app.launch()
        let session = "A1662B68-55BB-4A4B-9441-761EF83DCF54"
        let take = "50CC9A34-A7A3-44B5-A7A7-39671AC60968"
        func open() {
            XCTAssertTrue(app.buttons["app.settings"].waitForExistence(timeout: 20))
            app.buttons["app.settings"].tap()
            let recordings = app.buttons["settings.recordings"]
            for _ in 0..<8 {
                if recordings.exists && recordings.isHittable { break }
                app.swipeUp()
            }
            XCTAssertTrue(recordings.waitForExistence(timeout: 5)); recordings.tap()
            let row = app.buttons["study.recording.session.\(session)"]
            XCTAssertTrue(row.waitForExistence(timeout: 10)); capture(app, "reference-recording-session-history")
            row.tap()
        }
        open()
        XCTAssertTrue(app.staticTexts["study.recordings.range"].waitForExistence(timeout: 5))
        let play = app.buttons["study.recording.play.\(take)"]
        XCTAssertTrue(play.waitForExistence(timeout: 5)); play.tap()
        let seek = app.sliders["study.recording.seek"]
        XCTAssertTrue(seek.waitForExistence(timeout: 5)); capture(app, "reference-recording-playing")
        play.tap(); XCTAssertTrue(play.label.contains("استماع"))
        seek.adjust(toNormalizedSliderPosition: 0.45)
        capture(app, "reference-recording-paused-and-seeked")
        play.tap(); XCTAssertTrue(play.label.contains("إيقاف مؤقت"))
        app.buttons["study.recording.replay.\(take)"].tap()
        XCTAssertTrue(seek.exists); capture(app, "reference-recording-replayed")
        app.buttons["study.recording.options.\(take)"].tap()
        app.buttons["نقل إلى المحذوفات"].tap()
        XCTAssertFalse(play.exists)
        app.buttons["study.recordings.deleted"].tap()
        XCTAssertTrue(app.buttons["study.recording.restore.\(take)"].waitForExistence(timeout: 5))
        capture(app, "reference-recording-recoverable-removal")
        app.terminate(); app.launch(); open()
        XCTAssertFalse(app.buttons["study.recording.play.\(take)"].exists)
        app.buttons["study.recordings.deleted"].tap()
        let restore = app.buttons["study.recording.restore.\(take)"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5)); restore.tap()
        app.buttons["study.recordings.deleted"].tap()
        let restoredPlay = app.buttons["study.recording.play.\(take)"]
        XCTAssertTrue(restoredPlay.waitForExistence(timeout: 5)); restoredPlay.tap()
        XCTAssertTrue(app.sliders["study.recording.seek"].waitForExistence(timeout: 5))
        capture(app, "reference-recording-restored-playback-after-relaunch")
        app.buttons["study.recordings.close"].tap()
    }
    func test604ActualReaderEveryVerseToolsAndZoom() {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 20))
        selectNoorTab("المصحف", in: app)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("١١٤")
        let surah = app.buttons["surah.114"]
        XCTAssertTrue(surah.waitForExistence(timeout: 10)); surah.tap()
        let page = app.descendants(matching: .any).matching(identifier: "reader.page.ready").firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 120))
        capture(app, "text-reader-604-open")
        let originalFrame = page.frame
        page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["reader.next"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(page.frame, originalFrame, "Hiding tools must not resize or move the page")
        capture(app, "text-reader-604-tools-hidden")
        page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["reader.next"].waitForExistence(timeout: 5))
        XCTAssertEqual(page.frame, originalFrame, "Restoring tools keeps the same viewport")
        capture(app, "text-reader-604-tools-restored")
        page.swipeLeft()
        XCTAssertTrue(app.buttons["reader.verse.109:1"].waitForExistence(timeout: 30), "Fitted swipe opens page 603")
        capture(app, "text-reader-603-swiped")
        app.buttons["إغلاق المصحف"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 20))
        app.buttons["home.resume"].tap()
        XCTAssertTrue(app.buttons["reader.verse.109:1"].waitForExistence(timeout: 120),
            "Continue reading restores page 603 after terminating the app")
        capture(app, "text-reader-603-restored-after-relaunch")
        page.swipeRight()
        XCTAssertTrue(app.buttons["reader.verse.114:1"].waitForExistence(timeout: 30), "RTL forward swipe returns to 604")
        capture(app, "text-reader-604-swiped-back")
        for chapter in 112...114 {
            for number in 1...(chapter == 112 ? 4 : chapter == 113 ? 5 : 6) {
                let key = "\(chapter):\(number)"
                let verse = app.buttons["reader.verse.\(key)"]
                XCTAssertTrue(verse.waitForExistence(timeout: 10), key); verse.press(forDuration: 0.6)
                XCTAssertTrue(app.buttons["verse.tafsir"].waitForExistence(timeout: 10), key)
                let actualTitle = app.staticTexts["verse.tools.title"]
                XCTAssertTrue(actualTitle.waitForExistence(timeout: 10), key)
                let titleDigits = actualTitle.label.compactMap { $0.wholeNumberValue }
                XCTAssertEqual(titleDigits.reduce(0) { $0 * 10 + $1 }, number, "Correct ayah title \(key)")
                // Match the actual verified corpus spelling, including Quranic
                // combining marks which Foundation's diacritic folding need
                // not remove (for example U+06E1 in the name of Al-Ikhlas).
                let surahNames = [112: "سُورَةُ الإِخۡلَاصِ", 113: "سُورَةُ الفَلَقِ", 114: "سُورَةُ النَّاسِ"]
                XCTAssertEqual(actualTitle.value as? String, key, "Selected reference: \(actualTitle.label)")
                XCTAssertTrue(actualTitle.label.contains(surahNames[chapter]!),
                    "Expected surah \(chapter) for \(key); actual toolbar: \(actualTitle.label)")
                XCTAssertEqual(page.frame, originalFrame, "Selection must retain the reading viewport")
                if key == "114:1" {
                    capture(app, "text-reader-604-highlight-tools")
                    app.buttons["verse.tafsir"].tap()
                    XCTAssertTrue(app.staticTexts["verse.tafsir.text"].waitForExistence(timeout: 45))
                    XCTAssertTrue(app.staticTexts["verse.tafsir.ayah"].exists)
                    XCTAssertTrue(app.staticTexts["verse.sheet.title"].label.contains("١") || app.staticTexts["verse.sheet.title"].label.contains("1"))
                    capture(app, "text-reader-604-tafsir")
                    app.buttons["verse.tafsir.close"].tap()
                    verse.press(forDuration: 0.6)
                    app.buttons["verse.more"].tap()
                    app.swipeUp()
                    app.buttons["verse.copy"].tap()
                    XCTAssertTrue(app.staticTexts["verse.notice"].waitForExistence(timeout: 10))
                    capture(app, "text-reader-604-copy-confirmed")
                    XCTAssertTrue(app.buttons["verse.sheet.close"].waitForExistence(timeout: 5))
                    app.buttons["verse.sheet.close"].tap()
                    XCTAssertTrue(app.buttons["reader.jump"].waitForExistence(timeout: 5))
                    XCTAssertFalse(app.buttons["verse.tafsir"].exists, "Dismissing the sheet clears selection")
                } else {
                    app.buttons["verse.tools.close"].tap()
                }
            }
        }
        let verse = app.buttons["reader.verse.114:1"]
        verse.press(forDuration: 0.6); app.buttons["verse.play"].tap()
        let audioTerminal = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.buttons["إيقاف التلاوة"].exists || app.alerts["التلاوة"].exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [audioTerminal], timeout: 25), .completed,
            "Playback must start or report a bounded connection failure; never spin indefinitely")
        if app.buttons["إيقاف التلاوة"].exists {
            capture(app, "text-reader-604-audio-started")
            app.buttons["إيقاف التلاوة"].tap()
        } else {
            capture(app, "text-reader-604-audio-connection-failure")
            app.alerts["التلاوة"].buttons["حسنًا"].tap()
            XCTAssertFalse(app.buttons["إلغاء تحميل التلاوة"].exists)
            XCTAssertTrue(app.buttons["reader.study"].exists,
                "A failed stream releases playback ownership and restores reader tools")
        }
        page.pinch(withScale: 1.6, velocity: 1)
        capture(app, "text-reader-604-zoom")
        page.swipeLeft()
        capture(app, "text-reader-604-zoom-and-pan")
        let zoomedVerse = app.buttons["reader.verse.114:1"]
        zoomedVerse.press(forDuration: 0.6)
        XCTAssertTrue(app.buttons["verse.tafsir"].waitForExistence(timeout: 10))
        capture(app, "text-reader-604-zoom-reselection")
    }
    func testMicrophoneDenialKeepsReaderAvailableAndStationary() {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 20))
        app.buttons["home.resume"].tap()
        let page = app.descendants(matching: .any).matching(identifier: "reader.page.ready").firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 120), "Reader failed to become available: \(app.debugDescription)")
        let frame = page.frame
        XCTAssertTrue(app.buttons["reader.study"].waitForExistence(timeout: 10))
        app.buttons["reader.study"].tap()
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let denied = system.buttons.matching(NSPredicate(format: "label == %@ OR label == %@ OR label == %@", "Don’t Allow", "Don't Allow", "عدم السماح")).firstMatch
        if denied.waitForExistence(timeout: 10) { denied.tap() }
        XCTAssertTrue(app.alerts["التسميع"].waitForExistence(timeout: 15))
        capture(app, "recitation-microphone-denied")
        app.alerts["التسميع"].buttons["حسنًا"].tap()
        XCTAssertTrue(app.buttons["reader.study"].waitForExistence(timeout: 5))
        XCTAssertEqual(page.frame, frame, "Permission denial cannot move the Quran page")
        XCTAssertFalse(app.buttons["study.finish"].exists, "No false recording session after denied permission")
        capture(app, "recitation-reading-after-denial")
    }
    func testSecondaryScopeSelectsSurahAndRangeWithoutStartingMicrophone() {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 20))
        app.buttons["home.resume"].tap()
        let page = app.descendants(matching: .any).matching(identifier: "reader.page.ready").firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 120), app.debugDescription)
        let frame = page.frame
        app.buttons["reader.study"].press(forDuration: 1)
        let choose = app.buttons["اختيار مقطع التسميع"]
        XCTAssertTrue(choose.waitForExistence(timeout: 5)); choose.tap()
        let kind = app.segmentedControls["recitation.scope.kind"]
        XCTAssertTrue(kind.waitForExistence(timeout: 5))
        capture(app, "recitation-scope-page")
        kind.buttons["سورة"].tap()
        XCTAssertTrue(app.buttons["recitation.scope.chapter"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["recitation.scope.count"].exists)
        capture(app, "recitation-scope-surah")
        kind.buttons["آيات"].tap()
        XCTAssertTrue(app.steppers["recitation.scope.from"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.steppers["recitation.scope.to"].exists)
        XCTAssertTrue(app.buttons["recitation.scope.start"].isEnabled)
        capture(app, "recitation-scope-range")
        app.buttons["recitation.scope.close"].tap()
        XCTAssertTrue(app.buttons["reader.study"].waitForExistence(timeout: 5))
        XCTAssertEqual(page.frame, frame)
        XCTAssertFalse(app.buttons["study.finish"].exists, "Scope selection cannot start capture before its explicit start button")
    }
    func testActualVersePlaybackFailureShowsNoticeAndRestoresReader() {
        let app = XCUIApplication()
        app.launchArguments = ["-NoorAcceptanceUnavailableVerseAudio"]
        app.launch()
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 20))
        app.buttons["home.resume"].tap()
        let page = app.descendants(matching: .any).matching(identifier: "reader.page.ready").firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 120), app.debugDescription)
        let frame = page.frame
        let verse = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "reader.verse.")).firstMatch
        XCTAssertTrue(verse.waitForExistence(timeout: 5)); verse.press(forDuration: 0.6)
        app.buttons["verse.play"].tap()
        let notice = app.alerts["التلاوة"]
        XCTAssertTrue(notice.waitForExistence(timeout: 25), app.debugDescription)
        capture(app, "recitation-reader-actual-audio-failure")
        notice.buttons["حسنًا"].tap()
        XCTAssertTrue(app.buttons["reader.study"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["إلغاء تحميل التلاوة"].exists)
        XCTAssertEqual(page.frame, frame)
        capture(app, "recitation-reader-restored-after-audio-failure")
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
