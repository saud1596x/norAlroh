import XCTest
import UIKit

final class NoorReaderComfortUITests: XCTestCase {
    func testPage14LargeDynamicTypeControlsDoNotCoverVerses() {
        let app = XCUIApplication(); acceptanceApp = app
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        launchNoorApp(app)
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 20))
        app.buttons["home.resume"].tap()
        let page = app.descendants(matching: .any).matching(identifier: "reader.page.ready").firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 120))
        jump(14, app: app)
        requireStableReadingLayout(app, page: page, landscape: false)
        let title = app.staticTexts["reader.title"]
        XCTAssertGreaterThan(title.frame.height, 44, "The test must exercise an actually enlarged header")
        let footer = ["reader.study", "reader.jump", "reader.next", "reader.previous"].map { app.buttons[$0] }
        XCTAssertTrue(footer.allSatisfy { $0.exists && $0.isHittable })
        XCTAssertFalse(app.buttons["reader.study"].frame.intersects(app.buttons["reader.jump"].frame),
            "The enlarged page counter must not cover the microphone")
        let footerTop = footer.map { $0.frame.minY }.min() ?? app.frame.maxY
        for ayah in 89...93 {
            let verse = app.buttons["reader.verse.2:\(ayah)"]
            XCTAssertTrue(verse.exists)
            XCTAssertTrue(app.frame.contains(verse.frame), "Every reference verse must remain fully onscreen")
            XCTAssertGreaterThanOrEqual(verse.frame.minY, title.frame.maxY - 1, "The enlarged header must not cover Quran ink")
            XCTAssertLessThanOrEqual(verse.frame.maxY, footerTop + 1, "The enlarged footer must not cover Quran ink")
        }
        XCTAssertFalse(app.buttons["reader.fullscreen"].exists)
        capture(app, "user-reference-page14-accessibility-text-controls")
    }
    func testUserReferencePage14IsCenteredAndFullyVisible() {
        let app = XCUIApplication(); acceptanceApp = app; launchNoorApp(app)
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 20))
        app.buttons["home.resume"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "reader.page.ready").firstMatch.waitForExistence(timeout: 120))
        jump(14, app: app)
        let first = app.buttons["reader.verse.2:89"]
        let last = app.buttons["reader.verse.2:93"]
        XCTAssertTrue(first.waitForExistence(timeout: 20))
        XCTAssertTrue(last.exists)
        XCTAssertTrue(app.frame.contains(first.frame), "Reference page must not crop its first verse")
        XCTAssertTrue(app.frame.contains(last.frame), "Reference page must not crop its last verse")
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        XCTAssertFalse(app.navigationBars.firstMatch.exists)
        XCTAssertFalse(app.buttons["reader.fullscreen"].exists)
        capture(app, "user-reference-balanced-page-14")
    }
    func testReaderOpensFullscreenAutomaticallyWithBalancedMicrophone() {
        let app = XCUIApplication(); launchNoorApp(app)
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 20))
        app.buttons["home.resume"].tap()
        let page = app.descendants(matching: .any).matching(identifier: "reader.page.ready").firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 120))
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        XCTAssertFalse(app.buttons["reader.fullscreen"].exists)
        XCTAssertFalse(app.navigationBars.firstMatch.exists)
        let mic = app.buttons["reader.study"]
        XCTAssertGreaterThanOrEqual(mic.frame.width, 60)
        XCTAssertEqual(mic.frame.midX, app.frame.midX, accuracy: 2)
        XCTAssertTrue(mic.isHittable)
        XCTAssertTrue(app.frame.contains(page.frame))
        capture(app, "automatic-fullscreen-reader")
    }
    private var screenshotBackground: UInt32?
    private var acceptanceApp: XCUIApplication?
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }
    override func tearDownWithError() throws {
        if let run = testRun, run.failureCount > 0, let app = acceptanceApp {
            print("READER_ACCEPTANCE_FAILURE_HIERARCHY\n" + app.debugDescription)
        }
        XCUIDevice.shared.orientation = .portrait
    }
    func testPageToolsGesturesAndRelaunchPreservePosition() {
        let app = XCUIApplication(); acceptanceApp = app; launchNoorApp(app)
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 20))
        app.buttons["home.resume"].tap()
        let page = app.descendants(matching: .any).matching(identifier: "reader.page.ready").firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 120))
        jump(604, app: app)
        let verse = app.buttons["reader.verse.114:1"]
        XCTAssertTrue(verse.waitForExistence(timeout: 20))
        let frame = verse.frame
        requireTools(true, app: app)
        XCTAssertTrue(app.buttons["reader.study"].isHittable)
        XCTAssertTrue(app.buttons["reader.khatmah"].isHittable)
        app.buttons["reader.khatmah"].tap()
        XCTAssertTrue(app.staticTexts["رحلة الختمة"].waitForExistence(timeout: 10))
        app.buttons["إغلاق"].tap()
        XCTAssertTrue(app.buttons["reader.study"].waitForExistence(timeout: 10))
        XCTAssertEqual(verse.frame, frame, "Closing journey must preserve reader geometry")
        capture(app, "stage1-604-tools-visible")
        // A tap on Quran ink, not just a margin, toggles tools without selection.
        verse.tap()
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            // A missing control must be queried by existence. Resolving
            // isHittable on an unmounted element blocks with XCTest retries.
            !app.buttons["reader.jump"].exists
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
        let verseToolsVisible = app.buttons["verse.tafsir"].waitForExistence(timeout: 5)
        if !verseToolsVisible {
            // Preserve the real interface hierarchy to distinguish hit testing
            // from an inaccessible action bar. Do not relax the acceptance gate.
            print("INLINE_VERSE_ACTIONS_FAILURE_HIERARCHY\n" + app.debugDescription)
        }
        XCTAssertTrue(verseToolsVisible)
        XCTAssertEqual(verse.frame, frame, "Selection must preserve the exact Quran ink position")
        for id in ["verse.tafsir", "verse.play", "verse.repeat", "verse.bookmark", "verse.hifz"] {
            let action = app.buttons[id]
            XCTAssertTrue(action.isHittable, id)
            XCTAssertGreaterThanOrEqual(action.frame.width, 44, id)
            XCTAssertGreaterThanOrEqual(action.frame.height, 44, id)
            XCTAssertFalse(action.frame.intersects(verse.frame), "Actions must not cover the selected verse: \(id)")
        }
        capture(app, "stage2-604-inline-verse-actions")
        let bookmark = app.buttons["verse.bookmark"]
        let originalBookmark = bookmark.label
        bookmark.tap()
        XCTAssertNotEqual(bookmark.label, originalBookmark)
        bookmark.tap()
        XCTAssertEqual(bookmark.label, originalBookmark, "Keep the user's original bookmark state")
        app.buttons["verse.repeat"].tap()
        XCTAssertTrue(app.buttons["verse.repeat.start"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "verse.sheet.close").count, 1)
        app.buttons["verse.sheet.close"].tap()
        XCTAssertTrue(app.buttons["reader.jump"].waitForExistence(timeout: 5))
        verse.press(forDuration: 0.6)
        verse.tap()
        XCTAssertFalse(app.buttons["verse.tafsir"].exists, "A normal tap cancels selection")
        XCTAssertTrue(app.buttons["reader.jump"].exists)
        XCTAssertEqual(verse.frame, frame)
        page.pinch(withScale: 1.6, velocity: 1)
        page.swipeLeft()
        requirePage(604, app: app)
        capture(app, "stage1-604-zoom-pan")
        jump(151, app: app)
        capture(app, "stage1-151-centered")
        app.terminate(); launchNoorApp(app)
        XCTAssertTrue(app.buttons["home.resume"].waitForExistence(timeout: 20))
        app.buttons["home.resume"].tap()
        XCTAssertTrue(page.waitForExistence(timeout: 10))
        requirePage(151, app: app)
        capture(app, "stage1-151-restored-after-relaunch")
        XCUIDevice.shared.orientation = .landscapeLeft
        requireStableReadingLayout(app, page: page, landscape: true)
        requirePage(151, app: app)
        requireTools(true, app: app)
        capture(app, "stage1-151-landscape")
        let landscapeFrame = page.frame
        let landscapeVerse = app.buttons["reader.verse.7:1"]
        let landscapeVerseFrame = landscapeVerse.frame
        landscapeVerse.press(forDuration: 0.6)
        XCTAssertTrue(app.buttons["verse.tafsir"].waitForExistence(timeout: 5))
        XCTAssertEqual(landscapeVerse.frame, landscapeVerseFrame)
        XCTAssertEqual(page.frame, landscapeFrame)
        for id in ["verse.tafsir", "verse.play", "verse.repeat", "verse.bookmark", "verse.hifz"] {
            XCTAssertTrue(app.buttons[id].isHittable, id)
            XCTAssertFalse(app.buttons[id].frame.intersects(landscapeVerse.frame), id)
        }
        capture(app, "stage2-151-landscape-verse-actions")
        app.buttons["verse.tools.close"].tap()
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
            let control = app.buttons["reader.jump"]
            return visible ? control.exists && control.isHittable : !control.exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 5), .completed)
        if visible {
            XCTAssertGreaterThanOrEqual(app.buttons["reader.jump"].frame.height, 44 - 0.000001,
                                        "The actual page-counter hit label must remain at least 44 points")
            let page = app.descendants(matching: .any).matching(identifier: "reader.page.ready").firstMatch
            XCTAssertEqual(app.buttons["reader.study"].frame.midX, page.frame.midX, accuracy: 1,
                           "The primary microphone and reading viewport must share one center")
            XCTAssertTrue(app.frame.contains(app.buttons["reader.jump"].frame),
                          "The relocated page counter must remain fully accessible")
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
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let counter = app.buttons["reader.jump"]
            return !field.exists && !app.keyboards.firstMatch.exists && counter.exists && counter.isHittable
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 10), .completed,
                       "Page navigation must dismiss its sheet and keyboard before reader interaction resumes")
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
        // Capture the physical screen, not an application's cropped coordinate
        // region after rotation. Keep the original screenshot bytes as evidence.
        let screen = XCUIScreen.main.screenshot()
        let shot = XCTAttachment(screenshot: screen)
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
        if let bitmap = screen.image.cgImage {
            let quarterTurn: Bool
            switch screen.image.imageOrientation {
            case .left, .leftMirrored, .right, .rightMirrored: quarterTurn = true
            default: quarterTurn = false
            }
            let landscape = quarterTurn ? bitmap.height > bitmap.width : bitmap.width > bitmap.height
            XCTAssertEqual(landscape, app.frame.width > app.frame.height,
                           "Screenshot orientation must match the settled reader")
        } else { XCTFail("Missing screenshot bitmap") }
        requireCompleteScreenshot(screen, name: name)
    }
    private func requireCompleteScreenshot(_ screenshot: XCUIScreenshot, name: String) {
        guard let image = screenshot.image.cgImage else { XCTFail("Missing screenshot bitmap: \(name)"); return }
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        var colors: [UInt32: Int] = [:]
        bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            let pixels = buffer.bindMemory(to: UInt8.self)
            for y in stride(from: 0, to: height, by: 8) { for x in stride(from: 0, to: width, by: 8) {
                let offset = (y * width + x) * 4
                let color = UInt32(pixels[offset]) << 16 | UInt32(pixels[offset + 1]) << 8 | UInt32(pixels[offset + 2])
                colors[color, default: 0] += 1
            } }
        }
        guard let dominant = colors.max(by: { $0.value < $1.value })?.key else { XCTFail("Unreadable screenshot: \(name)"); return }
        // Use the first reader's actual background, including dark appearance.
        // A large black region or cropped off-screen window must fail acceptance.
        let reference = screenshotBackground ?? dominant
        screenshotBackground = reference
        let samples = colors.values.reduce(0, +)
        let fraction = Double(colors[reference, default: 0]) / Double(samples)
        XCTAssertGreaterThan(fraction, 0.75, "Incomplete screen capture \(name): reader background occupies only \(fraction)")
    }
}
