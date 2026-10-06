import XCTest

/// Screenshots come from the launched app and real navigation, not canvas mocks.
final class NoorMushafPageNavigationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testText604NavigationAndToolsDoNotMoveCanvas() {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 20))
        selectNoorTab("المصحف", in: app)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap(); search.typeText("١١٤")
        let surah = app.buttons["surah.114"]
        XCTAssertTrue(surah.waitForExistence(timeout: 10)); surah.tap()
        let viewport = app.descendants(matching: .any).matching(identifier: "reader.page.ready").firstMatch
        XCTAssertTrue(viewport.waitForExistence(timeout: 90))
        requirePage(604, in: app)
        capture(app, "native-text-reader-page-604-tools-visible")
        let originalFrame = viewport.frame
        viewport.coordinate(withNormalizedOffset: CGVector(dx: 0.002, dy: 0.03)).tap()
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !app.buttons["reader.jump"].exists || !app.buttons["reader.jump"].isHittable
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 10), .completed)
        XCTAssertEqual(viewport.frame, originalFrame, "Tools must not resize or move the viewport")
        capture(app, "native-text-reader-page-604-tools-hidden")
        viewport.coordinate(withNormalizedOffset: CGVector(dx: 0.002, dy: 0.03)).tap()
        XCTAssertTrue(app.buttons["reader.jump"].waitForExistence(timeout: 10))
        for number in [572, 598, 1, 2, 3, 151, 48] {
            app.buttons["reader.jump"].tap()
            let field = app.textFields["reader.pageNumber"]
            XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap()
            let pageInput = number == 598 ? "٥٩٨" : String(number)
            field.typeText(pageInput)
            XCTAssertEqual(field.value as? String, pageInput, "Page input must not append the previous page")
            app.buttons["انتقل"].tap()
            requirePage(number, in: app)
            XCTAssertTrue(viewport.waitForExistence(timeout: 10))
            capture(app, String(format: "native-text-reader-page-%03d", number))
            if number == 48 {
                let debtVerse = app.buttons["reader.verse.2:282"]
                XCTAssertTrue(debtVerse.waitForExistence(timeout: 10)); debtVerse.tap()
                XCTAssertTrue(app.buttons["verse.tafsir"].waitForExistence(timeout: 10))
                let title = app.staticTexts["verse.tools.title"]
                XCTAssertTrue(title.waitForExistence(timeout: 10))
                let digits = title.label.compactMap { $0.wholeNumberValue }
                XCTAssertEqual(digits.reduce(0) { $0 * 10 + $1 }, 282)
                capture(app, "native-text-reader-page-048-long-ayah-selected")
                app.buttons["verse.tools.close"].tap()
            }
        }
    }
    private func requirePage(_ number: Int, in app: XCUIApplication) {
        let counter = app.buttons["reader.jump"]
        XCTAssertTrue(counter.waitForExistence(timeout: 10))
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let prefix = counter.label.split(separator: "/").first ?? ""
            let digits = prefix.compactMap { $0.wholeNumberValue }
            return !digits.isEmpty && digits.reduce(0, { $0 * 10 + $1 }) == number
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 15), .completed, "Wrong actual reader page")
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
