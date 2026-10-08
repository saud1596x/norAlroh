import XCTest
@testable import Athar

final class MushafStudyGoalTests: XCTestCase {
    private func date(_ value: String) throws -> Date { try XCTUnwrap(ISO8601DateFormatter().date(from: value)) }
    private func answer(_ number: Int, _ assessment: String = "remembered") -> MemorizationAnswer {
        .init(ayah: number, assessment: assessment, revealed: assessment == "review", hints: 0)
    }
    func testCountsUniqueCompletedAyahsAcrossSurahsWithoutSkipsInvalidKeysOrExtraRepeatCredit() throws {
        let corpus = try XCTUnwrap(QuranResources.corpus); let now = try date("2026-10-08T10:00:00Z")
        let rows = [MemorizationResult(date: now, chapter: 112, answers: [answer(1), answer(2, "review"), answer(3, "skip"), answer(5)]),
            MemorizationResult(date: now, chapter: 112, answers: [answer(1)]),
            MemorizationResult(date: now, chapter: 113, answers: [answer(1)]),
            MemorizationResult(date: now, chapter: 0, answers: [answer(1)]),
            MemorizationResult(date: try date("2026-10-07T10:00:00Z"), chapter: 114, answers: [answer(1)])]
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Riyadh"))
        XCTAssertEqual(MushafStudyGoal.completed(history: rows, corpus: corpus, at: now, calendar: calendar), 3)
    }
    func testDayUsesUserTimezoneAtMidnightRatherThanUTCOrStoredPracticeDayStrings() throws {
        let corpus = try XCTUnwrap(QuranResources.corpus)
        let now = try date("2026-10-08T05:30:00Z")
        let rows = [MemorizationResult(date: try date("2026-10-07T21:30:00Z"), chapter: 112, answers: [answer(1)]),
            MemorizationResult(date: try date("2026-10-08T04:00:00Z"), chapter: 112, answers: [answer(2)])]
        var calendar = Calendar(identifier: .islamicUmmAlQura)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Riyadh"))
        XCTAssertEqual(MushafStudyGoal.completed(history: rows, corpus: corpus, at: now, calendar: calendar), 2)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        XCTAssertEqual(MushafStudyGoal.completed(history: rows, corpus: corpus, at: now, calendar: calendar), 1)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        XCTAssertEqual(MushafStudyGoal.completed(history: rows, corpus: corpus, at: now, calendar: calendar), 2)
    }
    func testRepeatedClockHourAtDSTTransitionStillCountsOneLocalDayAndOneAyah() throws {
        let corpus = try XCTUnwrap(QuranResources.corpus); let now = try date("2026-11-01T20:00:00Z")
        let rows = [MemorizationResult(date: try date("2026-11-01T08:30:00Z"), chapter: 112, answers: [answer(1)]),
            MemorizationResult(date: try date("2026-11-01T09:30:00Z"), chapter: 112, answers: [answer(1), answer(2)]),
            MemorizationResult(date: try date("2026-11-01T06:30:00Z"), chapter: 112, answers: [answer(3)])]
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        XCTAssertEqual(MushafStudyGoal.completed(history: rows, corpus: corpus, at: now, calendar: calendar), 2)
    }
    func testLocalMidnightStartsNewGoalDayWithoutDeletingYesterdayHistory() throws {
        let corpus = try XCTUnwrap(QuranResources.corpus)
        let rows = [MemorizationResult(date: try date("2026-10-07T20:59:00Z"), chapter: 112, answers: [answer(1)])]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Riyadh"))
        XCTAssertEqual(MushafStudyGoal.completed(history: rows, corpus: corpus, at: try date("2026-10-07T20:59:59Z"), calendar: calendar), 1)
        XCTAssertEqual(MushafStudyGoal.completed(history: rows, corpus: corpus, at: try date("2026-10-07T21:00:00Z"), calendar: calendar), 0)
        XCTAssertEqual(MushafStudyGoal.completed(history: rows, corpus: corpus, at: try date("2026-10-07T20:59:59Z"), calendar: calendar), 1)
        XCTAssertEqual(rows[0].answers.count, 1)
    }
    @MainActor func testGoalSaveDisableAndRelaunchPreservePendingSessionRepeatChoicesAndLegacyPlan() throws {
        let suite = "Noor.StudyGoal." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let corpus = try XCTUnwrap(QuranResources.corpus)
        let store = MemorizationStore(defaults: defaults)
        XCTAssertTrue(store.configure(.init(chapter: 67, from: 1, to: 5, daily: 3), corpus: corpus))
        let legacy = defaults.data(forKey: "noor.memorization.plan")
        XCTAssertTrue(store.startMushafStudy(keys: ["112:1"], scope: .range))
        var next = store.mushafStudy; next.repetition = .init(count: 4, delaySeconds: 2); next.goal = .init(dailyAyahs: 7)
        XCTAssertTrue(store.saveMushafStudy(next))
        let restored = MemorizationStore(defaults: defaults)
        XCTAssertEqual(restored.mushafStudy, next); XCTAssertEqual(defaults.data(forKey: "noor.memorization.plan"), legacy)
        let retained = try XCTUnwrap(defaults.data(forKey: "noor.mushaf.study"))
        for invalid in [0, 201] {
            var rejected = next; rejected.goal = .init(dailyAyahs: invalid)
            XCTAssertFalse(restored.saveMushafStudy(rejected)); XCTAssertEqual(defaults.data(forKey: "noor.mushaf.study"), retained)
        }
        next.goal = nil; XCTAssertTrue(restored.saveMushafStudy(next))
        XCTAssertEqual(MemorizationStore(defaults: defaults).mushafStudy, next)
        let old = try JSONDecoder().decode(MushafStudyArchive.self, from: Data(#"{"version":1}"#.utf8))
        XCTAssertNil(old.goal); XCTAssertTrue(old.valid(corpus: corpus))
        let damaged = Data([0, 255, 9])
        defaults.set(damaged, forKey: "noor.memorization.archive")
        let unavailable = MemorizationStore(defaults: defaults)
        XCTAssertEqual(unavailable.unreadableHistory, damaged)
        var independent = unavailable.mushafStudy; independent.goal = .init(dailyAyahs: 9)
        XCTAssertTrue(unavailable.saveMushafStudy(independent))
        XCTAssertEqual(defaults.data(forKey: "noor.memorization.archive"), damaged,
            "Changing an independent goal cannot repair or replace damaged history")
        defaults.set(damaged, forKey: "noor.mushaf.study")
        let corrupt = MemorizationStore(defaults: defaults)
        XCTAssertFalse(corrupt.saveMushafStudy(next)); XCTAssertEqual(corrupt.unreadableMushafStudy, damaged)
        XCTAssertEqual(defaults.data(forKey: "noor.mushaf.study"), damaged)
    }
}
