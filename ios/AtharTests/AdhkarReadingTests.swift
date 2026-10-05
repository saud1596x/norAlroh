import XCTest
@testable import Athar

final class AdhkarReadingTests: XCTestCase {
    func testEverySourceCharacterRemainsAvailableAfterSplitting() throws {
        let content = try XCTUnwrap(AdhkarContent.shared)
        for entry in content.entries {
            XCTAssertEqual(DhikrReadingContent(entry: entry).originalReassembled, entry.text, entry.id)
        }
    }
    func testMorningOrderAndShortSurahsAreSeparateAndCanonical() throws {
        let content = try XCTUnwrap(AdhkarContent.shared)
        let morning = try XCTUnwrap(content.groups.first { $0.id == "hisn-27" })
        let entries = content.entries(in: morning)
        XCTAssertEqual(DhikrReadingContent(entry: entries[0]).title, "آية الكرسي")
        let surahs = DhikrReadingContent(entry: entries[1]).blocks.compactMap(\.quran)
        XCTAssertEqual(surahs.map(\.chapter), [112, 113, 114])
        XCTAssertEqual(surahs.map(\.to), [4, 5, 6])
        let seven = try XCTUnwrap(entries.first { $0.id == "hisn-27-83" })
        XCTAssertEqual(seven.target, 1, "The raw source field is preserved for auditing.")
        XCTAssertEqual(DhikrReadingContent(entry: seven).counterEntry.target, 7, "Use the explicit count written in the source text.")
    }
}
