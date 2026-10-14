import XCTest
@testable import Athar

final class QuranObservedSpeechTests: XCTestCase {
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
