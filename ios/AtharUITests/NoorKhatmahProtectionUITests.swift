import XCTest

final class NoorKhatmahProtectionUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testProtectionIsVisibleOnHomeAndLinksToKhatmah() {
        let app = XCUIApplication(); launchNoorApp(app)
        let protection = app.buttons["khatmah.protection"]
        for _ in 0..<4 where !protection.isHittable { app.swipeUp() }
        XCTAssertTrue(protection.waitForExistence(timeout: 10))
        XCTAssertTrue(protection.isHittable)
        XCTAssertGreaterThanOrEqual(protection.frame.height, 44)
        capture(app, "protection-visible-on-home")
        protection.tap()
        let khatmah = app.buttons["focus.khatmah"]
        for _ in 0..<4 where !khatmah.isHittable { app.swipeUp() }
        XCTAssertTrue(khatmah.waitForExistence(timeout: 10)); XCTAssertTrue(khatmah.isHittable)
        capture(app, "protection-khatmah-setup")
        khatmah.tap()
        let visibleJourney = NSPredicate { _, _ in
            app.buttons["khatmah.setup"].exists || app.staticTexts["khatmah.completedPages"].exists
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: visibleJourney, object: app)], timeout: 10), .completed)
        XCTAssertTrue(app.buttons["khatmah.protection"].exists)
        capture(app, "protection-visible-in-khatmah")
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
}
