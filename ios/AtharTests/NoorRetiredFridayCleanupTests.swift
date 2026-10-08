import XCTest
@testable import Athar

@MainActor private final class RetiredNotificationsFixture: NoorRetiredNotificationClient {
    var pending = ["noor.friday.prayer.fajr", "noor.prayer.fajr", "noor.salawat.1", "noor.khatmah.1"]
    var delivered = ["noor.friday.salawat.1", "noor.dhikr.1"]
    var removedPending: [String] = []
    var removedDelivered: [String] = []
    var pendingReads = 0
    var suspend = false
    var continuation: CheckedContinuation<Void, Never>?
    var onSuspend: (() -> Void)?
    func pendingIDs() async -> [String] {
        pendingReads += 1
        if suspend { await withCheckedContinuation { continuation = $0; onSuspend?() } }
        return pending
    }
    func deliveredIDs() async -> [String] { delivered }
    func removePending(_ ids: [String]) { removedPending += ids; pending.removeAll { ids.contains($0) } }
    func removeDelivered(_ ids: [String]) { removedDelivered += ids; delivered.removeAll { ids.contains($0) } }
}

@MainActor private final class RetiredAlarmsFixture: NoorRetiredAlarmClient {
    enum Failure: Error { case unavailable }
    var available = true
    var active: Set<UUID> = []
    var failures: Set<UUID> = []
    var listingFails = false
    var reads = 0
    var cancellations: [UUID] = []
    func currentIDs() throws -> Set<UUID> {
        reads += 1
        if listingFails { throw Failure.unavailable }
        return active
    }
    func cancel(_ id: UUID) throws {
        cancellations.append(id)
        if failures.contains(id) { throw Failure.unavailable }
        active.remove(id)
    }
}

final class NoorRetiredFridayCleanupTests: XCTestCase {
    @MainActor private func withDefaults(_ body: (UserDefaults) async throws -> Void) async throws {
        let suite = "NoorRetiredFriday." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "noor.friday.notifications")
        defaults.set(true, forKey: "noor.friday.alarms")
        defaults.set(Data("saved-personal-friday-record".utf8), forKey: "noor.friday.days")
        defaults.set(Data("old-preferences".utf8), forKey: "noor.friday.preferences")
        defaults.set(Data("memorization-archive".utf8), forKey: "noor.memorization.archive")
        defaults.set(603, forKey: "noor.mushaf.lastPage")
        try await body(defaults)
    }

    @MainActor func testCancelsOnlyRetiredPendingAndDeliveredRequestsPreservingUserRecords() async throws {
        try await withDefaults { defaults in
            let notifications = RetiredNotificationsFixture(), alarms = RetiredAlarmsFixture()
            let before = defaults.dictionaryRepresentation()
            let cleanup = NoorRetiredFridayCleanup(defaults: defaults, notifications: notifications, alarms: alarms)
            XCTAssertFalse(defaults.bool(forKey: "noor.friday.notifications"))
            XCTAssertFalse(defaults.bool(forKey: "noor.friday.alarms"))
            await cleanup.cleanup()
            XCTAssertEqual(notifications.removedPending, ["noor.friday.prayer.fajr"])
            XCTAssertEqual(notifications.removedDelivered, ["noor.friday.salawat.1"])
            XCTAssertEqual(notifications.pending, ["noor.prayer.fajr", "noor.salawat.1", "noor.khatmah.1"])
            XCTAssertEqual(notifications.delivered, ["noor.dhikr.1"])
            XCTAssertEqual(alarms.reads, 0, "No owned IDs: do not inspect alarm authorization")
            for key in ["noor.friday.days", "noor.friday.preferences", "noor.memorization.archive"] {
                XCTAssertEqual(defaults.data(forKey: key), before[key] as? Data)
            }
            XCTAssertEqual(defaults.integer(forKey: "noor.mushaf.lastPage"), 603)
            await cleanup.cleanup()
            XCTAssertEqual(notifications.removedPending.count, 1, "Repeated cleanup cannot recreate old reminders")
            XCTAssertNil(cleanup.message)
        }
    }

    @MainActor func testPartialAlarmFailureRetainsFailedIDsAndRetriesAfterRelaunch() async throws {
        try await withDefaults { defaults in
            let success = UUID(), failure = UUID(), other = UUID(), alreadyGone = UUID()
            let notifications = RetiredNotificationsFixture(), alarms = RetiredAlarmsFixture()
            alarms.active = [success, failure, other]; alarms.failures = [failure]
            defaults.set([success.uuidString, failure.uuidString, failure.uuidString, alreadyGone.uuidString], forKey: NoorRetiredFridayCleanup.alarmIDsKey)
            let cleanup = NoorRetiredFridayCleanup(defaults: defaults, notifications: notifications, alarms: alarms)
            await cleanup.cleanup()
            XCTAssertEqual(Set(alarms.cancellations), [success, failure])
            XCTAssertEqual(alarms.cancellations.count, 2, "Duplicate IDs must not cancel twice")
            XCTAssertEqual(alarms.active, [failure, other])
            XCTAssertEqual(defaults.stringArray(forKey: NoorRetiredFridayCleanup.alarmIDsKey), [failure.uuidString, failure.uuidString])
            XCTAssertNotNil(cleanup.message)
            alarms.failures = []
            let reopened = NoorRetiredFridayCleanup(defaults: defaults, notifications: notifications, alarms: alarms)
            await reopened.cleanup()
            XCTAssertEqual(alarms.active, [other])
            XCTAssertNil(defaults.object(forKey: NoorRetiredFridayCleanup.alarmIDsKey))
            XCTAssertNotNil(defaults.data(forKey: "noor.friday.days"))
            XCTAssertNil(reopened.message)
        }
    }

    @MainActor func testFailedListingOrUnavailableOSNeverForgetsCancellationIDs() async throws {
        try await withDefaults { defaults in
            let raw = [UUID().uuidString, "malformed-legacy-value"]
            defaults.set(raw, forKey: NoorRetiredFridayCleanup.alarmIDsKey)
            let alarms = RetiredAlarmsFixture(); alarms.listingFails = true
            let cleanup = NoorRetiredFridayCleanup(defaults: defaults, notifications: RetiredNotificationsFixture(), alarms: alarms)
            await cleanup.cleanup()
            XCTAssertEqual(defaults.stringArray(forKey: NoorRetiredFridayCleanup.alarmIDsKey), raw)
            XCTAssertNotNil(cleanup.message)
            alarms.available = false
            await cleanup.cleanup()
            XCTAssertEqual(alarms.reads, 1)
            XCTAssertEqual(defaults.stringArray(forKey: NoorRetiredFridayCleanup.alarmIDsKey), raw)
            XCTAssertTrue(alarms.cancellations.isEmpty)
        }
    }

    @MainActor func testMalformedIDDoesNotPreventOtherOwnedAlarmCancellation() async throws {
        try await withDefaults { defaults in
            let owned = UUID(); let alarms = RetiredAlarmsFixture(); alarms.active = [owned]
            defaults.set(["unreadable", owned.uuidString], forKey: NoorRetiredFridayCleanup.alarmIDsKey)
            let cleanup = NoorRetiredFridayCleanup(defaults: defaults, notifications: RetiredNotificationsFixture(), alarms: alarms)
            await cleanup.cleanup()
            XCTAssertEqual(alarms.cancellations, [owned])
            XCTAssertEqual(defaults.stringArray(forKey: NoorRetiredFridayCleanup.alarmIDsKey), ["unreadable"])
            XCTAssertNotNil(cleanup.message)
        }
    }

    @MainActor func testUnreadableAlarmStorageIsPreservedAndReported() async throws {
        try await withDefaults { defaults in
            let raw = Data("unreadable-alarm-identifiers".utf8)
            defaults.set(raw, forKey: NoorRetiredFridayCleanup.alarmIDsKey)
            let alarms = RetiredAlarmsFixture()
            let cleanup = NoorRetiredFridayCleanup(defaults: defaults, notifications: RetiredNotificationsFixture(), alarms: alarms)
            await cleanup.cleanup()
            XCTAssertEqual(defaults.data(forKey: NoorRetiredFridayCleanup.alarmIDsKey), raw)
            XCTAssertNotNil(cleanup.message)
            XCTAssertEqual(alarms.reads, 0)
        }
    }

    @MainActor func testConcurrentLaunchAndForegroundCleanupCoalesce() async throws {
        try await withDefaults { defaults in
            let notifications = RetiredNotificationsFixture(); notifications.suspend = true
            let cleanup = NoorRetiredFridayCleanup(defaults: defaults, notifications: notifications, alarms: RetiredAlarmsFixture())
            let started = XCTestExpectation(description: "Initial cleanup is suspended at system query")
            notifications.onSuspend = { started.fulfill() }
            let first = Task { await cleanup.cleanup() }
            await fulfillment(of: [started], timeout: 5)
            let blocked = try XCTUnwrap(notifications.continuation)
            let joined = XCTestExpectation(description: "Foreground cleanup joins the pending launch cleanup")
            let second = Task { joined.fulfill(); await cleanup.cleanup() }
            await fulfillment(of: [joined], timeout: 5)
            XCTAssertEqual(notifications.pendingReads, 1)
            notifications.suspend = false
            blocked.resume(); notifications.continuation = nil
            await first.value; await second.value
            XCTAssertEqual(notifications.removedPending, ["noor.friday.prayer.fajr"])
            XCTAssertFalse(cleanup.busy)
        }
    }

    @MainActor func testExplicitErasureKeepsUncancelledAlarmIDsAndUnrelatedData() async throws {
        try await withDefaults { defaults in
            let raw = [UUID().uuidString]
            defaults.set(raw, forKey: NoorRetiredFridayCleanup.alarmIDsKey)
            let cleanup = NoorRetiredFridayCleanup(defaults: defaults, notifications: RetiredNotificationsFixture(), alarms: RetiredAlarmsFixture())
            cleanup.eraseArchivedRecords()
            XCTAssertNil(defaults.data(forKey: "noor.friday.days"))
            XCTAssertNil(defaults.data(forKey: "noor.friday.preferences"))
            XCTAssertNotNil(defaults.data(forKey: "noor.memorization.archive"))
            XCTAssertEqual(defaults.stringArray(forKey: NoorRetiredFridayCleanup.alarmIDsKey), raw)
        }
    }

    @MainActor func testRetiredFridayLinksOpenSavedReaderWithoutTouchingSalawat() async throws {
        try await withDefaults { defaults in
            let router = NoorWidgetRouter(defaults: defaults)
            for host in ["friday", "friday-settings"] {
                XCTAssertTrue(router.open(try XCTUnwrap(URL(string: "nooralruh://\(host)"))))
                XCTAssertEqual(router.destination?.host, "reading")
                XCTAssertEqual(router.destination?.page, 603)
                XCTAssertTrue(router.openNotification(destination: host))
                XCTAssertEqual(router.destination?.page, 603)
            }
            XCTAssertEqual(defaults.integer(forKey: "noor.mushaf.lastPage"), 603)
            XCTAssertTrue(router.openNotification(destination: "dhikr"))
            XCTAssertEqual(router.destination?.host, "dhikr")
        }
    }
}
