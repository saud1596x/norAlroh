import XCTest
@testable import Athar

final class WidgetTests: XCTestCase {
    @MainActor func testRetiredShortcutsAndNotificationsOpenSavedReaderPageWithoutChangingUserData() throws {
        let suite = "NoorRetiredRoutes." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(603, forKey: "noor.mushaf.lastPage")
        let sentinel = Data("preserved notes and bookmarks".utf8)
        defaults.set(sentinel, forKey: "noor.legacy.retention-test")
        let router = NoorWidgetRouter(defaults: defaults)
        for host in ["compare", "compare-verses", "similarities", "reflection", "daily-verse"] {
            XCTAssertTrue(router.open(try XCTUnwrap(URL(string: "nooralruh://\(host)/112/1"))))
            XCTAssertEqual(router.destination?.host, "reading")
            XCTAssertEqual(router.destination?.page, 603)
            XCTAssertTrue(router.openNotification(destination: host))
            XCTAssertEqual(router.destination?.host, "reading")
            XCTAssertEqual(router.destination?.page, 603)
            XCTAssertEqual(defaults.integer(forKey: "noor.mushaf.lastPage"), 603)
            XCTAssertEqual(defaults.data(forKey: "noor.legacy.retention-test"), sentinel)
        }
        let destination = router.destination?.id
        XCTAssertFalse(router.open(try XCTUnwrap(URL(string: "https://reflection/1"))))
        XCTAssertFalse(router.open(try XCTUnwrap(URL(string: "nooralruh://user:secret@reflection/1"))))
        XCTAssertEqual(router.destination?.id, destination)
    }
    @MainActor func testRetiredRouteFallsBackToValidPageForMissingOrDamagedPosition() throws {
        let suite = "NoorRetiredPosition." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let router = NoorWidgetRouter(defaults: defaults)
        XCTAssertTrue(router.openNotification(destination: "reflection"))
        XCTAssertEqual(router.destination?.page, 1)
        defaults.set(900, forKey: "noor.mushaf.lastPage")
        XCTAssertTrue(router.openNotification(destination: "compare"))
        XCTAssertEqual(router.destination?.page, 604)
    }
    @MainActor func testNotificationDestinationSurvivesColdStartAndRejectsUnknownPayload() {
        let router = NoorWidgetRouter()
        XCTAssertTrue(router.openNotification(destination: "prayers"))
        XCTAssertEqual(router.destination?.host, "prayers")
        let id = router.destination?.id
        XCTAssertFalse(router.openNotification(destination: "untrusted"))
        XCTAssertEqual(router.destination?.id, id)
        XCTAssertTrue(router.openNotification(destination: "dhikr"))
        XCTAssertEqual(router.destination?.host, "dhikr")
        XCTAssertNil(router.destination?.page)
    }
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
