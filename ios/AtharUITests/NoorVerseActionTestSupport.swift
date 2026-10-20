import XCTest
import UIKit

private enum NoorVerseActionLookupFailure: Error { case missingPanel, missingAction, unreachableAction }

extension XCTestCase {
    /// Reveal an actual action through its horizontal ScrollView. This does
    /// not force a coordinate tap or change application state to expose it.
    func revealNoorVerseAction(_ identifier: String, in app: XCUIApplication,
                              file: StaticString = #filePath, line: UInt = #line) throws -> XCUIElement {
        let panel = app.scrollViews["verse.actions.panel"].firstMatch
        guard panel.waitForExistence(timeout: 5) else {
            XCTFail("Missing actual horizontal verse action panel", file: file, line: line)
            throw NoorVerseActionLookupFailure.missingPanel
        }
        let action = app.buttons[identifier]
        guard action.waitForExistence(timeout: 5) else {
            XCTFail("Missing verse action: \(identifier)", file: file, line: line)
            throw NoorVerseActionLookupFailure.missingAction
        }
        func ready() -> Bool {
            guard panel.exists, action.exists else { return false }
            let bounds = action.frame
            guard bounds.minX.isFinite, bounds.minY.isFinite, bounds.width > 0, bounds.height > 0,
                  app.frame.contains(bounds), panel.frame.insetBy(dx: -0.5, dy: -0.5).contains(bounds) else { return false }
            return action.isHittable
        }
        if ready() { return action }
        // Search both directions: the app is RTL and previous actions can leave
        // the strip at either end. Never scroll the surrounding Quran viewport.
        for swipeLeft in [true, false] {
            for _ in 0..<4 {
                if ready() { return action }
                if swipeLeft { panel.swipeLeft() } else { panel.swipeRight() }
            }
        }
        if ready() { return action }
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "unreachable-verse-action-\(identifier)"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        XCTFail("Verse action must be fully visible and hittable after at most four swipes per direction: \(identifier)",
                file: file, line: line)
        throw NoorVerseActionLookupFailure.unreachableAction
    }
}
