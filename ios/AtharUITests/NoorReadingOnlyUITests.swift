import XCTest

/// Actual app journeys. These checks establish persisted preferences and
/// navigation, not a measured animation frame rate or physical-device quality.
final class NoorReadingOnlyUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testReducedMotionPreferenceSurvivesRelaunchAndReaderReturn() {
        let app = XCUIApplication(); launchNoorApp(app)
        openSettings(app)
        let motion = app.switches["تقليل الحركة"]
        reveal(motion, in: app)
        let original = motion.value as? String
        XCTAssertTrue(original == "0" || original == "1", "Expected a real persisted switch")
        if original != "1" { motion.tap() }
        XCTAssertEqual(motion.value as? String, "1")
        app.buttons["تم"].tap()
        app.terminate(); launchNoorApp(app)
        XCTAssertFalse(app.buttons["launch.skip"].exists, "Reduced motion skips the animated entrance")
        let resume = app.buttons["home.resume"]
        reveal(resume, in: app); resume.tap()
        let page = app.descendants(matching: .any).matching(identifier: "reader.page.ready").firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 120))
        XCTAssertFalse(app.buttons["reader.study"].exists)
        XCTAssertFalse(app.buttons["study.microphone"].exists)
        let close = app.buttons["إغلاق المصحف"]
        XCTAssertTrue(close.isHittable); close.tap()
        XCTAssertTrue(resume.waitForExistence(timeout: 10))
        openSettings(app); reveal(motion, in: app)
        XCTAssertEqual(motion.value as? String, "1", "Returning from reading must not reset the preference")
        capture(app, "reading-only-reduced-motion-persisted")
        if original == "0" { motion.tap() }
        XCTAssertEqual(motion.value as? String, original)
        app.buttons["تم"].tap()
    }

    func testReadingOptionsDoNotExposeCaptureOrTajweedAndCancelPreservesPage() {
        let app = XCUIApplication(); launchNoorApp(app)
        let resume = app.buttons["home.resume"]
        reveal(resume, in: app); resume.tap()
        let page = app.descendants(matching: .any).matching(identifier: "reader.page.ready").firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 120))
        let originalFrame = page.frame
        let originalTitle = app.staticTexts["reader.title"].label
        XCTAssertFalse(app.buttons["reader.study"].exists)
        XCTAssertFalse(app.buttons["reader.textVisibility"].exists)
        XCTAssertTrue(app.buttons["reader.reciters"].isHittable)
        app.buttons["reader.more"].tap()
        XCTAssertTrue(app.buttons["reader.options.close"].waitForExistence(timeout: 5))
        for title in ["التسميع", "اختيار مقطع التسميع", "الحفظ والمراجعة", "تسجيلاتي", "التجويد", "ألوان التجويد"] {
            XCTAssertFalse(app.buttons[title].exists)
            XCTAssertFalse(app.switches[title].exists)
        }
        XCTAssertTrue(app.buttons["الختمة وموضع التوقف"].isHittable)
        XCTAssertTrue(app.buttons["قراءة بملء الشاشة"].isHittable)
        capture(app, "reading-only-options")
        app.buttons["reader.options.close"].tap()
        XCTAssertTrue(app.buttons["reader.more"].waitForExistence(timeout: 5))
        XCTAssertEqual(page.frame, originalFrame)
        XCTAssertEqual(app.staticTexts["reader.title"].label, originalTitle)
        app.buttons["إغلاق المصحف"].tap()
        XCTAssertTrue(resume.waitForExistence(timeout: 10))
    }

    private func openSettings(_ app: XCUIApplication) {
        let settings = app.buttons["app.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10)); settings.tap()
        XCTAssertTrue(app.navigationBars["الإعدادات"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["settings.microphone.request"].exists)
        XCTAssertFalse(app.buttons["settings.microphone.open"].exists)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.exists && element.isHittable && app.frame.contains(element.frame) { break }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable && app.frame.contains(element.frame), app.debugDescription)
        XCTAssertGreaterThanOrEqual(element.frame.height, 44)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
}
