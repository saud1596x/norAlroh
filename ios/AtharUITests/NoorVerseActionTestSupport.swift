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
        // Choose the physical direction from the actual target rectangle.
        // Blindly resetting four swipes left before searching right returns to
        // card five, never card six, at accessibility sizes. Retain the same
        // four-swipes-per-direction bound and all full-containment checks.
        var leftSwipes = 0, rightSwipes = 0
        while leftSwipes < 4 || rightSwipes < 4 {
            if ready() { return action }
            let bounds = action.frame, visible = panel.frame
            guard bounds.minX.isFinite, bounds.maxX.isFinite,
                  bounds.width > 0, bounds.width <= visible.width + 1 else { break }
            if bounds.minX < visible.minX - 0.5 {
                guard rightSwipes < 4 else { break }
                print("MUSHAF_ACTION_DRIVER_SWIPE target=\(identifier) direction=right targetMinX=\(bounds.minX) panelMinX=\(visible.minX)")
                rightSwipes += 1; panel.swipeRight()
            } else if bounds.maxX > visible.maxX + 0.5 {
                guard leftSwipes < 4 else { break }
                print("MUSHAF_ACTION_DRIVER_SWIPE target=\(identifier) direction=left targetMaxX=\(bounds.maxX) panelMaxX=\(visible.maxX)")
                leftSwipes += 1; panel.swipeLeft()
            } else {
                // A contained but non-hittable action is a real failure. Do
                // not hide an overlay or force a coordinate tap to bypass it.
                break
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
