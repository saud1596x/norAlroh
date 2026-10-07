import XCTest
@testable import Athar

final class ReadingSyncTests: XCTestCase {
    private let deviceA = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let deviceB = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    func testProgressSerializationIsStableAcrossSetInsertionOrdersAndLegacyDecode() throws {
        var a = MemorizationProgress(), b = MemorizationProgress()
        a.practiceDays["2026-10-7"] = Set(["1:1", "1:2", "1:3", "1:4"])
        b.practiceDays["2026-10-7"] = Set(["1:4", "1:3", "1:2", "1:1"])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(a)
        XCTAssertEqual(bytes, try encoder.encode(b))
        let legacy = Data(#"{"version":1,"verses":{},"practiceDays":{"2026-10-7":["1:4","1:1","1:3","1:2"]},"confirmedMistakes":[]}"#.utf8)
        let restored = try JSONDecoder().decode(MemorizationProgress.self, from: legacy)
        XCTAssertEqual(bytes, try encoder.encode(restored))
    }
    @MainActor func testNewDeviceDoesNotOverwriteRemotePositionPlanOrReadingSettingsWithDefaults() throws {
        let suite = "Noor.SyncDefaults." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let journal = NoorReadingSyncJournal(defaults: defaults)
        XCTAssertTrue(journal.setEnabled(true, owner: "alice", data: .init(), page: nil, plan: nil))
        let initial = try XCTUnwrap(journal.record?.state)
        XCTAssertNil(initial.page); XCTAssertNil(initial.plan); XCTAssertNil(initial.lowMotion); XCTAssertNil(initial.largeQuran)
        let stamp = NoorSyncStamp(date: Date().addingTimeInterval(-100), device: deviceB)
        var remote = NoorReadingCloudState()
        remote.page = .init(value: 604, stamp: stamp)
        remote.lowMotion = .init(value: true, stamp: stamp)
        remote.plan = .init(value: .init(chapter: 112, from: 1, to: 4, daily: 1), stamp: stamp)
        let merged = try NoorReadingCloudState.merge(initial, remote, corpus: XCTUnwrap(QuranResources.corpus))
        XCTAssertEqual(merged.page?.value, 604)
        XCTAssertEqual(merged.plan?.value.chapter, 112)
        XCTAssertEqual(merged.lowMotion?.value, true)
    }
    func testDeletionTombstoneSurvivesOldUploadsAndMergeIsCommutativeAndIdempotent() throws {
        let corpus = try XCTUnwrap(QuranResources.corpus)
        let old = NoorSyncStamp(date: Date(timeIntervalSince1970: 1700000000), device: deviceA)
        let newer = NoorSyncStamp(date: old.date.addingTimeInterval(10), device: deviceB)
        var a = NoorReadingCloudState(), b = NoorReadingCloudState()
        a.bookmarks["1:1"] = .init(value: true, stamp: old)
        a.page = .init(value: 560, stamp: old)
        b.bookmarks["1:1"] = .init(value: false, stamp: newer)
        b.bookmarks["114:6"] = .init(value: true, stamp: newer)
        b.page = .init(value: 604, stamp: newer)
        let first = try NoorReadingCloudState.merge(a, b, corpus: corpus)
        let reverse = try NoorReadingCloudState.merge(b, a, corpus: corpus)
        let staleRetry = try NoorReadingCloudState.merge(first, a, corpus: corpus)
        XCTAssertEqual(first.bookmarks["1:1"]?.value, false)
        XCTAssertEqual(first.bookmarks["114:6"]?.value, true)
        XCTAssertEqual(first.page?.value, 604)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        XCTAssertEqual(try encoder.encode(first), try encoder.encode(reverse))
        XCTAssertEqual(try encoder.encode(first), try encoder.encode(staleRetry))
    }
    func testConcurrentStampTieHasStableDeviceOrderAndConflictingSameStampIsRejected() throws {
        let corpus = try XCTUnwrap(QuranResources.corpus), date = Date()
        var a = NoorReadingCloudState(), b = NoorReadingCloudState()
        a.page = .init(value: 603, stamp: .init(date: date, device: deviceA))
        b.page = .init(value: 604, stamp: .init(date: date, device: deviceB))
        XCTAssertEqual(try NoorReadingCloudState.merge(a, b, corpus: corpus).page?.value, 604)
        b.page = .init(value: 604, stamp: a.page!.stamp)
        XCTAssertThrowsError(try NoorReadingCloudState.merge(a, b, corpus: corpus))
        b.page = .init(value: 605, stamp: .init(date: date, device: deviceB))
        XCTAssertThrowsError(try NoorReadingCloudState.merge(a, b, corpus: corpus))
        b.page = nil; b.bookmarks["1:01"] = .init(value: true, stamp: .init(date: date, device: deviceB))
        XCTAssertFalse(b.valid(corpus: corpus))
    }
    @MainActor func testOfflineDeletionPersistsAndAnotherAccountCannotAdoptOrEnableIt() throws {
        let suite = "Noor.Sync." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let journal = NoorReadingSyncJournal(defaults: defaults)
        var data = DeviceData(); data.bookmarks = ["1:1"]
        XCTAssertTrue(journal.setEnabled(true, owner: "alice", data: data, page: 560, plan: MemorizationPlan()))
        journal.pause(); data.bookmarks = []
        XCTAssertTrue(journal.capture(data: data, page: 603, plan: nil))
        let reopened = NoorReadingSyncJournal(defaults: defaults)
        XCTAssertFalse(reopened.enabled)
        XCTAssertEqual(reopened.record?.state.bookmarks["1:1"]?.value, false)
        XCTAssertEqual(reopened.record?.state.page?.value, 603)
        let bytes = reopened.exportBytes
        XCTAssertFalse(reopened.setEnabled(true, owner: "bob", data: data, page: 604, plan: MemorizationPlan()))
        XCTAssertFalse(reopened.adopt(.init(), owner: "bob"))
        XCTAssertEqual(reopened.exportBytes, bytes)
        XCTAssertTrue(reopened.setEnabled(true, owner: "alice", data: data, page: 603, plan: nil))
        XCTAssertEqual(reopened.record?.state.bookmarks["1:1"]?.value, false)
    }
    @MainActor func testDamagedJournalIsExportableAndCannotBeSilentlyOverwritten() throws {
        let suite = "Noor.SyncRecovery." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let damaged = Data("damaged sync record".utf8); defaults.set(damaged, forKey: "noor.sync.journal.v1")
        let journal = NoorReadingSyncJournal(defaults: defaults)
        XCTAssertEqual(journal.unreadable, damaged)
        XCTAssertFalse(journal.setEnabled(true, owner: "alice", data: .init(), page: 1, plan: MemorizationPlan()))
        XCTAssertEqual(journal.exportBytes, damaged)
        journal.erase()
        XCTAssertTrue(journal.setEnabled(true, owner: "alice", data: .init(), page: 1, plan: nil))
    }
    @MainActor func testSyncedPlanCannotDiscardAnActiveLocalSession() throws {
        let suite = "Noor.SyncPlan." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let corpus = try XCTUnwrap(QuranResources.corpus), store = MemorizationStore(defaults: defaults)
        XCTAssertTrue(store.configure(.init(chapter: 1, from: 1, to: 7, daily: 2), corpus: corpus))
        XCTAssertTrue(store.saveSession(.init(chapter: 1, keys: [1, 2])))
        let before = defaults.data(forKey: "noor.memorization.session")
        XCTAssertFalse(store.applySyncedPlan(.init(chapter: 112, from: 1, to: 4, daily: 1)))
        XCTAssertEqual(defaults.data(forKey: "noor.memorization.session"), before)
        XCTAssertEqual(store.plan.chapter, 1)
        store.clearSession()
        XCTAssertTrue(store.applySyncedPlan(.init(chapter: 112, from: 1, to: 4, daily: 1)))
        XCTAssertEqual(MemorizationStore(defaults: defaults).plan.chapter, 112)
    }
    @MainActor func testExcludedRecognitionNoteSurvivesRestartAndStaleCloudRestore() throws {
        let suite = "Noor.SyncExclusion." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let corpus = try XCTUnwrap(QuranResources.corpus), store = MemorizationStore(defaults: defaults)
        let expected = try XCTUnwrap(corpus.first?.ayahs.first?.text.split(whereSeparator: \.isWhitespace).first)
        XCTAssertTrue(store.confirmMistake(chapter: 1, ayah: 1, expected: String(expected), heard: nil))
        let note = try XCTUnwrap(store.progress.confirmedMistakes.first)
        let stale = MemorizationCloudBackup(version: 1, plan: store.plan,
            archive: .init(version: 1, history: store.history, progress: store.progress, plan: store.plan))
        XCTAssertTrue(store.saveSession(.init(chapter: 1, keys: [1, 2])))
        let session = defaults.data(forKey: "noor.memorization.session"), ward = store.completedToday()
        XCTAssertTrue(store.excludeMistake(note.id))
        XCTAssertFalse(store.excludeMistake(note.id))
        XCTAssertEqual(store.completedToday(), ward)
        let reopened = MemorizationStore(defaults: defaults)
        XCTAssertTrue(reopened.progress.confirmedMistakes.isEmpty)
        XCTAssertTrue(reopened.progress.excludedMistakeIDs.contains(note.id))
        XCTAssertTrue(reopened.restore(stale))
        XCTAssertTrue(reopened.progress.confirmedMistakes.isEmpty)
        XCTAssertTrue(reopened.progress.excludedMistakeIDs.contains(note.id))
        XCTAssertEqual(defaults.data(forKey: "noor.memorization.session"), session)
        let local = MemorizationCloudBackup(version: 1, plan: reopened.plan,
            archive: .init(version: 1, history: reopened.history, progress: reopened.progress, plan: reopened.plan))
        let reverse = try MemorizationCloudMerge.merge(local: stale, remote: local, corpus: corpus)
        XCTAssertTrue(reverse.archive.progress.confirmedMistakes.isEmpty)
        XCTAssertTrue(reverse.archive.progress.excludedMistakeIDs.contains(note.id))
    }

}
