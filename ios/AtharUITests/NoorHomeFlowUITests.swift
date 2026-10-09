import XCTest

final class NoorHomeFlowUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws {
        if let run = testRun, run.failureCount > 0 { print("HOME_FLOW_FAILURE_HIERARCHY\n" + XCUIApplication().debugDescription) }
    }
    func testFourTabsAndVisibleOptionalAccountSurviveRelaunch() {
        let app = XCUIApplication(); launchNoorApp(app)
        for title in ["اليوم", "المصحف", "الصلاة", "الأذكار"] {
            XCTAssertTrue(app.tabBars.buttons[title].exists, title)
        }
        XCTAssertEqual(app.tabBars.buttons.count, 4)
        XCTAssertFalse(app.tabBars.buttons["الحفظ"].exists)
        let account = app.buttons["home.account"]
        XCTAssertTrue(account.waitForExistence(timeout: 10)); XCTAssertTrue(account.isHittable)
        XCTAssertGreaterThanOrEqual(account.frame.height, 44)
        XCTAssertTrue(app.frame.contains(account.frame))
        account.tap()
        XCTAssertTrue(app.navigationBars["حسابي"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["تسجيل الدخول اختياري. يمكنك حفظ نسخة من خطة الحفظ وتقدمك واستعادتها عند تغيير الجهاز."].exists)
        // This simulator build cannot pretend production Apple auth is enabled.
        XCTAssertTrue(app.staticTexts["الدخول بحساب Apple قيد التجهيز، ولم يُفعّل على هذه النسخة بعد."].exists)
        app.terminate(); launchNoorApp(app)
        XCTAssertTrue(account.waitForExistence(timeout: 10)); XCTAssertTrue(account.isHittable)
        XCTAssertTrue(app.buttons["home.resume"].exists)
    }
    func testReviewOpensScopeInMushafAndBookmarksPersistWithoutReflectionEditor() {
        let app = XCUIApplication(); launchNoorApp(app)
        let review = app.buttons["home.review"]
        reveal(review, app: app); review.tap()
        let closeScope = app.buttons["recitation.scope.close"]
        XCTAssertTrue(closeScope.waitForExistence(timeout: 120))
        XCTAssertGreaterThanOrEqual(closeScope.frame.height, 44)
        XCTAssertTrue(app.buttons["recitation.scope.start"].exists)
        XCTAssertTrue(app.segmentedControls["recitation.scope.kind"].exists)
        XCTAssertFalse(app.buttons["study.finish"].exists, "Opening review must not start a microphone session")
        closeScope.tap()
        let page = app.descendants(matching: .any).matching(identifier: "reader.page.ready").firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["study.finish"].exists)
        app.buttons["reader.jump"].tap()
        let field = app.textFields["reader.pageNumber"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("604")
        app.buttons["انتقل"].tap()
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !field.exists && !app.keyboards.firstMatch.exists && app.buttons["reader.jump"].isHittable
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 10), .completed)
        let verse = app.buttons["reader.verse.114:1"]
        XCTAssertTrue(verse.waitForExistence(timeout: 10)); verse.press(forDuration: 0.6)
        let bookmark = app.buttons["verse.bookmark"]
        XCTAssertTrue(bookmark.waitForExistence(timeout: 5))
        let alreadySaved = bookmark.label == "إزالة العلامة المرجعية"
        if !alreadySaved { bookmark.tap(); XCTAssertEqual(bookmark.label, "إزالة العلامة المرجعية") }
        // Long press opens inline selection tools. Bookmarking does not open
        // a modal; cancel the selection to reveal the reader's back button.
        let closeVerse = app.buttons["verse.tools.close"]
        XCTAssertTrue(closeVerse.waitForExistence(timeout: 5)); closeVerse.tap()
        XCTAssertFalse(bookmark.exists)
        let closeReader = app.buttons["إغلاق المصحف"]
        XCTAssertTrue(closeReader.waitForExistence(timeout: 5)); XCTAssertTrue(closeReader.isHittable)
        closeReader.tap()
        XCTAssertTrue(app.buttons["home.review"].waitForExistence(timeout: 10))
        let library = app.buttons["home.library"]
        reveal(library, app: app); library.tap()
        XCTAssertTrue(app.navigationBars["علاماتي"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.textViews["اكتب تأملك"].exists)
        XCTAssertFalse(app.buttons["احفظ تأملي"].exists)
        XCTAssertFalse(app.staticTexts["دفتر التأمل"].exists)
        XCTAssertTrue(app.buttons["library.bookmark.114:1"].exists)
        app.terminate(); launchNoorApp(app)
        reveal(library, app: app); library.tap()
        let saved = app.buttons["library.bookmark.114:1"]
        XCTAssertTrue(saved.waitForExistence(timeout: 10)); saved.tap()
        XCTAssertTrue(page.waitForExistence(timeout: 10))
        XCTAssertTrue(verse.waitForExistence(timeout: 10)); verse.press(forDuration: 0.6)
        XCTAssertTrue(bookmark.waitForExistence(timeout: 5)); XCTAssertEqual(bookmark.label, "إزالة العلامة المرجعية")
        if !alreadySaved { bookmark.tap(); XCTAssertEqual(bookmark.label, "إضافة علامة مرجعية") }
    }
    private func reveal(_ target: XCUIElement, app: XCUIApplication) {
        for _ in 0..<8 {
            if target.exists && target.isHittable && app.frame.contains(target.frame) && target.frame.maxY < app.tabBars.firstMatch.frame.minY { break }
            app.swipeUp()
        }
        XCTAssertTrue(target.exists && target.isHittable, app.debugDescription)
        XCTAssertGreaterThanOrEqual(target.frame.height, 44)
    }
}
