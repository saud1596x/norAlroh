import XCTest
import UserNotifications
@testable import Athar

/// Literal civil-time fixtures test the policy, not astronomical accuracy or
/// real device alarm delivery. Existing PrayerCalculator tests remain separate.
final class FixedPrayerPolicyTests: XCTestCase {
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    func testDuhaUsesMiddleOfValidSunriseAndNoonMargins() {
        XCTAssertEqual(FixedPrayerPolicy.duhaDate(sunrise: date("2026-10-31T03:00:00Z"),
            dhuhr: date("2026-10-31T09:00:00Z")), date("2026-10-31T06:00:00Z"))
        XCTAssertNil(FixedPrayerPolicy.duhaDate(sunrise: date("2026-10-31T08:20:00Z"),
            dhuhr: date("2026-10-31T09:00:00Z")))
    }
    func testWitrBelongsToNightAcrossMidnightAndAvoidsNextFajr() {
        XCTAssertEqual(FixedPrayerPolicy.witrDate(isha: date("2026-10-31T23:30:00Z"),
            nextFajr: date("2026-11-01T05:00:00Z")), date("2026-11-01T00:30:00Z"))
        // 20-minute admissible window: midpoint after Isha+5, before Fajr-15.
        XCTAssertEqual(FixedPrayerPolicy.witrDate(isha: date("2026-10-31T23:30:00Z"),
            nextFajr: date("2026-11-01T00:10:00Z")), date("2026-10-31T23:45:00Z"))
        XCTAssertNil(FixedPrayerPolicy.witrDate(isha: date("2026-10-31T23:30:00Z"),
            nextFajr: date("2026-10-31T23:45:00Z")))
    }
    func testFixedSalawatHasOneSilentRepeatingFiveMinuteTrigger() throws {
        let request = FixedPrayerPolicy.salawatRequest()
        let trigger = try XCTUnwrap(request.trigger as? UNTimeIntervalNotificationTrigger)
        XCTAssertEqual(trigger.timeInterval, 300)
        XCTAssertTrue(trigger.repeats)
        XCTAssertNil(request.content.sound)
        XCTAssertNil(request.content.badge)
        XCTAssertEqual(request.content.userInfo["destination"] as? String, "salawat")
    }
    @MainActor func testUnconfirmedDefaultCityCannotCreatePrayerAlerts() throws {
        let suite = "FixedLocation." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let data = DeviceData()
        XCTAssertFalse(PrayerNotifications.hasTrustedLocation(data, defaults: defaults))
        defaults.set(data.city.id, forKey: "noor.fixedPrayer.locationConfirmedCity.v2")
        XCTAssertTrue(PrayerNotifications.hasTrustedLocation(data, defaults: defaults))
        var changed = data
        changed.city = City(id: "location.current", name: "آخر موقع", latitude: 25.2,
            longitude: 55.3, timeZone: "Asia/Dubai", region: nil, countryCode: "AE", sourceID: nil)
        XCTAssertFalse(PrayerNotifications.hasTrustedLocation(changed, defaults: defaults))
        changed.locationUpdatedAt = date("2026-10-31T12:00:00Z")
        XCTAssertTrue(PrayerNotifications.hasTrustedLocation(changed, defaults: defaults,
            now: date("2026-10-31T12:01:00Z")))
        changed.locationUpdatedAt = date("2026-10-31T13:00:00Z")
        XCTAssertFalse(PrayerNotifications.hasTrustedLocation(changed, defaults: defaults,
            now: date("2026-10-31T12:01:00Z")))
    }
    func testThreeCivilDaysContainFiveExactPrayersAndNoSunriseAlarm() {
        let data = DeviceData()
        let events = FixedPrayerPolicy.make(data: data, now: date("2026-10-30T21:00:00Z"))
        let prayers = events.filter { $0.kind == .prayer }
        XCTAssertEqual(prayers.count, 15)
        XCTAssertEqual(Set(prayers.compactMap(\.prayerID)), ["fajr", "dhuhr", "asr", "maghrib", "isha"])
        XCTAssertTrue(events.allSatisfy { $0.fireDate > date("2026-10-30T21:00:00Z") })
        XCTAssertEqual(Set(events.map(\.id)).count, events.count)
        XCTAssertLessThanOrEqual(events.filter { $0.kind != .prayer }.count, 7)
    }
    func testChangingTimeZoneKeepsEachPrayerAtItsCalculatedInstantWithoutAdvance() {
        var data = DeviceData()
        data.city = City(id: "location.current", name: "نيويورك", latitude: 40.7, longitude: -74,
            timeZone: "America/New_York", region: nil, countryCode: "US", sourceID: nil)
        let now = date("2026-11-01T04:00:00Z") // DST fall-back local midnight.
        let events = FixedPrayerPolicy.make(data: data, now: now).filter { $0.kind == .prayer }
        XCTAssertEqual(events.count, 15)
        XCTAssertEqual(Set(events.map(\.id)).count, 15)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        for offset in 0..<3 {
            let day = calendar.date(byAdding: .day, value: offset, to: now)!
            let expected = PrayerCalculator.rows(data: data, date: day).filter { !$0.sunrise }.map(\.date)
            let actual = events.filter { calendar.isDate($0.fireDate, inSameDayAs: day) }.map(\.fireDate)
            XCTAssertEqual(actual.sorted(), expected.sorted())
        }
    }
    func testHistoryFloorNeverMovesBackwardAndOnlySettledOldRecordsArePruned() {
        let now = date("2026-10-31T00:00:00Z")
        let floor = FixedPrayerPolicy.historyFloor(previous: nil, now: now)
        XCTAssertEqual(floor, date("2026-08-28T00:00:00Z"))
        XCTAssertEqual(FixedPrayerPolicy.historyFloor(previous: floor,
            now: date("2026-07-01T00:00:00Z")), floor)
        let old = date("2026-08-01T00:00:00Z"), future = date("2026-11-01T00:00:00Z")
        let active = UUID(), pending = UUID(), removed = UUID(), futureRemoved = UUID()
        let records: [String: PrayerAlarmRecord] = [
            "old": .init(id: removed, fireDate: old, state: .observedRemoved),
            "pending": .init(id: pending, fireDate: old, state: .pending),
            "failed-cancel": .init(id: active, fireDate: old, state: .scheduled),
            "future-removed": .init(id: futureRemoved, fireDate: future, state: .observedRemoved)]
        let retained = FixedPrayerPolicy.retainAlarmHistory(records, floor: floor, activeIDs: [active])
        XCTAssertEqual(Set(retained.keys), ["pending", "failed-cancel", "future-removed"])
    }
    func testEarlyUTCPrayerRetainsItsCivilDayIdentityAcrossTheHistoryFloor() {
        let id = "noor.fixedPrayer.v2.c1.2026-8-28.fajr"
        let record = PrayerAlarmRecord(id: UUID(), fireDate: date("2026-08-27T19:00:00Z"), state: .observedRemoved)
        let floor = date("2026-08-28T00:00:00Z")
        XCTAssertNotNil(FixedPrayerPolicy.retainAlarmHistory([id: record], floor: floor, activeIDs: [])[id])
        XCTAssertNil(FixedPrayerPolicy.retainAlarmHistory([id: record],
            floor: date("2026-08-30T00:00:01Z"), activeIDs: [])[id])
    }
}
