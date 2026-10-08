import XCTest

final class NoorSalawatUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testActualCounterIncrementUndoAndRelaunchPersist() {
        let app = XCUIApplication(); launchNoorApp(app)
        openCounter(app)
        let count = app.staticTexts["salawat.count"]
        XCTAssertTrue(count.waitForExistence(timeout: 10))
        let initial = Int(count.value as? String ?? "") ?? -1
        XCTAssertGreaterThanOrEqual(initial, 0)
        let add = app.buttons["salawat.increment"]
        for _ in 0..<4 where !add.isHittable { app.swipeUp() }
        XCTAssertTrue(add.isHittable)
        XCTAssertGreaterThanOrEqual(add.frame.height, 44)
        add.tap(); add.tap()
        XCTAssertEqual(count.value as? String, String(initial + 2))
        app.buttons["salawat.undo"].tap()
        XCTAssertEqual(count.value as? String, String(initial + 1))
        capture(app, name: "salawat-counter-actual")
        app.terminate(); launchNoorApp(app); openCounter(app)
        XCTAssertEqual(app.staticTexts["salawat.count"].value as? String, String(initial + 1))
        capture(app, name: "salawat-counter-restored")
    }
    private func openCounter(_ app: XCUIApplication) {
        let link = app.buttons["home.salawat"]
        for _ in 0..<6 {
            if link.exists && link.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(link.waitForExistence(timeout: 10)); XCTAssertTrue(link.isHittable); link.tap()
        XCTAssertTrue(app.staticTexts["salawat.count"].waitForExistence(timeout: 10))
    }
    private func capture(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
