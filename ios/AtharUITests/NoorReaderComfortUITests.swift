import XCTest

final class NoorReaderComfortUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }
    override func tearDownWithError() throws { XCUIDevice.shared.orientation = .portrait }
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
        requireTools(true, app: app)
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
        requireStableReadingLayout(app, page: page, landscape: true)
        requirePage(151, app: app)
        requireTools(true, app: app)
        capture(app, "stage1-151-landscape")
        let landscapeFrame = page.frame
        app.buttons["reader.verse.7:1"].tap()
        requireTools(false, app: app)
        XCTAssertEqual(page.frame, landscapeFrame)
        capture(app, "stage1-151-landscape-tools-hidden")
        app.buttons["reader.verse.7:1"].tap()
        requireTools(true, app: app)
        XCUIDevice.shared.orientation = .portrait
        requireStableReadingLayout(app, page: page, landscape: false)
        requirePage(151, app: app)
        capture(app, "stage1-151-portrait-restored")
    }
    private func requireTools(_ visible: Bool, app: XCUIApplication) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.buttons["reader.jump"].isHittable == visible
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 5), .completed)
        if visible {
            let page = app.descendants(matching: .any).matching(identifier: "reader.page.ready").firstMatch
            XCTAssertEqual(app.buttons["reader.jump"].frame.midX, page.frame.midX, accuracy: 1,
                           "Page counter and reading viewport must share one center")
        }
    }
    private func requireStableReadingLayout(_ app: XCUIApplication, page: XCUIElement, landscape: Bool) {
        var previous: CGRect?
        var stableSince = Date()
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let screen = app.frame
            guard screen.width > 0, screen.height > 0,
                  (screen.width > screen.height) == landscape, page.exists else {
                previous = nil; stableSince = Date(); return false
            }
            let frame = page.frame
            guard frame.width > 0, frame.height > 0, screen.contains(frame) else {
                previous = nil; stableSince = Date(); return false
            }
            if previous != frame { previous = frame; stableSince = Date(); return false }
            return Date().timeIntervalSince(stableSince) >= 1
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 15), .completed,
                       "Wait for the final reading geometry, not merely an existing view during rotation")
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
