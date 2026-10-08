import XCTest
import RecitationAlignment
import RecitationSessions

final class QuranRecitationJournalTests: XCTestCase {
    func testNewJournalRetainsTimedEvidenceAcrossReopeningAndRejectsCorruptReplacement() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = QuranRecitationJournal(root: root)
        var record = QuranRecitationRecord(keys: ["112:1"], originPage: 604)
        try journal.create(record)
        let take = QuranRecitationTake(startedAt: record.startedAt, frames: 64_000, closed: true)
        record.takes = [take]
        var tracker = QuranRecitationTracker(expected: [
            .init(id: 1, verse: "112:1", page: 604, aliases: [["قل"]]),
            .init(id: 2, verse: "112:1", page: 604, aliases: [["هو"]])
        ])
        try tracker.consume([.init(text: "قل", start: 0.2, end: 0.8, probability: 0.9),
                             .init(text: "هو", start: 0.9, end: 1.3, probability: 0.9)], takeID: take.id)
        record.evidence = tracker.evidence
        record.recognitionUnavailable = true // A later inference failure retains prior evidence.
        try journal.save(record)
        let reopened = try QuranRecitationJournal(root: root).load(record.id)
        XCTAssertEqual(reopened.evidence, tracker.evidence)
        XCTAssertEqual(reopened.takes, [take])
        XCTAssertEqual(reopened.duration, 4)
        XCTAssertTrue(reopened.recognitionUnavailable)
        XCTAssertThrowsError(try journal.create(record))
        var invalid = record; invalid.takes = []
        XCTAssertThrowsError(try journal.save(invalid), "Evidence cannot point to absent audio")
        XCTAssertEqual(try journal.load(record.id).evidence, record.evidence)
        let file = journal.folder(record.id).appendingPathComponent("recognized-session.json")
        let damaged = Data("incomplete".utf8)
        try damaged.write(to: file)
        XCTAssertThrowsError(try journal.load(record.id))
        XCTAssertThrowsError(try journal.save(record), "Do not overwrite unreadable history")
        XCTAssertEqual(try Data(contentsOf: file), damaged)
    }
    func testAnUnclosedTakeCannotBePresentedAsFinishedOrPaused() throws {
        var record = QuranRecitationRecord(keys: ["114:1"], originPage: 604)
        record.takes = [.init(startedAt: record.startedAt, frames: 16_000)]
        XCTAssertThrowsError(try record.validate())
        record.phase = .recording
        XCTAssertNoThrow(try record.validate())
        record.phase = .finished; record.finishedAt = record.startedAt.addingTimeInterval(2)
        XCTAssertThrowsError(try record.validate())
        record.takes[0].closed = true
        XCTAssertNoThrow(try record.validate())
    }
}
