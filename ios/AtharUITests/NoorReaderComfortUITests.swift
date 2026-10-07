import XCTest

final class NoorReaderComfortUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testPageToolsGesturesAndRelaunchPreservePosition() {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 20))
        app.buttons["home.resume"].tap()
        let page = app.descendants(matching: .any).matching(identifier: "reader.page.ready").firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 120))
        jump(604, app: app)
        let verse = app.buttons["reader.verse.114:1"]
        XCTAssertTrue(verse.waitForExistence(timeout: 20))
        let frame = verse.frame
        capture(app, "stage1-604-tools-visible")
        // A tap on Quran ink, not just a margin, toggles tools without selection.
        verse.tap()
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !app.buttons["reader.jump"].isHittable
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed)
        XCTAssertFalse(app.buttons["verse.tafsir"].exists)
        XCTAssertEqual(verse.frame, frame, "Hiding controls must not move Quran ink")
        capture(app, "stage1-604-tools-hidden")
        verse.tap()
        XCTAssertTrue(app.buttons["reader.jump"].waitForExistence(timeout: 5))
        XCTAssertEqual(verse.frame, frame)
        page.swipeLeft()
        requirePage(603, app: app)
        capture(app, "stage1-603-swiped")
        page.swipeRight()
        requirePage(604, app: app)
        verse.press(forDuration: 0.6)
        XCTAssertTrue(app.buttons["verse.tafsir"].waitForExistence(timeout: 5))
        app.buttons["verse.tools.close"].tap()
        page.pinch(withScale: 1.6, velocity: 1)
        page.swipeLeft()
        requirePage(604, app: app)
        capture(app, "stage1-604-zoom-pan")
        jump(151, app: app)
        capture(app, "stage1-151-centered")
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 20))
        app.buttons["home.resume"].tap()
        XCTAssertTrue(page.waitForExistence(timeout: 120))
        requirePage(151, app: app)
        capture(app, "stage1-151-restored-after-relaunch")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(page.waitForExistence(timeout: 10))
        capture(app, "stage1-151-landscape")
        XCUIDevice.shared.orientation = .portrait
        capture(app, "stage1-151-portrait-restored")
    }
    private func jump(_ number: Int, app: XCUIApplication) {
        app.buttons["reader.jump"].tap()
        let field = app.textFields["reader.pageNumber"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText(String(number))
        app.buttons["انتقل"].tap()
        requirePage(number, app: app)
    }
    private func requirePage(_ number: Int, app: XCUIApplication) {
        let counter = app.buttons["reader.jump"]
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let prefix = counter.label.components(separatedBy: " من ").first ?? ""
            return prefix.compactMap { $0.wholeNumberValue }.reduce(0, { $0 * 10 + $1 }) == number
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 20), .completed)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
