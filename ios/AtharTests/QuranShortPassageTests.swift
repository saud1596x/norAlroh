import XCTest
@testable import Athar

/// Injected word observations verify location policy, never ASR accuracy.
final class QuranShortPassageTests: XCTestCase {
    private func word(_ id: Int, _ verse: String, _ position: Int, _ count: Int,
                      _ text: String, initials: Bool = false) -> QuranAlignedWord {
        .init(id: id, verse: verse, page: 1, aliases: [[text]],
              requiresFollowingContext: initials, positionInVerse: position, wordsInVerse: count)
    }
    private var preceding: [QuranAlignedWord] {
        (1...30).map { word($0, "2:2", $0, 30, "فاصل") }
    }
    private func heard(_ words: [String], probability: Double = 0.98, offset: Double = 0) -> [QuranHeardWord] {
        words.enumerated().map { .init(text: $0.element, start: offset + Double($0.offset),
            end: offset + Double($0.offset) + 0.8, probability: probability) }
    }
    func testUniqueCompleteSingleWordAyahCanBeLocatedWithoutSelectingAnAyah() throws {
        var tracker = QuranRecitationTracker(expected: preceding + [word(51, "55:64", 1, 1, "مدهامتان")])
        let found = try tracker.consume(heard(["مدهامتان"]), takeID: UUID())
        XCTAssertEqual(found.map(\.nativeID), [51])
        XCTAssertEqual(found.map(\.verse), ["55:64"])
        XCTAssertEqual(tracker.revealedIDs, [51])
        XCTAssertEqual(found.first?.start, 0)
        XCTAssertEqual(found.first?.end, 0.8)
    }
    func testCompleteTwoWordAyahCanBeLocatedButDoesNotFillSkippedWords() throws {
        var tracker = QuranRecitationTracker(expected: preceding + [
            word(51, "112:2", 1, 2, "الله"), word(52, "112:2", 2, 2, "الصمد")])
        XCTAssertEqual(try tracker.consume(heard(["الله", "الصمد"]), takeID: UUID()).map(\.nativeID), [51, 52])
        XCTAssertEqual(tracker.revealedIDs, [51, 52])
    }
    func testSharedSingleWordInsideALongerAyahCannotSelectTheShortAyah() throws {
        var tracker = QuranRecitationTracker(expected: preceding + [
            word(51, "55:1", 1, 1, "الرحمن"),
            word(61, "1:1", 3, 4, "الرحمن"), word(62, "1:1", 4, 4, "الرحيم")])
        XCTAssertTrue(try tracker.consume(heard(["الرحمن"]), takeID: UUID()).isEmpty)
        XCTAssertTrue(tracker.evidence.isEmpty)
    }
    func testSharedTwoWordPrefixCompetesEvenWhenOnlyOneCopyIsACompleteAyah() throws {
        var tracker = QuranRecitationTracker(expected: preceding + [
            word(51, "1:3", 1, 2, "الرحمن"), word(52, "1:3", 2, 2, "الرحيم"),
            word(61, "1:1", 3, 4, "الرحمن"), word(62, "1:1", 4, 4, "الرحيم")])
        XCTAssertTrue(try tracker.consume(heard(["الرحمن", "الرحيم"]), takeID: UUID()).isEmpty)
        XCTAssertTrue(tracker.revealedIDs.isEmpty)
    }
    func testMultiTokenCompoundAlsoCompetesAgainstACompleteTwoGroupAyah() throws {
        let compound = QuranAlignedWord(id: 61, verse: "2:181", page: 1, aliases: [["بعد", "ما"]],
            positionInVerse: 3, wordsInVerse: 5)
        var tracker = QuranRecitationTracker(expected: preceding + [
            word(51, "test:short", 1, 2, "بعد"), word(52, "test:short", 2, 2, "ما"), compound])
        XCTAssertTrue(try tracker.consume(heard(["بعد", "ما"]), takeID: UUID()).isEmpty)
        XCTAssertTrue(tracker.evidence.isEmpty)
    }
    func testShortAyahStillRequiresStrongerConfidenceAndExactWholeWords() throws {
        let expected = preceding + [word(51, "55:64", 1, 1, "مدهامتان")]
        var weak = QuranRecitationTracker(expected: expected)
        XCTAssertTrue(try weak.consume(heard(["مدهامتان"], probability: 0.94), takeID: UUID()).isEmpty)
        XCTAssertTrue(try weak.consume(heard(["مدهامت"], probability: 0.99), takeID: UUID()).isEmpty)
        var two = QuranRecitationTracker(expected: preceding + [
            word(51, "112:2", 1, 2, "الله"), word(52, "112:2", 2, 2, "الصمد")])
        XCTAssertTrue(try two.consume(heard(["الله", "الصمد"], probability: 0.94), takeID: UUID()).isEmpty)
    }
    func testInitialsAndTruncatedVerseMetadataCannotCreateAShortAyahAnchor() throws {
        var initials = QuranRecitationTracker(expected: preceding + [word(51, "36:1", 1, 1, "يس", initials: true)])
        XCTAssertTrue(try initials.consume(heard(["يس"], probability: 0.999), takeID: UUID()).isEmpty)
        var tail = QuranRecitationTracker(expected: preceding + [
            word(51, "2:3", 2, 3, "مستقل"), word(52, "2:3", 3, 3, "اخير")])
        XCTAssertTrue(try tail.consume(heard(["مستقل", "اخير"]), takeID: UUID()).isEmpty)
        var unknown = QuranRecitationTracker(expected: preceding + [
            .init(id: 51, verse: "55:64", page: 1, aliases: [["مدهامتان"]])])
        XCTAssertTrue(try unknown.consume(heard(["مدهامتان"]), takeID: UUID()).isEmpty)
    }
    func testRetractedShortAyahDoesNotRemainEvidenceAndLaterRereadingKeepsItsOwnTimes() throws {
        var tracker = QuranRecitationTracker(expected: preceding + [word(51, "55:64", 1, 1, "مدهامتان")])
        let take = UUID()
        XCTAssertEqual(try tracker.consume(heard(["مدهامتان"]), takeID: take).count, 1)
        try tracker.reconsiderAudio(takeID: take, start: 0, end: 1)
        XCTAssertTrue(tracker.evidence.isEmpty)
        XCTAssertTrue(try tracker.consume(heard(["مدهامتان"], probability: 0.94, offset: 2), takeID: take).isEmpty)
        XCTAssertEqual(try tracker.consume(heard(["مدهامتان"], offset: 4), takeID: take).map(\.nativeID), [51])
        XCTAssertEqual(tracker.evidence.first?.start, 4)
        XCTAssertEqual(tracker.evidence.first?.end, 4.8)
        XCTAssertEqual(tracker.revealedIDs, [51])
    }
}
