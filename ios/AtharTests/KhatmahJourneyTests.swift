import XCTest
@testable import Athar

final class KhatmahJourneyTests: XCTestCase {
    func testDailyScopeIsCappedDoesNotAccumulateMissedDaysAndResumesOnlyRemainingQuota() throws {
        let plan = try KhatmahCalculator.make(first: 1, date: start, weekdays: Set(1...7), daily: 20,
            deadline: nil, reminder: nil, calendar: calendar)
        let later = try XCTUnwrap(calendar.date(byAdding: .day, value: 8, to: start))
        XCTAssertEqual(plan.readingScope(on: later)?.pages, 1...20)
        let partial = try KhatmahCalculator.confirm(plan, first: 1, last: 7, date: later)
        let scope = try XCTUnwrap(partial.readingScope(on: later))
        XCTAssertEqual(scope.pages, 8...20)
        XCTAssertEqual(scope.resumePage(.init(page: 12, chapter: 2, ayah: 77)), 12)
        XCTAssertEqual(scope.resumePage(.init(page: 45, chapter: 2, ayah: 270)), 8)
        let done = try KhatmahCalculator.confirm(partial, first: 8, last: 20, date: later)
        XCTAssertNil(done.readingScope(on: later))
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: later))
        XCTAssertEqual(done.readingScope(on: tomorrow)?.pages, 21...40)
        let revised = try KhatmahCalculator.revised(partial, date: later, weekdays: Set(1...7), daily: 10, deadline: nil, reminder: nil)
        XCTAssertEqual(revised.readingScope(on: later)?.pages, 8...10)
    }
    @MainActor func testDailyConfirmationRejectsBeyondRangeRepeatedAndStaleDay() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("journey.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = KhatmahStore(file: file)
        let plan = try KhatmahCalculator.make(first: 590, date: start, weekdays: Set(1...7), daily: 20,
            deadline: nil, reminder: nil, calendar: calendar)
        XCTAssertTrue(store.adopt(plan))
        let scope = try XCTUnwrap(plan.readingScope(on: start))
        XCTAssertEqual(scope.pages, 590...604)
        XCTAssertFalse(store.confirmReading(scope, through: 605, date: start))
        XCTAssertFalse(store.confirmReading(scope, through: 589, date: start))
        XCTAssertTrue(store.confirmReading(scope, through: 599, date: start))
        XCTAssertFalse(store.confirmReading(scope, through: 599, date: start))
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: start))
        XCTAssertFalse(store.confirmReading(scope, through: 604, date: tomorrow))
        XCTAssertEqual(store.active?.completed.count, 10)
        XCTAssertTrue(store.confirmReading(scope, through: 604, date: start))
        XCTAssertNotNil(store.active?.finished)
        XCTAssertNil(store.active?.readingScope(on: tomorrow))
    }
    @MainActor func testExactVerseStopPersistsWithoutCompletingUnreadPages() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("khatmah.json")
        let store = KhatmahStore(file: file)
        let plan = try KhatmahCalculator.make(first: 1, date: start, weekdays: Set(1...7), daily: 20,
            deadline: nil, reminder: nil, calendar: calendar)
        XCTAssertTrue(store.adopt(plan))
        XCTAssertTrue(store.stop(page: 1, chapter: 1, ayah: 4))
        XCTAssertEqual(store.active?.stoppedAt, .init(page: 1, chapter: 1, ayah: 4))
        XCTAssertEqual(store.active?.nextPage, 1)
        XCTAssertEqual(store.active?.completed.count, 0)
        XCTAssertEqual(store.active?.sessions.count, 0)
        XCTAssertEqual(KhatmahStore(file: file).active?.stoppedAt, store.active?.stoppedAt)
        XCTAssertFalse(store.stop(page: 1, chapter: 1, ayah: 8))
        XCTAssertEqual(store.active?.stoppedAt?.ayah, 4)
    }
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Riyadh")!; return c }
    var start: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 10))! }
    func testEveryStartingPageAndDailyAmountCoversExactlyRemainingPages() throws {
        for first in 1...604 {
            for amount in [1, 4, 20, 100, 604] {
                let plan = try KhatmahCalculator.make(first: first, date: start, weekdays: [2,4,6], daily: amount, deadline: nil, reminder: nil, calendar: calendar)
                XCTAssertTrue(plan.valid)
                XCTAssertEqual(plan.days.flatMap { Array($0.first...$0.last) }, Array(first...604))
                XCTAssertTrue(plan.days.allSatisfy { $0.count <= amount && [2,4,6].contains(calendar.component(.weekday, from: $0.date)) })
            }
        }
    }
    func testDeadlineAllocationNeverDuplicatesOrSkipsPages() throws {
        for days in [1,2,7,30,365,700] {
            let deadline = calendar.date(byAdding: .day, value: days - 1, to: start)!
            let plan = try KhatmahCalculator.make(first: 1, date: start, weekdays: Set(1...7), daily: nil, deadline: deadline, reminder: nil, calendar: calendar)
            XCTAssertEqual(plan.days.flatMap { Array($0.first...$0.last) }, Array(1...604))
            XCTAssertLessThanOrEqual(plan.days.last!.date, deadline)
            XCTAssertLessThanOrEqual(plan.days.map(\.count).max()! - plan.days.map(\.count).min()!, 1)
        }
    }
    func testOpeningDoesNotCompleteAndConfirmationDoesNotDoubleCountRereading() throws {
        let plan = try KhatmahCalculator.make(first: 151, date: start, weekdays: Set(1...7), daily: 20, deadline: nil, reminder: nil, calendar: calendar)
        XCTAssertEqual(plan.due(on: start)?.last, 170)
        XCTAssertEqual(plan.completed.count, 0)
        let read = try KhatmahCalculator.confirm(plan, first: 151, last: 160, date: start)
        let again = try KhatmahCalculator.confirm(read, first: 151, last: 160, date: start)
        XCTAssertEqual(again.completed.count, 10)
        XCTAssertEqual(again.sessions.last?.newlyCompleted, 0)
        XCTAssertEqual(again.nextPage, 161)
        XCTAssertThrowsError(try KhatmahCalculator.confirm(again, first: 170, last: 180, date: start))
    }
    func testMissedDayRequiresExplicitChoiceAndBothChoicesKeepProgress() throws {
        let deadline = calendar.date(byAdding: .day, value: 29, to: start)!
        let plan = try KhatmahCalculator.make(first: 1, date: start, weekdays: Set(1...7), daily: nil, deadline: deadline, reminder: nil, calendar: calendar)
        let later = calendar.date(byAdding: .day, value: 5, to: start)!
        XCTAssertTrue(plan.missedDay(on: later))
        XCTAssertEqual(plan.days.first?.date, calendar.startOfDay(for: start))
        let read = try KhatmahCalculator.confirm(plan, first: 1, last: 10, date: start)
        let redistributed = try KhatmahCalculator.revised(read, date: later, weekdays: Set(1...7), daily: nil, deadline: deadline, reminder: nil)
        let extended = try KhatmahCalculator.revised(read, date: later, weekdays: Set(1...7), daily: 21, deadline: nil, reminder: nil)
        XCTAssertEqual(redistributed.completed, read.completed)
        XCTAssertEqual(extended.sessions.count, read.sessions.count)
        XCTAssertEqual(redistributed.days.first?.first, 11)
        XCTAssertEqual(redistributed.expectedFinish, calendar.startOfDay(for: deadline))
        XCTAssertGreaterThan(extended.expectedFinish!, deadline)
        XCTAssertThrowsError(try KhatmahCalculator.revised(read, date: later, weekdays: [1], daily: nil, deadline: start, reminder: nil))
    }
    func testReadingAheadResumesAtFirstUnconfirmedPage() throws {
        let plan = try KhatmahCalculator.make(first: 1, date: start, weekdays: Set(1...7), daily: 20, deadline: nil, reminder: nil, calendar: calendar)
        let ahead = try KhatmahCalculator.confirm(plan, first: 1, last: 25, date: start)
        XCTAssertEqual(ahead.due(on: start)?.first, 26)
        XCTAssertEqual(ahead.due(on: start)?.last, 40)
        XCTAssertEqual(ahead.completed.count, 25)
    }
    func testRemindersExcludeExpiredDaysBeforeBudgetAndResumeUnconfirmedPage() throws {
        let plan = try KhatmahCalculator.make(first: 1, date: start, weekdays: Set(1...7), daily: 1, deadline: nil, reminder: 18 * 60, calendar: calendar)
        let later = calendar.date(byAdding: .day, value: 40, to: start)!
        let reminders = KhatmahReminderPlan.make(plan, now: later, otherPending: 56)
        XCTAssertEqual(reminders.count, 4)
        XCTAssertTrue(reminders.allSatisfy { $0.fire > later && $0.first == 1 && $0.url == "nooralruh://reading/1" })
        XCTAssertEqual(Set(reminders.map(\.id)).count, reminders.count)
        XCTAssertEqual(reminders, KhatmahReminderPlan.make(plan, now: later, otherPending: 56))
        XCTAssertTrue(KhatmahReminderPlan.make(plan, now: later, otherPending: 64).isEmpty)
        var paused = plan; paused.paused = true
        XCTAssertTrue(KhatmahReminderPlan.make(paused, now: later, otherPending: 0).isEmpty)
        let read = try KhatmahCalculator.confirm(plan, first: 1, last: 45, date: later)
        XCTAssertEqual(KhatmahReminderPlan.make(read, now: later, otherPending: 0).first?.first, 46)
        let finished = try KhatmahCalculator.confirm(read, first: 46, last: 604, date: later)
        XCTAssertTrue(KhatmahReminderPlan.make(finished, now: later, otherPending: 0).isEmpty)
    }
    func testRemindersUsePlanCalendarAcrossDaylightSavingTransition() throws {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/New_York")!
        let date = c.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 10))!
        let plan = try KhatmahCalculator.make(first: 600, date: date, weekdays: Set(1...7), daily: 1, deadline: nil, reminder: 18 * 60 + 35, calendar: c)
        let reminders = KhatmahReminderPlan.make(plan, now: date, otherPending: 0)
        XCTAssertEqual(reminders.count, 5)
        XCTAssertTrue(reminders.allSatisfy { c.component(.hour, from: $0.fire) == 18 && c.component(.minute, from: $0.fire) == 35 })
        XCTAssertEqual(reminders[1].fire.timeIntervalSince(reminders[0].fire), 25 * 3600)
    }
    @MainActor func testPauseEditEarlyCompletionAndPersistence() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("journey.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = KhatmahStore(file: file)
        let plan = try KhatmahCalculator.make(first: 580, date: start, weekdays: Set(1...7), daily: 4, deadline: nil, reminder: nil, calendar: calendar)
        XCTAssertTrue(store.adopt(plan))
        XCTAssertTrue(store.setPaused(true))
        XCTAssertFalse(store.confirm(first: 580, last: 583, date: start))
        XCTAssertTrue(store.setPaused(false))
        XCTAssertTrue(store.confirm(first: 580, last: 590, date: start))
        let changed = try KhatmahCalculator.revised(store.active!, date: start, weekdays: [2,5], daily: 7, deadline: nil, reminder: nil)
        XCTAssertTrue(store.adopt(changed))
        XCTAssertEqual(store.active?.completed.count, 11)
        let reopened = KhatmahStore(file: file)
        XCTAssertEqual(reopened.active?.nextPage, 591)
        XCTAssertEqual(reopened.active?.sessions.count, 1)
        XCTAssertTrue(reopened.confirm(first: 591, last: 604, date: start))
        XCTAssertEqual(reopened.active?.progress, 1)
        XCTAssertEqual(reopened.active?.finished, start)
        XCTAssertEqual(KhatmahStore(file: file).active?.progress, 1)
    }
    @MainActor func testUnreadableArchiveIsNeverOverwritten() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let bad = Data("broken original archive".utf8)
        try bad.write(to: file); defer { try? FileManager.default.removeItem(at: file) }
        let store = KhatmahStore(file: file)
        XCTAssertFalse(store.adopt(try KhatmahCalculator.make(first: 1, date: start, weekdays: [1], daily: 20, deadline: nil, reminder: nil, calendar: calendar)))
        XCTAssertEqual(try Data(contentsOf: file), bad)
    }
    @MainActor func testExportPreservesRawArchiveAndExplicitEraseRemovesIt() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = KhatmahStore(file: file)
        XCTAssertTrue(store.adopt(try KhatmahCalculator.make(first: 600, date: start, weekdays: [1], daily: 1, deadline: nil, reminder: nil, calendar: calendar)))
        let bytes = try XCTUnwrap(store.exportBytes)
        XCTAssertEqual(try JSONDecoder().decode(KhatmahStore.Archive.self, from: bytes).plans.first?.firstPage, 600)
        let erased = await store.erase()
        XCTAssertTrue(erased)
        XCTAssertNil(store.active)
        XCTAssertNil(store.exportBytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
}
