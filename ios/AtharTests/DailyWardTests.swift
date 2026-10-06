import XCTest
@testable import Athar

final class DailyWardTests: XCTestCase {
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Riyadh")!; return c }
    private var date: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 20))! }
    private var independent: MemorizationAnswer { .init(ayah: 1, assessment: "remembered", revealed: false, hints: 0) }
    func testSameDayRepetitionDoesNotManufactureMastery() {
        var state = VerseReviewState()
        state.record(independent, at: date, calendar: calendar)
        state.record(independent, at: date.addingTimeInterval(300), calendar: calendar)
        XCTAssertEqual(state.stage, 1); XCTAssertEqual(state.attempts, 2)
        let next = calendar.date(byAdding: .day, value: 1, to: date)!
        state.record(independent, at: next, calendar: calendar)
        XCTAssertEqual(state.stage, 2)
        XCTAssertEqual(calendar.dateComponents([.day], from: calendar.startOfDay(for: next), to: state.nextReview).day, 3)
        state.record(.init(ayah: 1, assessment: "remembered", revealed: false, hints: 1), at: next, calendar: calendar)
        XCTAssertEqual(state.stage, 0); XCTAssertTrue(state.needsHelp); XCTAssertEqual(state.lapses, 1)
    }
    func testSkippedVerseDoesNotErasePriorMasteryOrCountAsPractice() {
        var state = VerseReviewState(); state.record(independent, at: date, calendar: calendar)
        state.record(.init(ayah: 1, assessment: "skip", revealed: false, hints: 0), at: date, calendar: calendar)
        XCTAssertEqual(state.stage, 1); XCTAssertEqual(state.attempts, 1)
        var progress = MemorizationProgress()
        progress.record(.init(date: date, chapter: 1, answers: [.init(ayah: 2, assessment: "skip", revealed: false, hints: 0)]), calendar: calendar)
        XCTAssertTrue(progress.practiceDays.isEmpty)
    }
    func testWardContractCountsUniqueSelectedVersesOnly() {
        let contract = NoorWardContract(chapter: 1, from: 2, to: 5, target: 3)
        XCTAssertFalse(contract.completed(in: ["1:1", "1:2", "1:3", "2:4"]))
        XCTAssertTrue(contract.completed(in: ["1:2", "1:3", "1:4"]))
        XCTAssertFalse(NoorWardContract(chapter: 1, from: 2, to: 3, target: 3).valid)
    }
    func testWardRollsOverAtLocalMidnight() {
        let before = calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 23, minute: 59))!
        let after = before.addingTimeInterval(120)
        XCTAssertNotEqual(NoorWardContract.dayKey(before, calendar: calendar), NoorWardContract.dayKey(after, calendar: calendar))
        XCTAssertEqual(NoorWardContract.dayKey(before, calendar: calendar), MemorizationProgress.dayKey(before, calendar: calendar))
    }
    @MainActor func testProgressSurvivesHistoryLimitAndRestart() throws {
        let suite = "NoorWardPersistence." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let store = MemorizationStore(defaults: defaults)
        XCTAssertTrue(store.finish(chapter: 1, answers: [independent]))
        for _ in 0..<105 { XCTAssertTrue(store.finish(chapter: 1, answers: [.init(ayah: 2, assessment: "review", revealed: true, hints: 0)])) }
        let reopened = MemorizationStore(defaults: defaults)
        XCTAssertEqual(reopened.history.count, 100)
        XCTAssertEqual(reopened.progress.verses["1:1"]?.attempts, 1)
        XCTAssertEqual(reopened.progress.verses["1:2"]?.attempts, 105)
        XCTAssertEqual(reopened.completedToday(), 2)
    }
    @MainActor func testMalformedNewArchiveIsProtected() throws {
        let suite = "NoorWardRecovery." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let bad = Data("bad-archive".utf8); defaults.set(bad, forKey: "noor.memorization.archive")
        let store = MemorizationStore(defaults: defaults)
        XCTAssertFalse(store.finish(chapter: 1, answers: [independent]))
        XCTAssertEqual(defaults.data(forKey: "noor.memorization.archive"), bad)
        XCTAssertEqual(store.unreadableHistory, bad)
    }
    @MainActor func testConfirmedDifferenceIsSavedWithoutClaimingWardCompletion() throws {
        let suite = "NoorMistakes." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let store = MemorizationStore(defaults: defaults)
        XCTAssertTrue(store.confirmMistake(chapter: 1, ayah: 1, expected: "بِسْمِ", heard: "اسم"))
        XCTAssertEqual(store.completedToday(), 0)
        let reopened = MemorizationStore(defaults: defaults)
        XCTAssertEqual(reopened.progress.confirmedMistakes.count, 1)
        XCTAssertTrue(reopened.progress.verses["1:1"]!.needsHelp)
    }
}
