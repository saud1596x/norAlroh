import XCTest

final class NoorRemovedFeaturesUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor func testRetiredActionsAreAbsentAndJourneyRemainsReachable() {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting"]; app.launch()
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 30))
        let footer = app.descendants(matching: .any).matching(identifier: "home.footer").firstMatch
        for _ in 0..<6 {
            if footer.exists && footer.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(footer.exists && footer.isHittable)
        XCTAssertFalse(app.buttons["home.reflection"].exists)
        XCTAssertFalse(app.buttons["قارن الآيات"].exists)
        XCTAssertFalse(app.staticTexts["وقفة مع آية"].exists)
        let journey = app.buttons["home.myJourney"]
        XCTAssertTrue(journey.exists && journey.isHittable)
        capture(app, "home-with-retired-actions-removed")
        journey.tap()
        XCTAssertTrue(app.navigationBars["رحلتي"].waitForExistence(timeout: 10))
        capture(app, "journey-still-reachable")
        selectNoorTab("الحفظ", in: app)
        for _ in 0..<4 { app.swipeUp() }
        XCTAssertFalse(app.buttons["hifz.similarities"].exists)
        XCTAssertFalse(app.staticTexts["الآيات المتشابهة"].exists)
        capture(app, "memorization-with-retired-action-removed")
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
}
