import XCTest
@testable import Athar

final class QuranLiveStoragePolicyTests: XCTestCase {
    func testUpgradeDeletesOnlyLearnerRecordingsAndExpiredWorkspaces() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("Support"), caches = root.appendingPathComponent("Caches")
        let discarded = ["Support/NoorMushafRecordings/old.caf", "Support/NoorRecitation/latest-recitation.m4a",
                         "Caches/NoorLiveRecitation/previous/session.caf"]
        let retained = ["Support/bookmarks.json", "Support/khatmah.json", "Support/account.json",
                        "Caches/reciters/surah.mp3", "Caches/NoorLiveRecitation/current/session.caf"]
        let original = Data([1, 5, 9, 21])
        for name in discarded + retained {
            let file = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try original.write(to: file)
        }
        try QuranLiveRecitationStorage.removePreviousRecordings(support: support, caches: caches, keepingProcess: "current")
        for name in discarded { XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path), name) }
        for name in retained { XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(name)), original, name) }
    }

    func testDisposedSessionCannotBeResurrectedByLateAnalysisAndDoesNotEraseAnotherSession() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = QuranRecitationJournal(root: root)
        let first = QuranRecitationRecord(keys: ["112:1"], originPage: 604)
        let second = QuranRecitationRecord(keys: ["1:2"], originPage: 1)
        try journal.create(first); try journal.create(second)
        let original = Data([2, 3, 4])
        try original.write(to: journal.audio(session: first.id, take: UUID()))
        try journal.discard(first.id)
        XCTAssertThrowsError(try journal.saveAnalysis(first))
        XCTAssertThrowsError(try journal.save(first))
        XCTAssertFalse(FileManager.default.fileExists(atPath: journal.folder(first.id).path))
        XCTAssertEqual(try journal.load(second.id).keys, second.keys)
        XCTAssertNoThrow(try journal.discard(first.id), "Repeated close is harmless")
    }

}
