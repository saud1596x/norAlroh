import XCTest
@testable import Athar

final class PrayerNotificationPlanTests: XCTestCase {
    func testPlanExcludesSunriseAndPastDatesAndStaysBelowSystemLimit() {
        let now = ISO8601DateFormatter().date(from: "2026-10-04T10:00:00Z")!
        let plan = PrayerNotificationPlan.make(data: DeviceData(), preferences: .init(), now: now)
        XCTAssertFalse(plan.isEmpty)
        XCTAssertLessThanOrEqual(plan.count, 50)
        XCTAssertTrue(plan.allSatisfy { !$0.prayer.sunrise && $0.fireDate > now })
        XCTAssertEqual(Set(plan.map(\.id)).count, plan.count)
        XCTAssertEqual(plan.map(\.fireDate), plan.map(\.fireDate).sorted())
    }
    func testOnlySelectedPrayersAreScheduledAtRequestedAdvance() {
        var preferences = PrayerNotificationPreferences()
        preferences.prayers = ["fajr": true]
        preferences.advanceMinutes = 10
        preferences.soundEnabled = false
        let plan = PrayerNotificationPlan.make(data: DeviceData(), preferences: preferences,
                                              now: ISO8601DateFormatter().date(from: "2026-10-04T22:00:00Z")!)
        XCTAssertFalse(plan.isEmpty)
        XCTAssertTrue(plan.allSatisfy { $0.prayer.id == "fajr" && !$0.soundEnabled })
        for event in plan { XCTAssertEqual(event.prayer.date.timeIntervalSince(event.fireDate), 600, accuracy: 0.1) }
    }
    func testSaudiDayBoundaryUsesRiyadhTimezone() {
        let now = ISO8601DateFormatter().date(from: "2026-10-24T21:30:00Z")!
        var data = DeviceData()
        data.city = City.defaultCity
        let plan = PrayerNotificationPlan.make(data: data, preferences: .init(), now: now)
        XCTAssertEqual(plan.filter { $0.prayer.id == "fajr" }.count, 10)
        XCTAssertTrue(plan.allSatisfy { $0.cityName == "مكة المكرمة" && $0.fireDate > now })
    }
    @MainActor
    func testBundledAdhkarReferencesAndTargetsAreAvailable() {
        let content = AdhkarContent.load()
        XCTAssertNotNil(content)
        XCTAssertEqual(content?.groups.count, 132)
        XCTAssertEqual(content?.entries.count, 267)
        XCTAssertEqual(content?.entries.first { $0.id == "hisn-27-75" }?.target, 1)
        XCTAssertTrue(content?.entries.allSatisfy { $0.sourceURL.host == "www.hisnmuslim.com" } == true)
        XCTAssertEqual(Set(content?.groups.flatMap(\.items) ?? []).count, 267)
    }
}
