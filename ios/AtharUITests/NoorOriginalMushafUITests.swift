import XCTest

/// Screenshots come from the launched app and real navigation, not canvas mocks.
final class NoorOriginalMushafUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testOriginal604FullReaderNavigationAndToolsDoNotMovePaper() {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 20))
        selectNoorTab("المصحف", in: app)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap(); search.typeText("١١٤")
        let surah = app.buttons["surah.114"]
        XCTAssertTrue(surah.waitForExistence(timeout: 10)); surah.tap()
        let paper = app.descendants(matching: .any).matching(identifier: "reader.page.ready").firstMatch
        XCTAssertTrue(paper.waitForExistence(timeout: 90))
        requirePage(604, in: app)
        capture(app, "KFGQPC-full-reader-page-604-tools-visible")
        let originalFrame = paper.frame
        paper.tap()
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !app.buttons["reader.jump"].isHittable
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 10), .completed)
        XCTAssertEqual(paper.frame, originalFrame, "Tools must not resize or move the paper")
        capture(app, "KFGQPC-full-reader-page-604-tools-hidden")
        paper.tap()
        XCTAssertTrue(app.buttons["reader.jump"].waitForExistence(timeout: 10))
        for number in [572, 598, 1] {
            app.buttons["reader.jump"].tap()
            let field = app.textFields["reader.pageNumber"]
            XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap()
            let existing = field.value as? String ?? ""
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
            field.typeText(String(number))
            app.buttons["انتقل"].tap()
            requirePage(number, in: app)
            XCTAssertTrue(paper.waitForExistence(timeout: 10))
            capture(app, String(format: "KFGQPC-full-reader-page-%03d", number))
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
