import XCTest
@testable import Athar

final class FridayTests: XCTestCase {
    func testFridayOnlyUsesCityTimezoneAtMidnight() {
        let before = ISO8601DateFormatter().date(from: "2026-10-08T20:59:00Z")!
        let after = before.addingTimeInterval(120)
        XCTAssertFalse(FridayPlan.active(at: before, city: .defaultCity))
        XCTAssertTrue(FridayPlan.active(at: after, city: .defaultCity))
    }
    func testUpcomingFridayEventsRespectQuietHoursAndNotificationBudget() {
        let now = ISO8601DateFormatter().date(from: "2026-10-06T15:00:00Z")!
        let p = FridayPreferences()
        let events = FridayPlan.events(data: DeviceData(), preferences: p, now: now)
        XCTAssertEqual(events.filter(\.prayer).count, 5)
        XCTAssertLessThanOrEqual(events.count + PrayerNotificationPlan.maximumRequests, 64)
        XCTAssertEqual(Set(events.map(\.id)).count, events.count)
        let c = FridayPlan.calendar(for: .defaultCity)
        for event in events {
            XCTAssertGreaterThan(event.date, now)
            XCTAssertTrue(FridayPlan.active(at: event.date, city: .defaultCity))
            if event.id.contains("salawat") {
                let parts = c.dateComponents([.hour, .minute], from: event.date)
                let minutes = parts.hour! * 60 + parts.minute!
                XCTAssertTrue(minutes < p.mosqueMinutes - 30 || minutes > p.mosqueMinutes + 90)
            }
        }
    }
    @MainActor func testCounterCannotRunOutsideFridayAndKeepsEachWeekSeparate() throws {
        let suite = "NoorFriday." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let friday = ISO8601DateFormatter().date(from: "2026-10-09T09:00:00Z")!
        let thursday = friday.addingTimeInterval(-86400)
        let store = FridayStore(defaults: defaults)
        store.count(at: thursday, city: .defaultCity, delta: 1)
        XCTAssertEqual(store.day(at: thursday, city: .defaultCity).count, 0)
        store.count(at: friday, city: .defaultCity, delta: 1)
        store.set("ghusl", completed: true, at: friday, city: .defaultCity)
        let reopened = FridayStore(defaults: defaults)
        XCTAssertEqual(reopened.day(at: friday, city: .defaultCity).count, 1)
        XCTAssertTrue(reopened.day(at: friday, city: .defaultCity).completed.contains("ghusl"))
        XCTAssertEqual(reopened.day(at: friday.addingTimeInterval(7 * 86400), city: .defaultCity).count, 0)
    }
    @MainActor func testCloudRestoreValidatesBeforeWritingAndDoesNotCompleteTodaysWard() throws {
        let suite = "NoorCloudRestore." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let source = MemorizationStore(defaults: defaults)
        XCTAssertTrue(source.finish(chapter: 1, answers: [.init(ayah: 1, assessment: "remembered", revealed: false, hints: 0)]))
        let backup = MemorizationCloudBackup(version: 1, plan: source.plan, archive: .init(version: 1, history: source.history, progress: source.progress))
        XCTAssertTrue(source.restore(backup))
        XCTAssertEqual(source.completedToday(), 0)
        XCTAssertEqual(source.progress.verses["1:1"]?.attempts, 1)
        let before = defaults.data(forKey: "noor.memorization.archive")
        let invalid = MemorizationCloudBackup(version: 1, plan: .init(chapter: 115, from: 1, to: 7, daily: 3), archive: backup.archive)
        XCTAssertFalse(source.restore(invalid))
        XCTAssertEqual(defaults.data(forKey: "noor.memorization.archive"), before)
    }
}
