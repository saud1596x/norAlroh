import XCTest
@testable import Athar

final class NoorRemovedFeatureRetentionTests: XCTestCase {
    @MainActor func testPersonalReflectionNotesAndBookmarksStillReopenAfterFeatureRetirement() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = AtharStore(directory: directory)
        let text = "تأمل شخصي — الإخلاص، الآية 1\nملاحظة محفوظة قبل إزالة القسم."
        let note = JournalNote(text: text)
        XCTAssertTrue(original.update { $0.notes = [note]; $0.bookmarks = ["112:1", "114:6"]; $0.lowMotion = true })
        let reopened = AtharStore(directory: directory)
        XCTAssertEqual(reopened.data.notes.first?.id, note.id)
        XCTAssertEqual(reopened.data.notes.first?.text, text)
        XCTAssertEqual(reopened.data.bookmarks, ["112:1", "114:6"])
        XCTAssertTrue(reopened.data.lowMotion)
        XCTAssertTrue(reopened.update { $0.largeQuran = true })
        XCTAssertEqual(AtharStore(directory: directory).data.notes.first?.text, text)
    }
}
