import XCTest

final class NoorInteractiveMushafUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
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
        page.swipeLeft()
        XCTAssertTrue(app.buttons["reader.verse.109:1"].waitForExistence(timeout: 30), "Fitted swipe opens page 603")
        capture(app, "text-reader-603-swiped")
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
                if key == "114:1" {
                    capture(app, "text-reader-604-highlight-tools")
                    app.buttons["verse.tafsir"].tap()
                    XCTAssertTrue(app.staticTexts["verse.tafsir.text"].waitForExistence(timeout: 45))
                    capture(app, "text-reader-604-tafsir")
                    app.buttons["verse.tafsir.close"].tap()
                    verse.press(forDuration: 0.6)
                    app.buttons["verse.more"].tap()
                    app.swipeUp()
                    app.buttons["verse.copy"].tap()
                    XCTAssertTrue(app.staticTexts["verse.notice"].waitForExistence(timeout: 10))
                    capture(app, "text-reader-604-copy-confirmed")
                }
                app.buttons["verse.tools.close"].tap()
            }
        }
        let verse = app.buttons["reader.verse.114:1"]
        verse.press(forDuration: 0.6); app.buttons["verse.play"].tap()
        XCTAssertTrue(app.buttons["إيقاف التلاوة"].waitForExistence(timeout: 20))
        capture(app, "text-reader-604-audio-started")
        app.buttons["إيقاف التلاوة"].tap()
        page.pinch(withScale: 1.6, velocity: 1)
        capture(app, "text-reader-604-zoom")
        page.swipeLeft()
        capture(app, "text-reader-604-zoom-and-pan")
        let zoomedVerse = app.buttons["reader.verse.114:1"]
        zoomedVerse.press(forDuration: 0.6)
        XCTAssertTrue(app.buttons["verse.tafsir"].waitForExistence(timeout: 10))
        capture(app, "text-reader-604-zoom-reselection")
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
