import XCTest
import DeviceActivity
@testable import Athar

final class NoorKhatmahProtectionTests: XCTestCase {
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private func contract() -> NoorKhatmahWardContract {
        NoorKhatmahWardContract(planID: UUID(), firstPage: 590, timeZone: "Asia/Riyadh", days: [
            .init(date: date("2026-10-08T21:00:00Z"), first: 590, last: 595),
            .init(date: date("2026-10-10T21:00:00Z"), first: 596, last: 604)
        ], nextPage: 590)
    }
    func testConfirmedPagesReleaseWardAndRestDayUntilNextRiyadhMidnight() throws {
        var value = contract()
        XCTAssertTrue(value.valid)
        XCTAssertNil(value.ward(at: date("2026-10-08T20:59:59Z")))
        XCTAssertEqual(value.ward(at: date("2026-10-08T21:00:00Z"))?.last, 595)
        value.confirm(planID: value.planID, nextPage: 593)
        XCTAssertEqual(value.ward(at: date("2026-10-09T10:00:00Z"))?.first, 593)
        value.confirm(planID: value.planID, nextPage: 596)
        XCTAssertNil(value.ward(at: date("2026-10-10T20:59:59Z")))
        XCTAssertEqual(value.ward(at: date("2026-10-10T21:00:00Z"))?.first, 596)
        let restored = try JSONDecoder().decode(NoorKhatmahWardContract.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(restored, value)
        value.confirm(planID: value.planID, nextPage: 605)
        XCTAssertTrue(value.finished)
        XCTAssertNil(value.ward(at: date("2026-10-15T00:00:00Z")))
    }
    func testSystemMonitoringIntervalUsesTheRecordedKhatmahCalendarAndZone() throws {
        let value = contract()
        let schedule = DeviceActivitySchedule(intervalStart: value.monitoringStart, intervalEnd: value.monitoringEnd, repeats: true)
        let interval = try XCTUnwrap(schedule.nextInterval)
        let start = value.calendar.dateComponents([.hour, .minute, .second], from: interval.start)
        let end = value.calendar.dateComponents([.hour, .minute, .second], from: interval.end)
        XCTAssertEqual(start.hour, 0); XCTAssertEqual(start.minute, 0); XCTAssertEqual(start.second, 0)
        XCTAssertEqual(end.hour, 23); XCTAssertEqual(end.minute, 59); XCTAssertEqual(end.second, 59)
        XCTAssertEqual(interval.duration, 86399, accuracy: 1)
    }
    func testAnotherKhatmahBackwardProgressAndInvalidPagesCannotUnlock() {
        var value = contract()
        value.confirm(planID: UUID(), nextPage: 605)
        value.confirm(planID: value.planID, nextPage: 606)
        value.confirm(planID: value.planID, nextPage: 589)
        XCTAssertEqual(value.nextPage, 590)
        XCTAssertEqual(value.ward(at: date("2026-10-12T00:00:00Z"))?.last, 604)
        value.confirm(planID: value.planID, nextPage: 595)
        value.confirm(planID: value.planID, nextPage: 591)
        XCTAssertEqual(value.nextPage, 595)
        XCTAssertEqual(value.ward(at: date("2026-10-09T00:00:00Z"))?.first, 595)
    }
    func testRevisedActualPlanCanBeProtectedWithoutCountingOldPagesAgain() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Riyadh")!
        let now = date("2026-10-09T00:00:00Z")
        let plan = try KhatmahCalculator.make(first: 590, date: now, weekdays: Set(1...7), daily: 6, deadline: nil, reminder: nil, calendar: calendar)
        let read = try KhatmahCalculator.confirm(plan, first: 590, last: 595, date: now)
        let revised = try KhatmahCalculator.revised(read, date: now, weekdays: Set(1...7), daily: 3, deadline: nil, reminder: nil)
        let value = NoorKhatmahWardContract(plan: revised)
        XCTAssertTrue(value.valid)
        XCTAssertEqual(value.ward(at: now)?.first, 596)
        XCTAssertEqual(value.ward(at: now)?.last, 598)
    }
    func testExplicitErasureRemovesOnlyOwnedProtectionState() {
        let suite = "noor.protection.erase." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data([1, 2, 3]), forKey: NoorFocusPersistence.key)
        defaults.set("keep", forKey: "unrelated")
        XCTAssertTrue(NoorFocusPersistence.erase(defaults: defaults))
        XCTAssertNil(defaults.data(forKey: NoorFocusPersistence.key))
        XCTAssertEqual(defaults.string(forKey: "unrelated"), "keep")
        XCTAssertTrue(NoorFocusPersistence.erase(defaults: defaults))
        XCTAssertFalse(NoorFocusPersistence.erase(defaults: nil))
    }
    func testMalformedScheduleDoesNotShield() {
        let original = contract()
        let invalid = NoorKhatmahWardContract(planID: original.planID, firstPage: 590, timeZone: "Asia/Riyadh",
            days: [.init(date: date("2026-10-09T00:00:00Z"), first: 590, last: 595),
                   .init(date: date("2026-10-11T00:00:00Z"), first: 597, last: 604)], nextPage: 590)
        XCTAssertFalse(invalid.valid)
        XCTAssertNil(invalid.ward(at: date("2026-10-12T00:00:00Z")))
    }
}
