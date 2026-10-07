import XCTest
import UserNotifications
@testable import Athar

@MainActor private final class TestNotificationClient: PrayerNotificationClient {
    var permission: CheckedContinuation<Bool, Never>?
    var permissionStarted: (() -> Void)?
    var holdPermission = false
    var pending: [String: UNNotificationRequest] = [:]
    var delivered: [String] = []
    var failAdding = false
    func requestAuthorization() async throws -> Bool {
        if !holdPermission { return true }
        return await withCheckedContinuation { permission = $0; permissionStarted?() }
    }
    func isAuthorized() async -> Bool { true }
    func pendingIdentifiers() async -> [String] { Array(pending.keys) }
    func deliveredIdentifiers() async -> [String] { delivered }
    func add(_ request: UNNotificationRequest) async throws {
        if failAdding { throw CocoaError(.fileWriteUnknown) }
        pending[request.identifier] = request
    }
    func removePending(_ ids: [String]) { for id in ids { pending.removeValue(forKey: id) } }
    func removeDelivered(_ ids: [String]) { delivered.removeAll { ids.contains($0) } }
}

final class NotificationReconciliationTests: XCTestCase {
    @MainActor func testDisablingDuringPermissionDoesNotReenableNotifications() async throws {
        let suite = "NoorNotifications." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
        let client = TestNotificationClient(); client.holdPermission = true
        let started = expectation(description: "Permission request started")
        client.permissionStarted = { started.fulfill() }
        let notifications = PrayerNotifications(client: client, defaults: defaults)
        let store = AtharStore(directory: folder)
        let task = Task { await notifications.enable(store: store) }
        await fulfillment(of: [started], timeout: 3)
        notifications.disable()
        client.permission?.resume(returning: true)
        await task.value
        XCTAssertFalse(notifications.enabled)
        XCTAssertFalse(defaults.bool(forKey: "athar.prayerNotifications"))
        XCTAssertTrue(client.pending.isEmpty)
    }
    @MainActor func testPreferenceChangeReplacesOnlyOwnRequestsAndFailureIsReported() async throws {
        let suite = "NoorNotifications." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
        let client = TestNotificationClient()
        let unrelated = UNNotificationRequest(identifier: "personal.reminder", content: UNMutableNotificationContent(), trigger: nil)
        client.pending[unrelated.identifier] = unrelated
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-04T10:00:00Z"))
        let notifications = PrayerNotifications(client: client, defaults: defaults, now: { now })
        let store = AtharStore(directory: folder)
        await notifications.enable(store: store)
        XCTAssertTrue(notifications.enabled)
        XCTAssertGreaterThan(notifications.scheduledCount, 0)
        await notifications.setSound(false, store: store)
        let owned = client.pending.values.filter { $0.identifier.hasPrefix(PrayerNotificationPlan.prefix) }
        XCTAssertTrue(owned.allSatisfy { $0.content.sound == nil })
        XCTAssertNotNil(client.pending[unrelated.identifier])
        client.failAdding = true
        await notifications.refresh(store: store)
        XCTAssertFalse(notifications.enabled)
        XCTAssertEqual(notifications.scheduledCount, 0)
        XCTAssertNotNil(notifications.message)
        XCTAssertNotNil(client.pending[unrelated.identifier])
        XCTAssertFalse(client.pending.keys.contains { $0.hasPrefix(PrayerNotificationPlan.prefix) })
    }
    @MainActor func testIndependentSalawatBudgetAndLocationReplacementSurviveRestart() async throws {
        let suite = "NoorNotifications." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
        let client = TestNotificationClient()
        for index in 0..<14 { client.pending["foreign.\(index)"] = .init(identifier: "foreign.\(index)", content: UNMutableNotificationContent(), trigger: nil) }
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-04T10:00:00Z"))
        let notifications = PrayerNotifications(client: client, defaults: defaults, now: { now })
        let store = AtharStore(directory: folder)
        await notifications.enable(store: store)
        await notifications.setSalawatInterval(2, store: store)
        await notifications.setSalawatEnabled(true, store: store)
        XCTAssertLessThanOrEqual(client.pending.count, 64)
        XCTAssertEqual(notifications.salawatCount, 7)
        XCTAssertTrue(client.pending.values.filter { $0.identifier.hasPrefix(SalawatNotificationPlan.prefix) }.allSatisfy {
            $0.content.sound == nil && ($0.trigger as? UNCalendarNotificationTrigger)?.repeats == true
        })
        func scheduledTimes() -> [String: Date] {
            client.pending.values.filter { $0.identifier.hasPrefix(PrayerNotificationPlan.prefix) }
                .reduce(into: [String: Date]()) { result, request in
                    guard let trigger = request.trigger as? UNCalendarNotificationTrigger else { return }
                    var calendar = Calendar(identifier: .gregorian)
                    calendar.timeZone = trigger.dateComponents.timeZone ?? .current
                    result[request.identifier] = calendar.date(from: trigger.dateComponents)
                }
        }
        let oldTimes = scheduledTimes()
        let city = City(id: "location.current", name: "دبي", latitude: 25.2048, longitude: 55.2708,
            timeZone: "Asia/Dubai", region: "دبي", countryCode: "AE", sourceID: nil)
        XCTAssertTrue(store.update { $0.city = city })
        await notifications.refresh(store: store)
        let prayers = client.pending.values.filter { $0.identifier.hasPrefix(PrayerNotificationPlan.prefix) }
        XCTAssertTrue(prayers.allSatisfy { $0.content.body.contains("دبي") })
        XCTAssertFalse(oldTimes.isEmpty)
        XCTAssertNotEqual(oldTimes, scheduledTimes())
        let restored = PrayerNotifications(client: client, defaults: defaults, now: { now })
        await restored.refresh(store: store)
        XCTAssertTrue(restored.salawat.enabled); XCTAssertEqual(restored.salawatCount, 7)
        await restored.setSalawatEnabled(false, store: store)
        XCTAssertTrue(restored.enabled)
        XCTAssertFalse(client.pending.keys.contains { $0.hasPrefix(SalawatNotificationPlan.prefix) })
        XCTAssertEqual(client.pending.keys.filter { $0.hasPrefix("foreign.") }.count, 14)
        XCTAssertLessThanOrEqual(client.pending.count, 64)
    }

    @MainActor func testDeliveredPrayerIsNotScheduledAgainAfterClockOrLocationChange() async throws {
        let suite = "NoorNotifications." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-04T10:00:00Z"))
        let client = TestNotificationClient()
        let store = AtharStore(directory: folder)
        let event = try XCTUnwrap(PrayerNotificationPlan.make(data: store.data, preferences: .init(), now: now).first)
        client.delivered = [event.id]
        let notifications = PrayerNotifications(client: client, defaults: defaults, now: { now })
        await notifications.enable(store: store)
        XCTAssertTrue(notifications.enabled)
        XCTAssertNil(client.pending[event.id])
        XCTAssertGreaterThan(notifications.scheduledCount, 0)
        await notifications.refresh(store: store)
        XCTAssertNil(client.pending[event.id])
        XCTAssertEqual(Set(client.pending.keys).count, notifications.scheduledCount)
        XCTAssertEqual(client.delivered, [event.id])
    }

}
