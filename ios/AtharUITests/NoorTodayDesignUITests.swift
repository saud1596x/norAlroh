import XCTest

// Original Simulator screenshots of real SwiftUI components. Fixture data is
// explicit; these tests never install widgets, seed progress or assert a live
// prayer time. The last three cases exercise the actual production Today view.
final class NoorTodayDesignUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 120
    }
    override func tearDownWithError() throws {
        if let run = testRun, run.failureCount > 0 {
            let app = XCUIApplication()
            print("NOOR_DESIGN_FAILURE_HIERARCHY\n" + app.debugDescription)
            let image = XCTAttachment(screenshot: app.screenshot())
            image.name = "design-failure-original"; image.lifetime = .keepAlways; add(image)
        }
        XCUIApplication().terminate()
    }

    @MainActor func testLinearLightComposition() { captureFixture("linear-light") }
    @MainActor func testEditorialLightComposition() { captureFixture("editorial-light") }
    @MainActor func testNajdiLightComposition() { captureFixture("najdi-light") }
    @MainActor func testNajdiDarkComposition() { captureFixture("najdi-dark") }
    @MainActor func testNajdiAccessibilityComposition() { captureFixture("najdi-ax") }
    @MainActor func testProductionTodayLight() { captureProduction("light") }
    @MainActor func testProductionTodayDark() { captureProduction("dark") }
    @MainActor func testProductionTodayAccessibility() { captureProduction("ax") }

    @MainActor private func launch(_ state: String, mediumDua: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-NoorAcceptanceDesignCase", state]
        if mediumDua { app.launchArguments.append("-NoorAcceptanceDesignMediumDua") }
        app.launch()
        let traits = element("design.actualTraits", app: app)
        XCTAssertTrue(traits.waitForExistence(timeout: 20), app.debugDescription)
        let actual = traits.value as? String ?? ""
        XCTAssertTrue(actual.contains("scheme=\(state.contains("dark") ? "dark" : "light")"), actual)
        XCTAssertTrue(actual.contains("accessibility=\(state.hasSuffix("ax"))"), actual)
        XCTAssertTrue(actual.contains("rtl=true"), actual)
        return app
    }
    @MainActor private func captureFixture(_ state: String) {
        let prefix = "design-fixture-\(state)"
        var app = launch(state)
        let account = element("design.account", app: app)
        reveal(account, app: app)
        capture(app, prefix + "-today-top", synthetic: true)
        assertContained(account, app: app)
        let reading = element("design.reading.action", app: app)
        reveal(reading, app: app); assertContained(reading, app: app)
        let prayer = element("design.prayer", app: app)
        reveal(prayer, app: app)
        capture(app, prefix + "-today-prayer", synthetic: true)
        assertContained(prayer, app: app)
        app.terminate()

        app = launch(state, mediumDua: true)
        let card = element("design.mediumDua", app: app)
        reveal(card, app: app)
        capture(app, prefix + "-medium-dua", synthetic: true)
        assertContained(card, app: app)
        let geometry = element("design.dua.geometry", app: app)
        XCTAssertTrue(geometry.waitForExistence(timeout: 5), "Missing actual Text/card anchors")
        let measured = geometry.value as? String ?? ""
        print("NOOR_DESIGN_DUA_BOUNDS case=\(state) \(measured)")
        XCTAssertTrue(measured.contains("textFits=true;"), "Full Quran text overflows: " + measured)
        XCTAssertTrue(measured.contains("componentFits=true;"), "Component overflows fixed medium card: " + measured)
    }
    @MainActor private func captureProduction(_ state: String) {
        let app = launch("production-" + state)
        let prefix = "design-production-" + state
        let account = app.buttons["home.account"]
        XCTAssertTrue(account.waitForExistence(timeout: 20), app.debugDescription)
        reveal(account, app: app)
        capture(app, prefix + "-today-top", synthetic: false)
        assertContained(account, app: app)
        XCTAssertGreaterThanOrEqual(account.frame.height, 44)
        let reading = app.buttons["home.continueKhatmah"].exists ? app.buttons["home.continueKhatmah"] : app.buttons["home.resume"]
        if reading.exists {
            reveal(reading, app: app); assertContained(reading, app: app)
            XCTAssertGreaterThanOrEqual(reading.frame.height, 44)
        } else {
            XCTAssertTrue(app.staticTexts["أتممت ورد اليوم"].exists, "No production reading state")
        }
        let prayer = app.buttons["home.prayers"]
        reveal(prayer, app: app)
        capture(app, prefix + "-today-prayer", synthetic: false)
        assertContained(prayer, app: app)
        XCTAssertGreaterThanOrEqual(prayer.frame.height, 44)
        let dua = app.buttons["home.dua"]
        reveal(dua, app: app)
        capture(app, prefix + "-today-dua", synthetic: false)
        assertContained(dua, app: app)
        XCTAssertGreaterThanOrEqual(dua.frame.height, 44)
        // Merely inspecting Today must not complete a ward or start reading.
        XCTAssertFalse(app.buttons["reader.study"].exists)
    }
    @MainActor private func element(_ id: String, app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    @MainActor private func viewport(_ app: XCUIApplication) -> CGRect {
        let scroll = app.scrollViews.firstMatch
        let frame = scroll.exists ? app.frame.intersection(scroll.frame) : app.frame
        let top = app.navigationBars.firstMatch.exists ? max(frame.minY, app.navigationBars.firstMatch.frame.maxY) : frame.minY
        let bottom = app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY : frame.maxY
        return CGRect(x: frame.minX, y: top, width: frame.width, height: max(0, min(bottom, frame.maxY) - top))
    }
    @MainActor private func reveal(_ target: XCUIElement, app: XCUIApplication) {
        XCTAssertTrue(target.waitForExistence(timeout: 10), app.debugDescription)
        for _ in 0..<8 {
            let visible = viewport(app)
            if visible.contains(target.frame), target.frame.height > 0 { return }
            if target.frame.midY < visible.midY { app.swipeDown() } else { app.swipeUp() }
        }
        assertContained(target, app: app)
    }
    @MainActor private func assertContained(_ target: XCUIElement, app: XCUIApplication) {
        XCTAssertGreaterThan(target.frame.width, 0)
        XCTAssertGreaterThan(target.frame.height, 0)
        XCTAssertTrue(viewport(app).contains(target.frame), "Clipped/covered element \(target.identifier): \(target.frame)")
        if target.elementType == .button { XCTAssertTrue(target.isHittable, target.identifier) }
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String, synthetic: Bool) {
        print("NOOR_DESIGN_SCREEN scope=\(synthetic ? "SYNTHETIC_DESIGN_DATA" : "PRODUCTION_TODAY_REAL_STATE") name=\(name)")
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
}
