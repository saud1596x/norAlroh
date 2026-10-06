import XCTest
@testable import Athar

final class WidgetTests: XCTestCase {
    func testWidgetAndNotificationPrayerInputsUseIdenticalTimesAcrossMidnight() throws {
        let data = DeviceData()
        let now = Date(timeIntervalSince1970: 1791320340)
        let app = PrayerCalculator.rows(data: data, date: now)
        let shared = PrayerCalculator.rows(data: PrayerCalculator.inputs(data), date: now)
        XCTAssertEqual(app.map(\.date), shared.map(\.date))
        let afterIsha = try XCTUnwrap(app.last?.date).addingTimeInterval(60)
        let next = try XCTUnwrap(PrayerCalculator.next(data: PrayerCalculator.inputs(data), now: afterIsha))
        XCTAssertEqual(next.id, "fajr")
        XCTAssertGreaterThan(next.date, afterIsha)
    }
    func testWidgetDoesNotCarryYesterdayWardCountIntoToday() throws {
        let now = Date()
        let tomorrow = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: now))
        let value = NoorWidgetSnapshot(version: 1, updated: now, prayer: PrayerCalculator.inputs(DeviceData()), page: 604,
            dailyTarget: 3, practiced: [MemorizationProgress.dayKey(now): 2],
            reviewDates: [Calendar.current.startOfDay(for: tomorrow)], dua: "", duaTitle: "")
        XCTAssertEqual(value.completed(at: now), 2)
        XCTAssertEqual(value.completed(at: tomorrow), 0)
        XCTAssertEqual(value.due(at: now), 0)
        XCTAssertEqual(value.due(at: tomorrow), 1)
    }
    @MainActor func testColdStartDestinationPersistsUntilRootConsumesItAndRejectsInvalidPages() throws {
        let router = NoorWidgetRouter()
        XCTAssertTrue(router.open(try XCTUnwrap(URL(string: "nooralruh://reading/604"))))
        XCTAssertEqual(router.destination?.page, 604)
        XCTAssertEqual(router.destination?.host, "reading")
        XCTAssertFalse(router.open(try XCTUnwrap(URL(string: "nooralruh://reading/605"))))
        XCTAssertEqual(router.destination?.page, 604)
        XCTAssertFalse(router.open(try XCTUnwrap(URL(string: "https://reading/1"))))
        XCTAssertFalse(router.open(try XCTUnwrap(URL(string: "nooralruh://untrusted"))))
    }
}
