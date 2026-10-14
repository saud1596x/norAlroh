import XCTest
@testable import Athar

final class QuranObservedSpeechTests: XCTestCase {
    func testWordTimingConfidenceAndRepeatedOccurrencesSurviveJournalRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = QuranRecitationJournal(root: root)
        var record = QuranRecitationRecord(keys: ["112:1"], originPage: 604)
        let take = QuranRecitationTake(startedAt: record.startedAt, frames: 64_000, closed: true)
        record.takes = [take]
        var span = QuranObservedSpeech(takeID: take.id, start: 0, end: 4,
                                      words: ["قل", "قل"], unresolved: true, backendID: "test")
        span.evidenceVersion = 1; span.recognitionWindowID = UUID(); span.recognitionRevision = 0
        span.wordObservations = [
            .init(occurrenceIndex: 0, runIndex: 0, observedText: "قل", startInTakeSeconds: 0.2,
                  endInTakeSeconds: 0.7, backendConfidence: 0.9, recognitionState: "accepted", timingSource: "backend-word"),
            .init(occurrenceIndex: 1, runIndex: 1, observedText: "قل", startInTakeSeconds: 2,
                  endInTakeSeconds: 2.5, backendConfidence: nil, recognitionState: "unassessable", timingSource: "backend-word")
        ]
        record.observedSpeech = [span]
        try journal.create(record)
        let loaded = try journal.load(record.id)
        XCTAssertEqual(loaded.observedSpeech, [span])
        XCTAssertEqual(loaded.observedSpeech?.first?.wordObservations?.count, 2, "A later repetition is a separate acoustic occurrence")
        var invalidSpan = span
        invalidSpan.wordObservations = [.init(occurrenceIndex: 0, runIndex: 0, observedText: "قل",
            startInTakeSeconds: 3.5, endInTakeSeconds: 4.5, backendConfidence: 0.9,
            recognitionState: "accepted", timingSource: "backend-word")]
        record.observedSpeech = [invalidSpan]
        XCTAssertThrowsError(try journal.save(record))
        XCTAssertEqual(try journal.load(record.id).observedSpeech, [span])
    }
    func testObservedWordsRemainSeparateFromReferenceAndSurviveReopening() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = QuranRecitationJournal(root: root)
        var record = QuranRecitationRecord(keys: ["112:1"], originPage: 604)
        try journal.create(record)
        let take = QuranRecitationTake(startedAt: record.startedAt, frames: 64_000, closed: true)
        record.takes = [take]
        record.observedSpeech = [.init(takeID: take.id, start: 0, end: 4,
                                      words: ["كلام", "مختلف"], unresolved: true, backendID: "test")]
        try journal.save(record)
        let reopened = try QuranRecitationJournal(root: root).load(record.id)
        XCTAssertEqual(reopened.observedSpeech, record.observedSpeech)
        XCTAssertTrue(reopened.evidence.isEmpty, "Observed words must not become reference progress without alignment")
        var invalid = record
        invalid.observedSpeech = [.init(takeID: UUID(), start: 0, end: 4,
                                       words: ["كلام"], unresolved: false, backendID: "test")]
        XCTAssertThrowsError(try journal.save(invalid))
        invalid.observedSpeech = [.init(takeID: take.id, start: 3, end: 5,
                                       words: ["كلام"], unresolved: false, backendID: "test")]
        XCTAssertThrowsError(try journal.save(invalid), "Recognized speech cannot extend beyond captured audio")
        XCTAssertEqual(try journal.load(record.id).observedSpeech, record.observedSpeech)
    }

    func testLegacyRecordWithoutObservedSpeechStillLoads() throws {
        let record = QuranRecitationRecord(keys: ["1:1"], originPage: 1)
        let encoded = try JSONEncoder().encode(record)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "observedSpeech")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let loaded = try JSONDecoder().decode(QuranRecitationRecord.self, from: legacy)
        try loaded.validate()
        XCTAssertEqual(loaded.id, record.id)
        XCTAssertNil(loaded.observedSpeech)
    }
}
