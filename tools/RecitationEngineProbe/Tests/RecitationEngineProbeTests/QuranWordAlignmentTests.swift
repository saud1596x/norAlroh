import XCTest
import CryptoKit
#if canImport(Athar)
@testable import Athar
#else
@testable import RecitationAlignment
#endif

final class QuranWordAlignmentTests: XCTestCase {
    func testFull6236VerseScriptBindsActualEditionAndRejectsChangedGlyph() async throws {
        #if canImport(Athar)
        let scriptURL = try XCTUnwrap(Bundle.main.url(forResource: "recitation-word-script", withExtension: "json"))
        let corpusURL = try XCTUnwrap(Bundle.main.url(forResource: "quran", withExtension: "json"))
        let data = try XCTUnwrap(QCFV2ContentCache.bundledSnapshot())
        #else
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let scriptURL = root.appendingPathComponent("content-sources/recitation-word-script.json")
        let corpusURL = root.appendingPathComponent("ios/Athar/quran.json")
        let data = try Data(contentsOf: root.appendingPathComponent("ios/Athar/mushaf-snapshot.json"))
        #endif
        let script = try JSONDecoder().decode(QuranWordScript.self, from: Data(contentsOf:
            scriptURL))
        let corpus = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf:
            corpusURL)) as? [[String: Any]])
        let keys = corpus.flatMap { surah -> [String] in
            let chapter = surah["number"] as! Int
            return (surah["ayahs"] as! [[String: Any]]).map { "\(chapter):\($0["number"] as! Int)" }
        }
        XCTAssertEqual(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
                       "125af9666b7166070782d6a7ab77fc5bb7926f3286a42374c5a540ae681abd7d")
        let snapshot = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(snapshot["resource_id"] as? Int, 1)
        XCTAssertEqual(snapshot["resource_content_id"] as? Int, 382)
        let records = try XCTUnwrap(snapshot["records"] as? [[String: Any]])
        let native = records.filter { $0["record_type"] as? String == "mushaf_word"
            && $0["char_type_name"] as? String == "word" }.map { item in
                QuranNativeWord(id: item["id"] as! Int, verse: keys[(item["verse_id"] as! Int) - 1],
                    position: item["position_in_verse"] as! Int, page: item["page_number"] as! Int,
                    glyph: item["text"] as! String)
            }
        let bound = try script.bind(native: native, verseKeys: keys)
        XCTAssertEqual(bound.count, 77429)
        XCTAssertEqual(Set(bound.map(\.verse)).count, 6236)
        XCTAssertTrue(bound.filter { $0.verse == "1:1" }[2].aliases.contains(["الرحمن"]))
        XCTAssertTrue(bound.filter { $0.verse == "1:1" }[2].aliases.contains(["الرحمان"]))
        XCTAssertTrue(bound.filter { $0.verse == "114:3" }[0].aliases.contains(["اله"]))
        for (key, position) in [("2:181", 3), ("8:6", 4), ("13:37", 8)] {
            let word = bound.filter { $0.verse == key }[position - 1]
            XCTAssertTrue(word.aliases.contains(["بعد", "ما"]))
        }
        XCTAssertTrue(bound.filter { $0.verse == "37:130" }[2].aliases.contains(["ال", "ياسين"]))
        XCTAssertTrue(bound.filter { $0.verse == "2:1" }[0].aliases.contains(["الف", "لام", "ميم"]))
        XCTAssertTrue(bound.filter { $0.verse == "2:1" }[0].requiresFollowingContext)
        XCTAssertTrue(bound.filter { $0.verse == "19:1" }[0].aliases.contains(["كاف", "ها", "يا", "عين", "صاد"]))
        XCTAssertFalse(bound.filter { $0.verse == "36:31" }[0].aliases.contains(["الف", "لام", "ميم"]))
        var damaged = native
        let first = damaged[0]
        damaged[0] = .init(id: first.id, verse: first.verse, position: first.position,
                          page: first.page, glyph: "wrong edition")
        XCTAssertThrowsError(try script.bind(native: damaged, verseKeys: keys))
    }
    func word(_ id: Int, _ forms: [[String]]) -> QuranAlignedWord {
        .init(id: id, verse: "112:1", page: 604, aliases: Set(forms))
    }
    func testSpokenInitialsNeedCompleteOrderedNamesAndCannotChooseASharedOpening() throws {
        let forms = try QuranSpokenInitials.forms(verse: "2:1", position: 1, canonical: ["الٓمٓ"])
        XCTAssertEqual(forms, [["الف","لام","ميم"], ["الفلام","ميم"], ["الف","لامميم"], ["الفلامميم"]])
        XCTAssertTrue(try QuranSpokenInitials.forms(verse: "36:31", position: 1, canonical: ["أَلَمْ"]).isEmpty)
        XCTAssertTrue(try QuranSpokenInitials.forms(verse: "2:1", position: 2, canonical: ["الم"]).isEmpty)
        XCTAssertThrowsError(try QuranSpokenInitials.forms(verse: "2:1", position: 1, canonical: ["الر"]))
        let opening = QuranAlignedWord(id: 1, verse: "2:1", page: 2, aliases: forms.union([["الم"]]), requiresFollowingContext: true)
        let repeated = QuranAlignedWord(id: 50, verse: "3:1", page: 50, aliases: forms, requiresFollowingContext: true)
        var ambiguous = QuranRecitationTracker(expected: [opening, repeated])
        XCTAssertTrue(try ambiguous.consume(heard(["ألف","لام","ميم"]), takeID: UUID()).isEmpty)
        var scope = QuranRecitationTracker(expected: [opening])
        let take = UUID()
        XCTAssertTrue(try scope.consume(heard(["ألف","ميم"]), takeID: take).isEmpty)
        XCTAssertTrue(try scope.consume(heard(["ميم","لام","ألف"]), takeID: take).isEmpty)
        let actual = ["ألف","لام","ميم"].enumerated().map {
            QuranHeardWord(text: $0.element, start: Double($0.offset), end: Double($0.offset)+0.8, probability: 0.99)
        }
        XCTAssertTrue(try scope.consume(actual, takeID: take).isEmpty)
        XCTAssertTrue(try scope.consume([.init(text: "الم", start: 0, end: 0.8, probability: 0.999)], takeID: take).isEmpty)
        var context = QuranRecitationTracker(expected: [opening,
            .init(id: 2, verse: "2:2", page: 2, aliases: [["ذلك"]]),
            .init(id: 3, verse: "2:2", page: 2, aliases: [["الكتاب"]])])
        XCTAssertEqual(try context.consume(actual + heard(["ذلك","الكتاب"],offset: 3), takeID: take).map(\.nativeID), [1,2,3])
        XCTAssertEqual(context.evidence[0].start, 0)
        XCTAssertEqual(context.evidence[0].end, 2.8)
    }
    func heard(_ tokens: [String], offset: Double = 0) -> [QuranHeardWord] {
        tokens.enumerated().map { .init(text: $0.element, start: offset + Double($0.offset),
                                       end: offset + Double($0.offset) + 0.8, probability: 0.9) }
    }
    func testRealAnchorsKeepRepetitionAndBacktrackingWithTakeTimes() throws {
        let words = [word(1, [["قل"]]), word(2, [["هو"]]), word(3, [["الله"]]), word(4, [["احد"]])]
        var tracker = QuranRecitationTracker(expected: words)
        let take = UUID()
        XCTAssertEqual(try tracker.consume(heard(["قل", "هو", "الله", "أحد"]), takeID: take).count, 4)
        XCTAssertEqual(tracker.cursor, 4)
        XCTAssertEqual(try tracker.consume(heard(["قل", "هو", "الله", "أحد"]), takeID: take).count, 0)
        XCTAssertEqual(try tracker.consume(heard(["قل", "هو"], offset: 8), takeID: take).count, 2)
        XCTAssertEqual(tracker.cursor, 2)
        XCTAssertEqual(tracker.evidence.count, 6)
        XCTAssertEqual(tracker.evidence.last?.start, 9)
        XCTAssertEqual(tracker.revealedIDs, Set([1, 2, 3, 4]))
        let bytes = try JSONEncoder().encode(tracker.evidence)
        let saved = try JSONDecoder().decode([QuranWordEvidence].self, from: bytes)
        var restored = try QuranRecitationTracker(expected: words, restoring: saved)
        XCTAssertEqual(restored.cursor, 2)
        XCTAssertEqual(restored.evidence, tracker.evidence)
        XCTAssertEqual(try restored.consume(heard(["قل", "هو"], offset: 8), takeID: take).count, 0)
        XCTAssertEqual(try restored.consume(heard(["الله", "أحد"]), takeID: UUID()).count, 2)
        XCTAssertThrowsError(try QuranRecitationTracker(expected: [word(900, [["قل"]])], restoring: saved))
    }
    func testCompoundNeedsBothWordsAndDoesNotShiftFollowingIDs() throws {
        var tracker = QuranRecitationTracker(expected: [word(71, [["بعد", "ما"]]),
            word(99, [["سمعه"]]), word(103, [["فانما"]])])
        let take = UUID()
        XCTAssertTrue(try tracker.consume(heard(["بعد"]), takeID: take).isEmpty)
        XCTAssertTrue(tracker.revealedIDs.isEmpty)
        XCTAssertEqual(try tracker.consume(heard(["بعد", "ما", "سمعه"]), takeID: take).map(\.nativeID), [71, 99])
        XCTAssertEqual(tracker.evidence.first?.end, 1.8)
        XCTAssertFalse(tracker.revealedIDs.contains(103))
    }
    func testSingleGroupScopeRequiresItsFullFormAndStrongerConfidence() throws {
        // Alignment inputs are explicit unit-test evidence, not live ASR.
        var tracker = QuranRecitationTracker(expected: [
            .init(id: 51, verse: "55:64", page: 533, aliases: [["مدهامتان"]])
        ])
        let take = UUID()
        XCTAssertTrue(try tracker.consume([.init(text: "مدهامتان", start: 0, end: 1, probability: 0.94)], takeID: take).isEmpty)
        XCTAssertTrue(try tracker.consume([.init(text: "مدهامت", start: 0, end: 1, probability: 0.99)], takeID: take).isEmpty)
        XCTAssertEqual(try tracker.consume([.init(text: "مدهامتان", start: 0, end: 1, probability: 0.97)], takeID: take).map(\.nativeID), [51])
        XCTAssertEqual(tracker.evidence.first?.minimumConfidence, 0.97)
        var compound = QuranRecitationTracker(expected: [word(71, [["بعد", "ما"]])])
        XCTAssertTrue(try compound.consume([.init(text: "بعد", start: 0, end: 1, probability: 0.99)], takeID: take).isEmpty)
        XCTAssertEqual(try compound.consume([
            .init(text: "بعد", start: 0, end: 1, probability: 0.99),
            .init(text: "ما", start: 1, end: 2, probability: 0.99)
        ], takeID: take).map(\.nativeID), [71])
        var multiple = QuranRecitationTracker(expected: [word(1, [["الله"]]), word(2, [["الصمد"]])])
        XCTAssertTrue(try multiple.consume([.init(text: "الله", start: 0, end: 1, probability: 0.99)], takeID: take).isEmpty)
    }
    func testDistantReturnNeedsUniqueLongAnchorAndDoesNotRevealSkippedText() throws {
        let words = [word(1, [["قل"]]), word(2, [["هو"]]), word(3, [["الله"]])]
            + (4...30).map { word($0, [["فاصل"]]) }
            + [word(31, [["من"]]), word(32, [["شر"]]), word(33, [["الوسواس"]])]
        var tracker = QuranRecitationTracker(expected: words)
        let take = UUID()
        XCTAssertTrue(try tracker.consume(heard(["من", "شر"]), takeID: take).isEmpty)
        XCTAssertEqual(try tracker.consume(heard(["من", "شر", "الوسواس"]), takeID: take).map(\.nativeID), [31, 32, 33])
        XCTAssertEqual(tracker.revealedIDs, [31, 32, 33])
        XCTAssertEqual(try tracker.consume(heard(["قل", "هو", "الله"], offset: 10), takeID: take).map(\.nativeID), [1, 2, 3])
        XCTAssertEqual(tracker.cursor, 3)
        XCTAssertFalse(tracker.revealedIDs.contains(15))
    }
    func testRetractedAudioCannotLeaveAStaleShortAnchorPrior() throws {
        let words = (1...30).map { word($0, [["فاصل"]]) }
            + [word(31, [["من"]]), word(32, [["شر"]]), word(33, [["الوسواس"]])]
        var tracker = QuranRecitationTracker(expected: words)
        let take = UUID()
        XCTAssertEqual(try tracker.consume(heard(["من","شر","الوسواس"]), takeID:take).count,3)
        try tracker.reconsiderAudio(takeID:take, start:0, end:4)
        XCTAssertTrue(tracker.evidence.isEmpty)
        XCTAssertEqual(tracker.cursor,0)
        XCTAssertTrue(try tracker.consume(heard(["من","شر"], offset:5), takeID:take).isEmpty)
    }
    func testAmbiguousCommonPhraseAndWrongWordStayUnresolved() throws {
        var tracker = QuranRecitationTracker(expected: [word(1, [["الله"]]), word(2, [["الصمد"]]),
            word(3, [["الله"]]), word(4, [["الصمد"]])])
        XCTAssertTrue(try tracker.consume(heard(["الله", "الصمد"]), takeID: UUID()).isEmpty)
        XCTAssertTrue(try tracker.consume(heard(["الله", "نار"]), takeID: UUID()).isEmpty)
        XCTAssertEqual(tracker.cursor, 0)
        XCTAssertTrue(tracker.evidence.isEmpty)
        XCTAssertNotEqual(QuranAlignedWord.normalize("ناس"), QuranAlignedWord.normalize("نار"))
        XCTAssertNotEqual(QuranAlignedWord.normalize("نور"), QuranAlignedWord.normalize("نار"))
    }
    func testLowConfidenceInvalidTimesAndPauseDoNotCreateProgress() throws {
        var tracker = QuranRecitationTracker(expected: [word(1, [["قل"]]), word(2, [["هو"]])])
        XCTAssertThrowsError(try tracker.consume([.init(text: "قل", start: 0, end: 1, probability: 0.4)], takeID: UUID()))
        XCTAssertThrowsError(try tracker.consume([.init(text: "قل", start: .nan, end: 1, probability: 0.9)], takeID: UUID()))
        XCTAssertTrue(try tracker.consume([.init(text: "قل", start: 0, end: 1, probability: 0.9),
            .init(text: "هو", start: 5, end: 6, probability: 0.9)], takeID: UUID()).isEmpty)
        XCTAssertTrue(tracker.evidence.isEmpty)
    }
    func testBothAuthoritativeSpellingsWithoutFuzzyMatching() throws {
        var tracker = QuranRecitationTracker(expected: [word(1, [["الرحمان"], ["الرحمن"]]), word(2, [["الرحيم"]])])
        XCTAssertEqual(try tracker.consume(heard(["ٱلرَّحْمَٰنِ", "ٱلرَّحِيمِ"]), takeID: UUID()).count, 2)
    }
}
