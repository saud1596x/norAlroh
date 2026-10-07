import XCTest
@testable import Athar

final class NoorJourneyIndexTests: XCTestCase {
    func testTimelineGroupsByUserDayWithoutDoubleCountingRereading() throws {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Riyadh")!
        let start = c.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 23, minute: 59))!
        let afterMidnight = start.addingTimeInterval(120)
        let plan = try KhatmahCalculator.make(first: 1, date: start, weekdays: Set(1...7), daily: 20, deadline: nil, reminder: nil, calendar: c)
        let first = try KhatmahCalculator.confirm(plan, first: 1, last: 20, date: start)
        let reread = try KhatmahCalculator.confirm(first, first: 1, last: 20, date: afterMidnight)
        let archive = KhatmahStore.Archive(plans: [reread], activeID: reread.id)
        let index = NoorJourneyIndex(archive: archive, calendar: c)
        XCTAssertEqual(index.events.count, 2)
        XCTAssertEqual(index.readingDays.count, 2)
        XCTAssertEqual(index.newlyCompletedPages, 20)
        XCTAssertEqual(index.events(on: afterMidnight).first?.session.newlyCompleted, 0)
        var utc = c; utc.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(NoorJourneyIndex(archive: archive, calendar: utc).readingDays.count, 1)
        XCTAssertEqual(reread.completed.count, 20)
    }
    func testMonthDaysAcrossLeapYearAndDSTHaveNoDuplicateOrMissingDays() {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/New_York")!; c.firstWeekday = 1
        let index = NoorJourneyIndex(archive: .init(), calendar: c)
        for (year, month, count) in [(2028, 2, 29), (2026, 3, 31), (2026, 11, 30)] {
            let date = c.date(from: DateComponents(year: year, month: month, day: 15))!
            let days = index.days(in: date)
            XCTAssertEqual(days.count, count)
            XCTAssertEqual(Set(days).count, count)
            XCTAssertEqual(days.map { c.component(.day, from: $0) }, Array(1...count))
            XCTAssertTrue(days.allSatisfy { c.component(.hour, from: $0) == 0 })
            XCTAssertEqual(index.leadingDays(in: date), (c.component(.weekday, from: days[0]) - 1) % 7)
        }
        XCTAssertTrue(index.events.isEmpty)
        XCTAssertTrue(index.readingDays.isEmpty)
        XCTAssertEqual(index.newlyCompletedPages, 0)
    }
    func testFinishedJourneysAndHistoryRemainSeparateWhenStartingAgain() throws {
        let c = Calendar(identifier: .gregorian)
        let start = Date(timeIntervalSince1970: 1700000000)
        let first = try KhatmahCalculator.make(first: 600, date: start, weekdays: Set(1...7), daily: 5, deadline: nil, reminder: nil, calendar: c)
        let finished = try KhatmahCalculator.confirm(first, first: 600, last: 604, date: start)
        let next = try KhatmahCalculator.make(first: 1, date: start, weekdays: Set(1...7), daily: 20, deadline: nil, reminder: nil, calendar: c)
        let index = NoorJourneyIndex(archive: .init(plans: [finished, next], activeID: next.id), calendar: c)
        XCTAssertEqual(index.events.count, 1)
        XCTAssertEqual(index.events.first?.planID, finished.id)
        XCTAssertEqual(index.newlyCompletedPages, 5)
        XCTAssertEqual(next.progress, 0)
    }
}
