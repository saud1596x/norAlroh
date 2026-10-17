import XCTest
@testable import Athar

final class AdhkarReadingTests: XCTestCase {
    func testMorningAndEveningHaveIndependentContentAndCounters() throws {
        let content = try XCTUnwrap(AdhkarContent.shared)
        let morning = DhikrDayPeriod.morning.entries(in: content)
        let evening = DhikrDayPeriod.evening.entries(in: content)
        XCTAssertEqual(morning.count, 23)
        XCTAssertEqual(evening.count, 21)
        XCTAssertFalse(morning.contains { $0.id == "hisn-27-97" })
        XCTAssertFalse(evening.contains { ["hisn-27-93", "hisn-27-94", "hisn-27-95"].contains($0.id) })
        XCTAssertNotEqual(DhikrDayPeriod.morning.group(in: content).id, DhikrDayPeriod.evening.group(in: content).id)
        let night = try XCTUnwrap(evening.first { $0.id == "hisn-27-77" })
        let normalized = ArabicSearch.normalize(night.text)
        XCTAssertTrue(normalized.contains(ArabicSearch.normalize("أمسينا وأمسى")))
        XCTAssertTrue(normalized.contains(ArabicSearch.normalize("هذه الليلة")))
        XCTAssertFalse(normalized.contains("هذا اليوم"))
        for entry in morning + evening {
            XCTAssertFalse(entry.text.contains("["), entry.id)
            let original = try XCTUnwrap(content.entries.first { $0.id == entry.id })
            XCTAssertEqual(entry.reference, original.reference)
            XCTAssertEqual(entry.target, original.target)
        }
        let original = try XCTUnwrap(content.entries.first { $0.id == "hisn-27-77" })
        XCTAssertTrue(original.text.contains("["), "Original source remains available for auditing")
        XCTAssertEqual(DhikrReadingContent(entry: morning[0]).blocks.compactMap(\.quran).map(\.chapter), [2])
        XCTAssertEqual(DhikrReadingContent(entry: evening[1]).blocks.compactMap(\.quran).map(\.chapter), [112, 113, 114])
    }
    func testChapterSearchPrioritizesRequestedTitleAndPreservesFavorites() throws {
        let content = try XCTUnwrap(AdhkarContent.shared)
        XCTAssertEqual(content.searchGroups("النوم").first?.id, "hisn-28")
        XCTAssertEqual(content.searchGroups("أذكار النوم").first?.id, "hisn-28")
        XCTAssertEqual(content.searchGroups("النوم", favorites: ["hisn-1"]).map(\.id), ["hisn-1"])
        XCTAssertEqual(content.searchGroups("").map(\.id), content.groups.map(\.id))
        XCTAssertTrue(content.searchGroups("عبارة لا توجد في الأذكار مطلقا").isEmpty)
    }
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
