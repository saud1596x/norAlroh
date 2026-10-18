import XCTest
@testable import Athar

final class QuranObservedSpeechTests: XCTestCase {
    func testHourEquivalentObservationJournalPreservesEverySourceOccurrence() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = QuranRecitationJournal(root: root)
        var record = QuranRecitationRecord(keys: ["112:1"], originPage: 604)
        try journal.create(record)
        let take = QuranRecitationTake(startedAt: record.startedAt, frames: 57_600_000, closed: true)
        record.takes = [take]
        // Accelerated synthetic metadata only. This does not certify one hour
        // of physical capture, recognition, temperature, or learner accuracy.
        record.observedSpeech = (0..<1800).map { index in
            let start = Double(index * 2), end = min(3600, start + 8)
            let count = min(12, Int((end - start) / 0.4))
            var span = QuranObservedSpeech(takeID: take.id, start: start, end: end,
                words: Array(repeating: "قل", count: count), unresolved: false, backendID: "synthetic-load-test")
            span.evidenceVersion = 1; span.recognitionWindowID = UUID(); span.recognitionRevision = 0
            span.wordObservations = (0..<count).map { word in
                QuranObservedWord(occurrenceIndex: word, runIndex: 0, observedText: "قل",
                    startInTakeSeconds: start + Double(word) * 0.4,
                    endInTakeSeconds: start + Double(word) * 0.4 + 0.3,
                    backendConfidence: 0.9, recognitionState: "accepted", timingSource: "backend-word")
            }
            return span
        }
        let before = Date(); try journal.save(record)
        let saveSeconds = Date().timeIntervalSince(before)
        let loaded = try QuranRecitationJournal(root: root).load(record.id)
        XCTAssertEqual(loaded.observedSpeech, record.observedSpeech)
        XCTAssertEqual(loaded.duration, 3600)
        let size = try Data(contentsOf: root.appendingPathComponent(record.id.uuidString)
            .appendingPathComponent("recognized-session.json")).count
        print("SYNTHETIC_HOUR_JOURNAL windows=1800 bytes=\(size) saveMs=\(Int(saveSeconds * 1000)) source=generated-metadata-not-device-audio")
    }
    func testInputGuidanceUsesPCMAndDoesNotTreatSilenceOrBriefPeaksAsMistakes() {
        var quality = QuranInputQuality()
        XCTAssertTrue(quality.consume(Array(repeating: 0, count: 7999)).isEmpty)
        XCTAssertEqual(quality.consume([0]), [.noSignal])
        XCTAssertEqual(quality.consume(Array(repeating: 0.0001, count: 8000)), [.weak])
        let varying = (0..<8000).map { Float(sin(Double($0) * 0.1) * 0.1) }
        XCTAssertEqual(quality.consume(varying), [.present])
        var transient = varying; transient[0] = 1
        XCTAssertEqual(quality.consume(transient), [.present])
        XCTAssertEqual(quality.consume(Array(repeating: 1, count: 8000)), [.clipping])
        XCTAssertEqual(quality.consume(Array(repeating: -1, count: 8000)), [.clipping])
        XCTAssertTrue(quality.consume([.nan, .infinity]).isEmpty)
    }
    func testSignalFaultsCountActualCaptureFramesAndGuidanceRecoversAfterSustainedHealthyAudio() {
        var quality = QuranInputQuality()
        XCTAssertEqual(quality.consume(Array(repeating: 0.1, count: 8000)), [.frozenInput])
        let offset = (0..<8000).map { Float(0.15 + sin(Double($0) * 0.1) * 0.01) }
        XCTAssertEqual(quality.consume(offset), [.dcOffset])
        var malformed = Array(repeating: Float(0), count: 8000); malformed[5] = .nan
        XCTAssertEqual(quality.consume(malformed), [.invalidSignal])
        var guidance = QuranInputGuidance()
        guidance.consume(.frozenInput); XCTAssertNil(guidance.message)
        guidance.consume(.frozenInput); XCTAssertNotNil(guidance.message)
        guidance.consume(.present); XCTAssertNotNil(guidance.message)
        guidance.consume(.present); XCTAssertNotNil(guidance.message)
        guidance.consume(.present); XCTAssertNil(guidance.message)
        guidance.consume(.invalidSignal); XCTAssertNotNil(guidance.message)
        guidance = QuranInputGuidance(); XCTAssertNil(guidance.message, "A resumed take starts with fresh signal guidance")
        for _ in 0..<3 { guidance.consume(.noSignal); guidance.consume(.weak) }
        XCTAssertNotNil(guidance.message, "Alternating silence and weak input still form one sustained low-input condition")
    }
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
