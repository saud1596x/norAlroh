import XCTest
@testable import Athar

final class LocalDataRecoveryTests: XCTestCase {
    func testCombinedExportRetainsBothJourneyAndStudyArchivesAndReadsEarlierExports() throws {
        let khatmah = Data([255, 8, 1])
        let damagedStudy = Data([0, 255, 9])
        let export = NoorPrivacyExport(device: DeviceData(), adhkarCounters: [:], adhkarFavorites: [],
            memorizationPlan: .init(), memorizationHistory: [], prayerPreferences: .init(),
            localRecording: nil, lastMushafPage: 151, unreadableDeviceData: nil,
            unreadableMemorizationHistory: nil, khatmahArchive: khatmah,
            mushafStudy: .init(), unreadableMushafStudy: damagedStudy, mushafRecordings: [])
        let encoded = try JSONEncoder().encode(export)
        let restored = try JSONDecoder().decode(NoorPrivacyExport.self, from: encoded)
        XCTAssertEqual(restored.khatmahArchive, khatmah)
        XCTAssertEqual(restored.unreadableMushafStudy, damagedStudy)
        XCTAssertNotNil(restored.mushafStudy)
        XCTAssertEqual(restored.mushafRecordings?.count, 0)
        XCTAssertEqual(restored.lastMushafPage, 151)
        var earlier = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for key in ["khatmahArchive", "mushafStudy", "unreadableMushafStudy", "mushafRecordings"] { earlier.removeValue(forKey: key) }
        let previous = try JSONDecoder().decode(NoorPrivacyExport.self, from: JSONSerialization.data(withJSONObject: earlier))
        XCTAssertNil(previous.khatmahArchive); XCTAssertNil(previous.mushafStudy)
        XCTAssertEqual(previous.lastMushafPage, 151)
    }
    @MainActor func testLegacyArchiveOpeningKeepsPositionPreviousRangeAndModelBytesWithoutAnalysis() throws {
        let suite = "Noor.LegacySpeech." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = root.appendingPathComponent("retained-model.bin"); let modelBytes = Data([1, 9, 7]); try modelBytes.write(to: model)
        let corpus = try XCTUnwrap(QuranResources.corpus)
        let words = RecitationComparison.words(chapter: corpus[111], from: 1, to: 4)
        let next = try XCTUnwrap(words.firstIndex { $0.ayah == 2 })
        let position = try XCTUnwrap(SpeechSessionPosition.make(words: words, nextWord: next, usedHelp: true))
        XCTAssertTrue(SpeechPositionStore(defaults: defaults).save(position))
        let bytes = try XCTUnwrap(defaults.data(forKey: "noor.speech.position.v1"))
        let previous = Data([255, 0, 2]); defaults.set(previous, forKey: "noor.speech.previousPosition.v1")
        defaults.set(model.path, forKey: "noor.speechModelFolder.v1")
        let archive = LegacySpeechArchive(defaults: defaults, modelFolder: root)
        XCTAssertEqual(archive.savedPosition?.nextWord, next); XCTAssertTrue(archive.savedPosition?.usedHelp == true)
        let start = archive.readerPosition(corpus: corpus, plan: .init(chapter: 67, from: 1, to: 5, daily: 2), pending: nil)
        XCTAssertEqual(start.chapter, 112); XCTAssertEqual(start.ayah, 2)
        var pending = MushafStudySession(keys: ["113:1", "113:2"], scope: .range)
        XCTAssertTrue(pending.answer("review"))
        let resumed = archive.readerPosition(corpus: corpus, plan: .init(), pending: pending)
        XCTAssertEqual(resumed.chapter, 113); XCTAssertEqual(resumed.ayah, 2)
        XCTAssertEqual(defaults.data(forKey: "noor.speech.position.v1"), bytes)
        XCTAssertEqual(archive.previousPosition, previous); XCTAssertEqual(try Data(contentsOf: model), modelBytes)
        XCTAssertEqual(defaults.string(forKey: "noor.speechModelFolder.v1"), model.path)
    }
    @MainActor func testLegacyDamagedPositionAndNeighborRecordingSurviveOpeningAndExplicitModelErase() async throws {
        let suite = "Noor.LegacySpeechDamaged." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = root.appendingPathComponent("NoorSpeech")
        try FileManager.default.createDirectory(at: model, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let recording = root.appendingPathComponent("latest-recitation.m4a")
        let bytes = Data([3, 4, 5]); try bytes.write(to: recording)
        try bytes.write(to: model.appendingPathComponent("model.bin"))
        let damaged = Data([0, 255, 10]); defaults.set(damaged, forKey: "noor.speech.position.v1")
        let archive = LegacySpeechArchive(defaults: defaults, modelFolder: model)
        XCTAssertEqual(archive.unreadablePosition, damaged); XCTAssertNil(archive.savedPosition)
        let start = archive.readerPosition(corpus: try XCTUnwrap(QuranResources.corpus), plan: .init(), pending: nil)
        XCTAssertEqual(start.chapter, 1); XCTAssertEqual(start.ayah, 1)
        let erased = await archive.eraseModel(); XCTAssertTrue(erased)
        XCTAssertFalse(FileManager.default.fileExists(atPath: model.path))
        XCTAssertEqual(try Data(contentsOf: recording), bytes)
        XCTAssertEqual(defaults.data(forKey: "noor.speech.position.v1"), damaged)
    }
    func testStaleUploadRetainsNewerRemoteProgressAndIsIdempotent() throws {
        let corpus = try XCTUnwrap(QuranResources.corpus)
        let old = MemorizationResult(date: Date(timeIntervalSince1970: 1_700_000_000), chapter: 1,
            answers: [.init(ayah: 1, assessment: "review", revealed: false, hints: 0)])
        let newer = MemorizationResult(date: old.date.addingTimeInterval(172800), chapter: 1,
            answers: [.init(ayah: 1, assessment: "remembered", revealed: false, hints: 0)])
        var oldProgress = MemorizationProgress(); oldProgress.record(old)
        var newProgress = oldProgress; newProgress.record(newer)
        let stale = MemorizationCloudBackup(version: 1, plan: .init(),
            archive: .init(version: 1, history: [old], progress: oldProgress))
        let current = MemorizationCloudBackup(version: 1, plan: .init(),
            archive: .init(version: 1, history: [newer, old], progress: newProgress))
        let merged = try MemorizationCloudMerge.merge(local: stale, remote: current, corpus: corpus)
        let retried = try MemorizationCloudMerge.merge(local: stale, remote: merged, corpus: corpus)
        XCTAssertEqual(retried.archive.history.map(\.id), [newer.id, old.id])
        let state = try XCTUnwrap(retried.archive.progress.verses["1:1"])
        XCTAssertEqual(state.lastPracticed, newer.date)
        XCTAssertEqual(state.attempts, 2)
        XCTAssertEqual(state.lapses, 1)
        XCTAssertFalse(state.needsHelp)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        XCTAssertEqual(try encoder.encode(merged), try encoder.encode(retried))
        XCTAssertEqual(stale.archive.history.count, 1)
    }
    func testUploadMergeRejectsConflictingEventAndInvalidRemoteArchive() throws {
        let corpus = try XCTUnwrap(QuranResources.corpus)
        let result = MemorizationResult(chapter: 1,
            answers: [.init(ayah: 1, assessment: "remembered", revealed: false, hints: 0)])
        var progress = MemorizationProgress(); progress.record(result)
        let local = MemorizationCloudBackup(version: 1, plan: .init(),
            archive: .init(version: 1, history: [result], progress: progress))
        let conflict = MemorizationResult(id: result.id, date: result.date, chapter: 1,
            answers: [.init(ayah: 1, assessment: "review", revealed: false, hints: 0)])
        let remote = MemorizationCloudBackup(version: 1, plan: .init(),
            archive: .init(version: 1, history: [conflict], progress: progress))
        XCTAssertThrowsError(try MemorizationCloudMerge.merge(local: local, remote: remote, corpus: corpus))
        let invalid = MemorizationCloudBackup(version: 2, plan: .init(), archive: local.archive)
        XCTAssertThrowsError(try MemorizationCloudMerge.merge(local: local, remote: invalid, corpus: corpus))
        let duplicate = MemorizationCloudBackup(version: 1, plan: .init(),
            archive: .init(version: 1, history: [result, result], progress: progress))
        XCTAssertThrowsError(try MemorizationCloudMerge.merge(local: duplicate, remote: local, corpus: corpus))
    }
    func testSpeechPositionRestoresTrustedRangeAndAssistanceWithoutSavingTranscript() throws {
        let suite = "NoorSpeechPosition." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let corpus = try XCTUnwrap(QuranResources.corpus)
        let words = RecitationComparison.words(chapter: corpus[111], from: 1, to: 4)
        let position = try XCTUnwrap(SpeechSessionPosition.make(words: words, nextWord: 3, usedHelp: true))
        XCTAssertTrue(SpeechPositionStore(defaults: defaults).save(position))
        let restored = try XCTUnwrap(SpeechPositionStore(defaults: defaults).value)
        XCTAssertEqual(restored.nextWord, 3)
        XCTAssertTrue(restored.usedHelp)
        XCTAssertTrue(restored.matches(words))
        let bytes = try XCTUnwrap(defaults.data(forKey: "noor.speech.position.v1"))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertNil(payload["transcript"]); XCTAssertNil(payload["audio"])
        var invalid = restored; invalid.nextWord = words.count + 1
        XCTAssertFalse(SpeechPositionStore(defaults: defaults).save(invalid))
        XCTAssertEqual(defaults.data(forKey: "noor.speech.position.v1"), bytes)
        let changedWords = RecitationComparison.words(chapter: corpus[111], from: 2, to: 4)
        XCTAssertFalse(restored.matches(changedWords))
    }
    func testSpeechPositionPreservesDamagedDataAndPreviousRangeUntilExplicitErase() throws {
        let suite = "NoorSpeechRecovery." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let corpus = try XCTUnwrap(QuranResources.corpus)
        let first = try XCTUnwrap(SpeechSessionPosition.make(words: RecitationComparison.words(chapter: corpus[0], from: 1, to: 7), nextWord: 4, usedHelp: false))
        let store = SpeechPositionStore(defaults: defaults)
        XCTAssertTrue(store.save(first))
        let old = try XCTUnwrap(defaults.data(forKey: "noor.speech.position.v1"))
        let second = try XCTUnwrap(SpeechSessionPosition.make(words: RecitationComparison.words(chapter: corpus[111], from: 1, to: 4), nextWord: 0, usedHelp: false))
        XCTAssertTrue(store.save(second))
        XCTAssertEqual(defaults.data(forKey: "noor.speech.previousPosition.v1"), old)
        let damaged = Data("invalid-speech-position".utf8)
        defaults.set(damaged, forKey: "noor.speech.position.v1")
        let reopened = SpeechPositionStore(defaults: defaults)
        XCTAssertFalse(reopened.save(first)); XCTAssertEqual(defaults.data(forKey: "noor.speech.position.v1"), damaged)
        reopened.erase()
        XCTAssertNil(defaults.data(forKey: "noor.speech.position.v1")); XCTAssertNil(defaults.data(forKey: "noor.speech.previousPosition.v1"))
        XCTAssertTrue(reopened.save(first))
    }
    @MainActor func testCloudMergePreservesLocalSessionPlanAndHistoryWithoutDuplicatingEvents() throws {
        let suite = "Noor.Merge." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MemorizationStore(defaults: defaults)
        XCTAssertTrue(store.finish(chapter: 1, answers: [.init(ayah: 1, assessment: "remembered", revealed: false, hints: 0)]))
        let local = store.history[0]
        let checkpoint = MemorizationSession(chapter: 1, keys: [2, 3])
        XCTAssertTrue(store.saveSession(checkpoint))
        let remote = MemorizationResult(date: Date().addingTimeInterval(-86400), chapter: 1,
            answers: [.init(ayah: 2, assessment: "remembered", revealed: false, hints: 0)])
        var progress = MemorizationProgress(); progress.record(remote); progress.record(local)
        let backup = MemorizationCloudBackup(version: 1, plan: .init(chapter: 112, from: 1, to: 4, daily: 2),
            archive: .init(version: 1, history: [remote, local], progress: progress))
        XCTAssertTrue(store.restore(backup)); XCTAssertTrue(store.restore(backup))
        XCTAssertEqual(Set(store.history.map(\.id)), Set([local.id, remote.id]))
        XCTAssertEqual(store.progress.verses["1:1"]?.attempts, 1)
        XCTAssertEqual(store.plan.chapter, 1); XCTAssertEqual(store.session?.keys, [2, 3])
        XCTAssertEqual(store.completedToday(), 1)
        let recovery = try XCTUnwrap(store.preCloudMerge?["archive"])
        let original = try JSONDecoder().decode(MemorizationArchive.self, from: recovery)
        XCTAssertEqual(original.history.map(\.id), [local.id])
        let reopened = MemorizationStore(defaults: defaults)
        XCTAssertEqual(reopened.history.count, 2); XCTAssertEqual(reopened.session?.keys, [2, 3])
    }
    @MainActor func testOlderCloudReviewCannotReplaceMoreRecentIndependentPractice() throws {
        let suite = "Noor.MergeChronology." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MemorizationStore(defaults: defaults)
        XCTAssertTrue(store.finish(chapter: 1, answers: [.init(ayah: 1, assessment: "remembered", revealed: false, hints: 0)]))
        let latest = try XCTUnwrap(store.progress.verses["1:1"])
        let old = MemorizationResult(date: latest.lastPracticed.addingTimeInterval(-86400), chapter: 1,
            answers: [.init(ayah: 1, assessment: "review", revealed: true, hints: 1)])
        var oldProgress = MemorizationProgress(); oldProgress.record(old)
        let backup = MemorizationCloudBackup(version: 1, plan: store.plan,
            archive: .init(version: 1, history: [old], progress: oldProgress))
        XCTAssertTrue(store.restore(backup)); XCTAssertTrue(store.restore(backup))
        let merged = try XCTUnwrap(store.progress.verses["1:1"])
        XCTAssertEqual(merged.lastPracticed, latest.lastPracticed)
        XCTAssertEqual(merged.nextReview, latest.nextReview)
        XCTAssertFalse(merged.needsHelp)
        XCTAssertEqual(merged.attempts, 2); XCTAssertEqual(merged.lapses, 1)
        XCTAssertEqual(store.history.count, 2)
        XCTAssertEqual(store.completedToday(), 1)
    }
    @MainActor func testCloudMergeRejectsConflictingImmutableResultBeforeWritingAnything() throws {
        let suite = "Noor.MergeConflict." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MemorizationStore(defaults: defaults)
        XCTAssertTrue(store.finish(chapter: 1, answers: [.init(ayah: 1, assessment: "remembered", revealed: false, hints: 0)]))
        let original = store.history[0]
        let conflicting = MemorizationResult(id: original.id, date: original.date, chapter: 1,
            answers: [.init(ayah: 1, assessment: "review", revealed: false, hints: 0)])
        let bytes = defaults.data(forKey: "noor.memorization.archive")
        let backup = MemorizationCloudBackup(version: 1, plan: store.plan,
            archive: .init(version: 1, history: [conflicting], progress: store.progress))
        XCTAssertFalse(store.restore(backup))
        XCTAssertEqual(defaults.data(forKey: "noor.memorization.archive"), bytes)
        XCTAssertNil(store.preCloudMerge)
    }

    @MainActor func testMushafPracticeRestoresPositionAndHelpWithoutCountingOpeningAsCompletion() throws {
        let suite = "NoorPracticeRecovery." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let store = MemorizationStore(defaults: defaults)
        let value = MemorizationPracticeSession(chapter: 112, from: 1, to: 4, ayah: 3, visibleWords: 2, hints: 1, revealAll: false, usedHelp: true)
        XCTAssertTrue(store.savePractice(value))
        XCTAssertEqual(store.completedToday(), 0)
        let reopened = MemorizationStore(defaults: defaults)
        XCTAssertEqual(reopened.practice?.ayah, 3)
        XCTAssertEqual(reopened.practice?.visibleWords, 2)
        XCTAssertEqual(reopened.practice?.hints, 1)
        XCTAssertEqual(reopened.practice?.usedHelp, true)
        reopened.erase()
        XCTAssertNil(defaults.data(forKey: "noor.memorization.practice"))
    }
    @MainActor func testUnreadablePracticeIsNotOverwrittenByNewTraining() throws {
        let suite = "NoorPracticeUnreadable." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let damaged = Data("invalid-practice".utf8); defaults.set(damaged, forKey: "noor.memorization.practice")
        let store = MemorizationStore(defaults: defaults)
        XCTAssertFalse(store.savePractice(.init(chapter: 1, from: 1, to: 7, ayah: 1)))
        XCTAssertEqual(defaults.data(forKey: "noor.memorization.practice"), damaged)
    }
    @MainActor func testUnreadableDeviceFileIsExportableAndCannotBeOverwrittenUntilErase() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let directory = folder.appendingPathComponent("Athar")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let original = Data("{invalid-but-preserved".utf8)
        let file = directory.appendingPathComponent("device-data.json")
        try original.write(to: file)
        let store = AtharStore(directory: folder)
        XCTAssertEqual(store.unreadableDeviceData, original)
        XCTAssertFalse(store.update { $0.lowMotion = true })
        XCTAssertEqual(try Data(contentsOf: file), original)
        XCTAssertTrue(store.erase())
        XCTAssertNil(store.unreadableDeviceData)
        XCTAssertTrue(store.update { $0.lowMotion = true })
        XCTAssertTrue(AtharStore(directory: folder).data.lowMotion)
    }
    @MainActor func testMalformedMemorizationHistoryIsNotReplacedByNewResults() throws {
        let suite = "NoorHistoryRecovery." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = Data("unreadable-history".utf8)
        defaults.set(original, forKey: "noor.memorization.history")
        let store = MemorizationStore(defaults: defaults)
        XCTAssertEqual(store.unreadableHistory, original)
        let answer = MemorizationAnswer(ayah: 1, assessment: "remembered", revealed: false, hints: 0)
        XCTAssertFalse(store.finish(chapter: 1, answers: [answer]))
        XCTAssertEqual(defaults.data(forKey: "noor.memorization.history"), original)
        store.erase()
        XCTAssertTrue(store.finish(chapter: 1, answers: [answer]))
        XCTAssertFalse(store.finish(chapter: 1, answers: [answer, answer]))
        XCTAssertFalse(store.finish(chapter: 1, answers: [.init(ayah: 1, assessment: "unsupported", revealed: false, hints: 0)]))
    }
    @MainActor func testUpgradeAndNewResultPreserveAllHistoryAndOriginalBytes() throws {
        let suite = "NoorRetention." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let answer = MemorizationAnswer(ayah: 1, assessment: "remembered", revealed: false, hints: 0)
        let history = (0..<125).map { index in
            MemorizationResult(date: Date(timeIntervalSince1970: Double(index + 1) * 86400), chapter: 1, answers: [answer])
        }
        let original = try JSONEncoder().encode(history)
        defaults.set(original, forKey: "noor.memorization.history")
        let store = MemorizationStore(defaults: defaults)
        XCTAssertEqual(store.history.map(\.id), history.map(\.id))
        XCTAssertTrue(store.finish(chapter: 1, answers: [answer]))
        let reopened = MemorizationStore(defaults: defaults)
        XCTAssertEqual(reopened.history.count, 126)
        XCTAssertEqual(Array(reopened.history.dropFirst()).map(\.id), history.map(\.id))
        let preserved = defaults.dictionary(forKey: "noor.memorization.preRetentionFix")
        XCTAssertEqual(preserved?["history"] as? Data, original)
        reopened.erase()
        XCTAssertNil(defaults.object(forKey: "noor.memorization.preRetentionFix"))
        XCTAssertTrue(MemorizationStore(defaults: defaults).history.isEmpty)
    }
    @MainActor func testArchiveDoesNotDropNotesOrPlanAfterNewResult() throws {
        let suite = "NoorArchiveRetention." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let corpus = try XCTUnwrap(QuranResources.corpus)
        let word = try XCTUnwrap(corpus[0].ayahs[0].text.split(whereSeparator: \.isWhitespace).first)
        var progress = MemorizationProgress()
        progress.confirmedMistakes = (0..<501).map { _ in .init(chapter: 1, ayah: 1, expected: String(word), heard: nil) }
        let plan = MemorizationPlan(chapter: 1, from: 1, to: 7, daily: 5)
        defaults.set(try JSONEncoder().encode(MemorizationArchive(version: 1, history: [], progress: progress, plan: plan)), forKey: "noor.memorization.archive")
        let store = MemorizationStore(defaults: defaults)
        XCTAssertTrue(store.confirmMistake(chapter: 1, ayah: 1, expected: String(word), heard: nil))
        XCTAssertEqual(MemorizationStore(defaults: defaults).progress.confirmedMistakes.count, 502)
        XCTAssertEqual(MemorizationStore(defaults: defaults).plan.daily, 5)
    }
    func testArabicPersianAndAsciiPageNumbers() {
        XCTAssertEqual(ArabicSearch.integer("٦٠٤"), 604)
        XCTAssertEqual(ArabicSearch.integer("۱۲۳"), 123)
        XCTAssertEqual(ArabicSearch.integer(" 42 "), 42)
        XCTAssertNil(ArabicSearch.integer("١-٢"))
        XCTAssertNil(ArabicSearch.integer(""))
        XCTAssertNil(ArabicSearch.integer("999999999999999999999"))
        XCTAssertEqual(ArabicSearch.normalize("الإِخۡلَاصِ"), ArabicSearch.normalize("الاخلاص"))
        XCTAssertEqual(ArabicSearch.normalize("النَّاسِ"), ArabicSearch.normalize("الناس"))
        XCTAssertEqual(ArabicSearch.normalize("المَدِينَة"), ArabicSearch.normalize("المدينة"))
    }
}
