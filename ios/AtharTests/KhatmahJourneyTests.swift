import XCTest
@testable import Athar

final class KhatmahJourneyTests: XCTestCase {
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
}
