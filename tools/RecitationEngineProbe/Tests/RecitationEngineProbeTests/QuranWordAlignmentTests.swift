import XCTest
@testable import RecitationAlignment

final class QuranWordAlignmentTests: XCTestCase {
    func testFull6236VerseScriptBindsActualEditionAndRejectsChangedGlyph() async throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let script = try JSONDecoder().decode(QuranWordScript.self, from: Data(contentsOf:
            root.appendingPathComponent("content-sources/recitation-word-script.json")))
        let corpus = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf:
            root.appendingPathComponent("ios/Athar/quran.json"))) as? [[String: Any]])
        let keys = corpus.flatMap { surah -> [String] in
            let chapter = surah["number"] as! Int
            return (surah["ayahs"] as! [[String: Any]]).map { "\(chapter):\($0["number"] as! Int)" }
        }
        let (data, response) = try await URLSession.shared.data(from:
            URL(string: "https://noor-quran-sync.onrender.com/v1/mushaf/snapshot")!)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
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
        var damaged = native
        let first = damaged[0]
        damaged[0] = .init(id: first.id, verse: first.verse, position: first.position,
                          page: first.page, glyph: "wrong edition")
        XCTAssertThrowsError(try script.bind(native: damaged, verseKeys: keys))
    }
    func word(_ id: Int, _ forms: [[String]]) -> QuranAlignedWord {
        .init(id: id, verse: "112:1", page: 604, aliases: Set(forms))
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
