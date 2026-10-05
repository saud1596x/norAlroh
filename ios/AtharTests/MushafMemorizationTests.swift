import XCTest
@testable import Athar

final class MushafMemorizationTests: XCTestCase {
    func testAllPagesHaveCanonicalVerseEndCoverageAndCorrectHeaders() throws {
        let database = try XCTUnwrap(MushafDatabase.shared)
        XCTAssertEqual(database.pages.map(\.page), Array(1...604))
        XCTAssertEqual(database.chapterPages.count, 114)
        XCTAssertEqual(database.juzPages.count, 30)
        let ends = database.pages.flatMap { $0.words.filter { $0.kind == "end" }.map(\.key) }
        XCTAssertEqual(ends.count, 6236)
        XCTAssertEqual(Set(ends).count, 6236)
        let corpus = try XCTUnwrap(QuranResources.corpus)
        XCTAssertEqual(ends, corpus.flatMap { s in s.ayahs.map { "\(s.number):\($0.number)" } })
        XCTAssertTrue(database.isValid(corpus: corpus))
        XCTAssertEqual(MushafDatabase.headers.count, 114)
        XCTAssertEqual(MushafDatabase.headers[0], 0xFC45)
        XCTAssertEqual(MushafDatabase.headers[13], 0xFC5A)
        let tawbah = try XCTUnwrap(database.pages.first { $0.page == 187 })
        XCTAssertFalse(tawbah.layout.values.contains { $0.type == "bismillah" })
        let last = try XCTUnwrap(database.pages.last)
        XCTAssertEqual(Set(last.layout.values.compactMap(\.chapter)), Set([112, 113, 114]))
    }
    func testChangedReligiousResourceIsRejected() throws {
        var bytes = try XCTUnwrap(QuranResources.data("quran"))
        bytes.append(0)
        XCTAssertFalse(QuranResources.verified(bytes, resource: "quran.json"))
        XCTAssertFalse(QuranResources.verified(Data(), resource: "unknown.ttf"))
    }
    @MainActor func testOpeningVerseDoesNotDoubleCountUnnumberedBasmala() throws {
        let corpus = AtharStore().quran
        let fatiha = try XCTUnwrap(corpus.first)
        XCTAssertEqual(QuranText.verse(chapter: 1, ayah: fatiha.ayahs[0]), QuranText.basmala)
        for chapter in [2, 3, 67, 95, 97, 114] {
            let text = QuranText.verse(chapter: chapter, ayah: corpus[chapter - 1].ayahs[0])
            XCTAssertFalse(text.hasPrefix(QuranText.basmala))
            XCTAssertFalse(text.isEmpty)
        }
    }
    @MainActor func testPlanRangeValidationPersistenceAndErase() throws {
        let suite = "NoorMemorizationTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let corpus = AtharStore().quran
        let store = MemorizationStore(defaults: defaults)
        XCTAssertFalse(store.configure(.init(chapter: 2, from: 286, to: 285, daily: 3), corpus: corpus))
        XCTAssertFalse(store.configure(.init(chapter: 114, from: 1, to: 7, daily: 3), corpus: corpus))
        XCTAssertTrue(store.configure(.init(chapter: 67, from: 1, to: 5, daily: 3), corpus: corpus))
        store.finish(chapter: 67, answers: [.init(ayah: 1, assessment: "review", revealed: true, hints: 1)])
        let reopened = MemorizationStore(defaults: defaults)
        XCTAssertEqual(reopened.plan.chapter, 67)
        XCTAssertEqual(reopened.history.first?.answers.first?.assessment, "review")
        XCTAssertEqual(reopened.history.first?.answers.first?.hints, 1)
        reopened.erase()
        let empty = MemorizationStore(defaults: defaults)
        XCTAssertEqual(empty.plan.chapter, 1)
        XCTAssertTrue(empty.history.isEmpty)
    }
}
