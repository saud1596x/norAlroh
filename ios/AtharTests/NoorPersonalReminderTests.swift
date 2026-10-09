import XCTest
import UserNotifications
@testable import Athar

@MainActor private final class PersonalNotificationClient: PrayerNotificationClient {
    var allowed = true
    var holdPermission = false
    var permission: CheckedContinuation<Bool, Never>?
    var permissionStarted: (() -> Void)?
    var fail = false
    var removedDelivered: (([String]) -> Void)?
    var pending: [String: UNNotificationRequest] = [:]
    var delivered: [String] = []
    func requestAuthorization() async throws -> Bool {
        if !holdPermission { return allowed }
        return await withCheckedContinuation { permission = $0; permissionStarted?() }
    }
    func isAuthorized() async -> Bool { allowed }
    func pendingIdentifiers() async -> [String] { Array(pending.keys) }
    func deliveredIdentifiers() async -> [String] { delivered }
    func add(_ request: UNNotificationRequest) async throws {
        if fail { throw CocoaError(.fileWriteUnknown) }; pending[request.identifier] = request
    }
    func removePending(_ ids: [String]) { ids.forEach { pending.removeValue(forKey: $0) } }
    func removeDelivered(_ ids: [String]) { delivered.removeAll { ids.contains($0) }; removedDelivered?(ids) }
}

final class NoorPersonalReminderTests: XCTestCase {
    private func date(_ raw: String) -> Date { ISO8601DateFormatter().date(from: raw)! }
    func testLocalDaysFrequencyQuietOvernightAndNoDuplicates() throws {
        var preference = NoorReminderPreference(kind: .hifz)
        preference.enabled = true; preference.startMinute = 0; preference.endMinute = 1320
        preference.intervalMinutes = 120; preference.weekdays = [6, 7]
        preference.quietEnabled = true; preference.quietStart = 1320; preference.quietEnd = 420
        var archive = NoorReminderArchive(); archive.values["hifz"] = preference
        let now = date("2026-10-08T21:30:00Z") // Friday 00:30 Riyadh.
        let events = NoorPersonalReminderPlan.make(archive, now: now, timeZone: TimeZone(identifier: "Asia/Riyadh")!)
        XCTAssertEqual(events.count, 14)
        XCTAssertEqual(events.first?.date, date("2026-10-09T05:00:00Z"))
        XCTAssertTrue(events.allSatisfy { $0.date > now })
        XCTAssertEqual(Set(events.map(\.id)).count, events.count)
        XCTAssertEqual(events.map(\.date), events.map(\.date).sorted())
        preference.quietEnd = preference.quietStart; archive.values["hifz"] = preference
        XCTAssertTrue(NoorPersonalReminderPlan.make(archive, now: now).isEmpty)
        preference.weekdays = []; archive.values["hifz"] = preference
        XCTAssertFalse(archive.valid); XCTAssertTrue(NoorPersonalReminderPlan.make(archive, now: now).isEmpty)
    }
    func testDSTMissingAndRepeatedTimeProduceOneSlotPerLocalDay() {
        var preference = NoorReminderPreference(kind: .morning)
        preference.enabled = true; preference.startMinute = 150; preference.endMinute = 150
        var archive = NoorReminderArchive(); archive.values["morning"] = preference
        let zone = TimeZone(identifier: "America/New_York")!
        let spring = NoorPersonalReminderPlan.make(archive, now: date("2026-03-08T05:00:00Z"), timeZone: zone)
        XCTAssertEqual(spring.count, 7); XCTAssertEqual(spring.first?.date, date("2026-03-08T07:00:00Z"))
        preference.startMinute = 90; preference.endMinute = 90; archive.values["morning"] = preference
        let fall = NoorPersonalReminderPlan.make(archive, now: date("2026-11-01T04:00:00Z"), timeZone: zone)
        XCTAssertEqual(fall.count, 7); XCTAssertEqual(fall.first?.date, date("2026-11-01T05:30:00Z"))
        XCTAssertEqual(Set(fall.map(\.id)).count, fall.count)
    }
    @MainActor func testIndependentPersistenceBudgetDeliveredDedupDisableAndFailure() async throws {
        let suite = "Noor.Personal." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
        let client = PersonalNotificationClient(); let store = AtharStore(directory: folder)
        for i in 0..<55 { client.pending["foreign.\(i)"] = .init(identifier: "foreign.\(i)", content: UNMutableNotificationContent(), trigger: nil) }
        let now = date("2026-10-09T00:00:00Z")
        let service = PrayerNotifications(client: client, defaults: defaults, now: { now })
        var dua = NoorReminderPreference(kind: .dua); dua.enabled = true
        await service.setReminder(.dua, preference: dua, store: store)
        var hifz = NoorReminderPreference(kind: .hifz); hifz.enabled = true
        await service.setReminder(.hifz, preference: hifz, store: store)
        XCTAssertLessThanOrEqual(client.pending.count, 64)
        XCTAssertEqual(client.pending.keys.filter { $0.hasPrefix("foreign.") }.count, 55)
        XCTAssertEqual(service.personalCounts.values.reduce(0, +), 9)
        XCTAssertNotNil(service.message)
        let event = try XCTUnwrap(client.pending.values.first { $0.content.userInfo["destination"] as? String == "review" })
        XCTAssertEqual((event.trigger as? UNCalendarNotificationTrigger)?.repeats, false)
        XCTAssertNotNil((event.trigger as? UNCalendarNotificationTrigger)?.dateComponents.calendar)
        client.delivered = [event.identifier]
        let restored = PrayerNotifications(client: client, defaults: defaults, now: { now })
        await restored.refresh(store: store)
        XCTAssertEqual(restored.reminder(.hifz), hifz); XCTAssertNil(client.pending[event.identifier])
        hifz.enabled = false; await restored.setReminder(.hifz, preference: hifz, store: store)
        XCTAssertFalse(client.pending.keys.contains { $0.hasPrefix("noor.personal.hifz.") })
        XCTAssertTrue(client.delivered.isEmpty)
        XCTAssertTrue(client.pending.keys.contains { $0.hasPrefix("noor.personal.dua.") })
        client.fail = true; await restored.refresh(store: store)
        XCTAssertEqual(client.pending.count, 55); XCTAssertTrue(restored.personalCounts.isEmpty)
        XCTAssertNotNil(restored.message)
    }
    @MainActor func testDisableDuringPermissionAndUnreadableArchiveCannotBeOverwritten() async throws {
        let suite = "Noor.Personal." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
        let client = PersonalNotificationClient(); client.holdPermission = true
        let store = AtharStore(directory: folder), service = PrayerNotifications(client: client, defaults: defaults)
        let started = expectation(description: "Real controller requested permission")
        client.permissionStarted = { started.fulfill() }
        var value = NoorReminderPreference(kind: .evening); value.enabled = true
        let task = Task { await service.setReminder(.evening, preference: value, store: store) }
        await fulfillment(of: [started], timeout: 3)
        value.enabled = false; await service.setReminder(.evening, preference: value, store: store)
        client.permission?.resume(returning: true); await task.value
        XCTAssertFalse(service.reminder(.evening).enabled); XCTAssertTrue(client.pending.isEmpty)
        let damaged = Data("damaged preferences".utf8); defaults.set(damaged, forKey: "noor.personalReminders.v1")
        let broken = PrayerNotifications(client: client, defaults: defaults)
        await broken.setReminder(.dua, preference: .init(kind: .dua), store: store)
        XCTAssertTrue(broken.personalUnreadable); XCTAssertEqual(broken.personalExport, damaged)
        XCTAssertEqual(defaults.data(forKey: "noor.personalReminders.v1"), damaged)
    }
    @MainActor func testDeniedPermissionAndExplicitErasePreserveForeignRequests() async throws {
        let suite = "Noor.Personal." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
        let client = PersonalNotificationClient(); client.allowed = false
        let service = PrayerNotifications(client: client, defaults: defaults)
        let store = AtharStore(directory: folder)
        var value = NoorReminderPreference(kind: .morning); value.enabled = true
        await service.setReminder(.morning, preference: value, store: store)
        XCTAssertFalse(service.reminder(.morning).enabled); XCTAssertNil(service.personalExport)
        XCTAssertNotNil(service.message); XCTAssertTrue(client.pending.isEmpty)
        client.allowed = true; await service.setReminder(.morning, preference: value, store: store)
        let owned = try XCTUnwrap(client.pending.keys.first)
        client.pending["foreign"] = .init(identifier: "foreign", content: UNMutableNotificationContent(), trigger: nil)
        client.delivered = [owned, "foreign.delivered"]
        let cancelled = expectation(description: "Owned delivered notification cancelled")
        client.removedDelivered = { ids in if ids.contains(owned) { cancelled.fulfill() } }
        service.erasePreferences(); await fulfillment(of: [cancelled], timeout: 3)
        XCTAssertNil(service.personalExport); XCTAssertTrue(service.personal.values.isEmpty)
        XCTAssertEqual(Set(client.pending.keys), ["foreign"]); XCTAssertEqual(client.delivered, ["foreign.delivered"])
    }
    @MainActor func testExplicitSalawatEditorAdoptsOneScheduleWithoutDuplicatingLegacy() async throws {
        let suite = "Noor.Personal." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
        let client = PersonalNotificationClient(), store = AtharStore(directory: folder)
        let now = date("2026-10-09T00:00:00Z")
        let service = PrayerNotifications(client: client, defaults: defaults, now: { now })
        await service.setSalawatInterval(2, store: store)
        await service.setSalawatEnabled(true, store: store)
        XCTAssertEqual(service.salawatCount, 7)
        var value = NoorReminderPreference(kind: .salawat); value.enabled = true
        await service.setReminder(.salawat, preference: value, store: store)
        XCTAssertFalse(service.salawat.enabled); XCTAssertEqual(service.salawatCount, 0)
        XCTAssertFalse(client.pending.keys.contains { $0.hasPrefix(SalawatNotificationPlan.prefix) })
        XCTAssertTrue(client.pending.values.allSatisfy { $0.content.userInfo["destination"] as? String == "salawat" })
        XCTAssertEqual(service.personalCounts["salawat"], 7)
        XCTAssertEqual(PrayerNotifications(client: client, defaults: defaults).reminder(.salawat), value)
    }
    @MainActor func testReminderRoutesOpenActualSectionsAndRejectUnknownPayload() {
        let router = NoorWidgetRouter()
        for kind in NoorReminderKind.allCases {
            XCTAssertTrue(router.openNotification(destination: kind.destination))
            XCTAssertEqual(router.destination?.host, kind.destination)
        }
        XCTAssertFalse(router.openNotification(destination: "personal-secret"))
    }
}
