import XCTest
@testable import Athar

final class MushafStudySessionTests: XCTestCase {
    private func corpus() throws -> [Surah] { try XCTUnwrap(QuranResources.corpus) }
    private func isolated() throws -> (String, UserDefaults) {
        let suite = "Noor.InlineStudy." + UUID().uuidString
        return (suite, try XCTUnwrap(UserDefaults(suiteName: suite)))
    }
    func testCanonicalRangeSupportsEntireQuranAndRejectsGapsAliasesAndInvalidAssistance() throws {
        let Quran = try corpus()
        let keys = Quran.flatMap { s in s.ayahs.map { "\(s.number):\($0.number)" } }
        XCTAssertEqual(keys.count, 6236)
        XCTAssertTrue(MushafStudySession(keys: keys, scope: .range).valid(corpus: Quran))
        for invalid in [["1:1", "1:1"], ["1:1", "1:3"], ["01:1"], ["1:0"], ["114:7"], ["1:2", "1:1"]] {
            XCTAssertFalse(MushafStudySession(keys: invalid, scope: .range).valid(corpus: Quran))
        }
        var session = MushafStudySession(keys: ["1:1"], scope: .range)
        session.assistance.visibleWords = 1
        XCTAssertFalse(session.valid(corpus: Quran), "Revealed text must carry a persisted help record")
    }
    @MainActor func testCrossSurahPracticePreservesLegacyPlanSessionsAndPartialResultsAcrossRelaunch() throws {
        let (suite, defaults) = try isolated(); defer { defaults.removePersistentDomain(forName: suite) }
        let store = MemorizationStore(defaults: defaults)
        XCTAssertTrue(store.configure(.init(chapter: 67, from: 1, to: 5, daily: 3), corpus: try corpus()))
        XCTAssertTrue(store.saveSession(.init(chapter: 1, keys: [1, 2, 3])))
        XCTAssertTrue(store.savePractice(.init(chapter: 67, from: 1, to: 5, ayah: 2)))
        let retained = ["plan", "session", "practice"].map { defaults.data(forKey: "noor.memorization." + $0) }
        XCTAssertTrue(store.startMushafStudy(keys: ["112:4", "113:1", "113:2"], scope: .page, page: 604))
        XCTAssertTrue(store.updateMushafStudy { $0.reveal(wordCount: 3, all: false) })
        let reopened = MemorizationStore(defaults: defaults)
        XCTAssertEqual(reopened.mushafStudy.pending?.assistance.visibleWords, 1)
        XCTAssertTrue(reopened.updateMushafStudy { $0.answer("remembered") })
        XCTAssertFalse(reopened.updateMushafStudy { $0.recordAudioHelp(for: "112:4") }, "Stale playback cannot count for the new verse")
        XCTAssertTrue(reopened.updateMushafStudy { $0.recordAudioHelp(for: "113:1") })
        XCTAssertTrue(reopened.updateMushafStudy { $0.answer("review") })
        XCTAssertTrue(reopened.finishMushafStudy())
        let finished = MemorizationStore(defaults: defaults)
        XCTAssertNil(finished.mushafStudy.pending)
        XCTAssertEqual(finished.mushafStudy.summary?.answered, 2)
        XCTAssertEqual(finished.mushafStudy.summary?.session.keys.count, 3)
        XCTAssertEqual(finished.history.count, 2)
        XCTAssertEqual(finished.progress.verses["112:4"]?.attempts, 1)
        XCTAssertEqual(finished.progress.verses["112:4"]?.needsHelp, true)
        XCTAssertEqual(finished.progress.verses["113:1"]?.needsHelp, true)
        XCTAssertNil(finished.progress.verses["113:2"], "Ending early cannot invent an attempt for unread verses")
        XCTAssertEqual(retained, ["plan", "session", "practice"].map { defaults.data(forKey: "noor.memorization." + $0) })
    }
    @MainActor func testInterruptedFinalizationRetriesWithoutDuplicateHistoryOrProgress() throws {
        let (suite, defaults) = try isolated(); defer { defaults.removePersistentDomain(forName: suite) }
        let store = MemorizationStore(defaults: defaults)
        XCTAssertTrue(store.startMushafStudy(keys: ["1:1", "1:2"], scope: .range))
        XCTAssertTrue(store.updateMushafStudy { $0.answer("remembered") })
        XCTAssertTrue(store.updateMushafStudy {
            $0.phase = .finishing; $0.finishedAt = $0.startedAt.addingTimeInterval(60); return true
        })
        let pendingBytes = try XCTUnwrap(defaults.data(forKey: "noor.mushaf.study"))
        XCTAssertTrue(store.finishMushafStudy())
        let results = store.history
        // Recreate the exact durable state of a crash after the result archive
        // write and before the pending-session clear.
        defaults.set(pendingBytes, forKey: "noor.mushaf.study")
        let reopened = MemorizationStore(defaults: defaults)
        XCTAssertTrue(reopened.finishMushafStudy(at: Date().addingTimeInterval(300)))
        XCTAssertEqual(reopened.history, results)
        XCTAssertEqual(reopened.progress.verses["1:1"]?.attempts, 1)
        XCTAssertNil(reopened.mushafStudy.pending)
    }
    @MainActor func testConflictingResultIDIsRejectedWithoutReplacingExistingUserHistory() throws {
        let (suite, defaults) = try isolated(); defer { defaults.removePersistentDomain(forName: suite) }
        let store = MemorizationStore(defaults: defaults)
        XCTAssertTrue(store.startMushafStudy(keys: ["1:1"], scope: .range))
        XCTAssertTrue(store.updateMushafStudy { $0.answer("remembered") })
        XCTAssertTrue(store.updateMushafStudy {
            $0.phase = .finishing; $0.finishedAt = $0.startedAt.addingTimeInterval(60); return true
        })
        let result = try XCTUnwrap(store.mushafStudy.pending?.results()?.first)
        let conflict = MemorizationResult(id: result.id, date: result.date, chapter: 1,
            answers: [.init(ayah: 1, assessment: "review", revealed: true, hints: 1)])
        var progress = MemorizationProgress(); progress.record(conflict)
        let original = try JSONEncoder().encode(MemorizationArchive(version: 1, history: [conflict], progress: progress))
        defaults.set(original, forKey: "noor.memorization.archive")
        let reopened = MemorizationStore(defaults: defaults)
        XCTAssertFalse(reopened.finishMushafStudy())
        XCTAssertEqual(defaults.data(forKey: "noor.memorization.archive"), original)
        XCTAssertEqual(reopened.history, [conflict]); XCTAssertNotNil(reopened.mushafStudy.pending)
    }
    @MainActor func testCorruptSessionBytesRemainAvailableAndCannotBeOverwritten() throws {
        let (suite, defaults) = try isolated(); defer { defaults.removePersistentDomain(forName: suite) }
        let bytes = Data("previous unreadable session".utf8)
        defaults.set(bytes, forKey: "noor.mushaf.study")
        let store = MemorizationStore(defaults: defaults)
        XCTAssertEqual(store.unreadableMushafStudy, bytes)
        XCTAssertFalse(store.startMushafStudy(keys: ["1:1"], scope: .range))
        XCTAssertEqual(defaults.data(forKey: "noor.mushaf.study"), bytes)
        store.erase()
        XCTAssertNil(MemorizationStore(defaults: defaults).unreadableMushafStudy)
    }
    @MainActor func testPauseAndExistingSessionPreventUnexpectedHelpAnswersAndPlanReplacement() throws {
        let (suite, defaults) = try isolated(); defer { defaults.removePersistentDomain(forName: suite) }
        let store = MemorizationStore(defaults: defaults)
        XCTAssertTrue(store.configure(.init(chapter: 67, from: 1, to: 5, daily: 3), corpus: try corpus()))
        XCTAssertTrue(store.startMushafStudy(keys: ["1:1", "1:2"], scope: .range))
        XCTAssertFalse(store.startMushafStudy(keys: ["114:1"], scope: .surah))
        XCTAssertFalse(store.applySyncedPlan(.init(chapter: 114, from: 1, to: 6, daily: 1)))
        XCTAssertEqual(store.plan.chapter, 67)
        XCTAssertTrue(store.updateMushafStudy { $0.phase = .paused; return true })
        XCTAssertFalse(store.updateMushafStudy { $0.reveal(wordCount: 4, all: true) })
        XCTAssertFalse(store.updateMushafStudy { $0.recordAudioHelp(for: "1:1") })
        XCTAssertFalse(store.updateMushafStudy { $0.answer("remembered") })
        XCTAssertTrue(store.updateMushafStudy { $0.phase = .active; return true })
        XCTAssertTrue(store.updateMushafStudy { $0.reveal(wordCount: 4, all: true) })
        XCTAssertFalse(store.updateMushafStudy { $0.reveal(wordCount: 4, all: true) }, "Repeated reveal must not fabricate extra hints")
        XCTAssertTrue(store.updateMushafStudy { $0.answer("skip") })
        XCTAssertTrue(store.finishMushafStudy())
        XCTAssertNil(store.progress.verses["1:1"])
        XCTAssertEqual(store.mushafStudy.summary?.helped, 1)
    }
}
