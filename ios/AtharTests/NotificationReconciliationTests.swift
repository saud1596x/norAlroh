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
}
