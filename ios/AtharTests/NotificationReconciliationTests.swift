import XCTest
import UserNotifications
@testable import Athar

@MainActor private final class ContractNotifications: PrayerNotificationClient {
    var status: PrayerAuthorizationState = .authorized
    var permissionRequests = 0
    var additions: [String] = []
    var pending: [String: UNNotificationRequest] = [:]
    var delivered: [String] = []
    var failIDs: Set<String> = []
    var omitAcceptedID: String?
    var holdPermission = false
    var permissionStarted: (() -> Void)?
    var permission: CheckedContinuation<Bool, Never>?
    func authorizationStatus() async -> PrayerAuthorizationState { status }
    func requestAuthorization() async throws -> Bool {
        permissionRequests += 1
        if holdPermission {
            let allowed = await withCheckedContinuation { permission = $0; permissionStarted?() }
            status = allowed ? .authorized : .denied
            return allowed
        }
        status = .authorized; return true
    }
    func isAuthorized() async -> Bool { status == .authorized }
    func pendingIdentifiers() async -> [String] { Array(pending.keys) }
    func pendingRequests() async -> [UNNotificationRequest] { Array(pending.values) }
    func deliveredIdentifiers() async -> [String] { delivered }
    func add(_ request: UNNotificationRequest) async throws {
        additions.append(request.identifier)
        if failIDs.contains(request.identifier) { throw CocoaError(.fileWriteUnknown) }
        if request.identifier == omitAcceptedID { return }
        pending[request.identifier] = request
    }
    func removePending(_ ids: [String]) { for id in ids { pending.removeValue(forKey: id) } }
    func removeDelivered(_ ids: [String]) { delivered.removeAll { ids.contains($0) } }
}
@MainActor private final class ContractAlarms: PrayerAlarmClient {
    var available = true
    var status: PrayerAuthorizationState = .authorized
    var permissionRequests = 0
    var active: [UUID: ScheduledPrayerAlarm] = [:]
    var additions: [UUID] = []
    var failedEvent: String?
    var omitAcceptedEvent: String?
    var failCancellation = false
    var holdSchedule = false
    var scheduled: (() -> Void)?
    var cancelled: (() -> Void)?
    var scheduleBarrier: CheckedContinuation<Void, Never>?
    func authorizationStatus() -> PrayerAuthorizationState { status }
    func requestAuthorization() async throws -> PrayerAuthorizationState {
        permissionRequests += 1; status = .authorized; return status
    }
    func currentAlarms() throws -> [ScheduledPrayerAlarm] { Array(active.values) }
    func schedule(id: UUID, event: FixedPrayerEvent) async throws {
        additions.append(id)
        if event.id == failedEvent { throw CocoaError(.fileWriteUnknown) }
        if event.id == omitAcceptedEvent { return }
        if holdSchedule {
            holdSchedule = false
            await withCheckedContinuation { scheduleBarrier = $0; scheduled?() }
        }
        active[id] = .init(id: id, fireDate: event.fireDate)
    }
    func cancel(id: UUID) throws {
        if failCancellation { throw CocoaError(.fileWriteUnknown) }
        active.removeValue(forKey: id); cancelled?()
    }
}
@MainActor private final class NotificationContractFixture {
    let suite: String
    let folder: URL
    let defaults: UserDefaults
    let store: AtharStore
    let notifications = ContractNotifications()
    let alarms = ContractAlarms()
    var now = ISO8601DateFormatter().date(from: "2026-10-30T21:00:00Z")!
    init(trusted: Bool = true) throws {
        let suiteName = "Noor.FixedPolicy." + UUID().uuidString
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        suite = suiteName; folder = directory
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        store = AtharStore(directory: directory)
        if trusted { defaults.set(store.data.city.id, forKey: "noor.fixedPrayer.locationConfirmedCity.v2") }
    }
    func service() -> PrayerNotifications {
        PrayerNotifications(client: notifications, alarms: alarms, defaults: defaults, now: { self.now })
    }
    func cleanup() { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
}

/// Injected system clients verify policy/reconciliation contracts. These tests
/// do not demonstrate OS prompt rendering, sound, lock-screen or alarm delivery.
final class NotificationReconciliationTests: XCTestCase {
    @MainActor func testFirstUseReadsStateWithoutPromptingOrAdoptingUndisclosedPolicy() async throws {
        let f = try NotificationContractFixture(); defer { f.cleanup() }
        f.notifications.status = .notDetermined; f.alarms.status = .notDetermined
        let service = f.service()
        for _ in 0..<10 { await service.configureFirstUse(store: f.store) }
        XCTAssertEqual(f.notifications.permissionRequests, 0); XCTAssertEqual(f.alarms.permissionRequests, 0)
        XCTAssertFalse(service.policyRequested); XCTAssertTrue(f.notifications.pending.isEmpty); XCTAssertTrue(f.alarms.active.isEmpty)
    }
    @MainActor func testExplicitEnableRequestsEachUndeterminedPermissionOnlyOnce() async throws {
        let f = try NotificationContractFixture(); defer { f.cleanup() }
        f.notifications.status = .notDetermined; f.alarms.status = .notDetermined
        let service = f.service()
        await service.enable(store: f.store); await service.enable(store: f.store)
        XCTAssertEqual(f.notifications.permissionRequests, 1); XCTAssertEqual(f.alarms.permissionRequests, 1)
        XCTAssertEqual(service.prayerAuthorization, .authorized); XCTAssertEqual(service.notificationAuthorization, .authorized)
        XCTAssertEqual(service.scheduledCount, 15); XCTAssertEqual(service.salawatCount, 1)
    }
    @MainActor func testFourPermissionCombinationsNeverDisableTheOtherAuthorizedChannel() async throws {
        for alarmAllowed in [false, true] {
            for notificationAllowed in [false, true] {
                let f = try NotificationContractFixture(); defer { f.cleanup() }
                f.alarms.status = alarmAllowed ? .authorized : .denied
                f.notifications.status = notificationAllowed ? .authorized : .denied
                let service = f.service(); await service.enable(store: f.store)
                XCTAssertEqual(f.alarms.active.count, alarmAllowed ? 15 : 0)
                XCTAssertEqual(service.salawatCount, notificationAllowed ? 1 : 0)
                XCTAssertEqual(f.alarms.permissionRequests, 0); XCTAssertEqual(f.notifications.permissionRequests, 0)
                XCTAssertFalse(f.notifications.pending.keys.contains { $0.hasSuffix(".fajr") }, "iOS26 must not silently substitute UN for denied AlarmKit")
            }
        }
    }
    @MainActor func testDeniedPermissionsAreNotPromptedOnRepeatedEnableOrForegroundRefresh() async throws {
        let f = try NotificationContractFixture(); defer { f.cleanup() }
        f.alarms.status = .denied; f.notifications.status = .denied
        let service = f.service()
        for _ in 0..<10 { await service.enable(store: f.store); await service.refresh(store: f.store) }
        XCTAssertEqual(f.alarms.permissionRequests, 0); XCTAssertEqual(f.notifications.permissionRequests, 0)
        XCTAssertTrue(f.alarms.active.isEmpty); XCTAssertTrue(f.notifications.pending.isEmpty)
    }
    @MainActor func testLegacyOSUsesOrdinaryDatedPrayerNotificationsAndSilentQuietReminders() async throws {
        let f = try NotificationContractFixture(); defer { f.cleanup() }
        f.alarms.available = false
        let service = f.service(); await service.enable(store: f.store)
        XCTAssertFalse(service.usesAlarmKit); XCTAssertTrue(f.alarms.active.isEmpty)
        XCTAssertEqual(service.scheduledCount, 15)
        let prayers = f.notifications.pending.values.filter { $0.identifier.hasSuffix(".fajr") }
        XCTAssertEqual(prayers.count, 3)
        XCTAssertTrue(prayers.allSatisfy { ($0.trigger as? UNCalendarNotificationTrigger)?.repeats == false })
        let quiet = f.notifications.pending.values.filter { $0.identifier.hasSuffix(".duha") || $0.identifier.hasSuffix(".witr") }
        XCTAssertEqual(quiet.count, 6)
        XCTAssertTrue(quiet.allSatisfy { $0.content.sound == nil && $0.content.badge == nil })
    }
    @MainActor func testTenRefreshesAndRestartPreserveTheOriginalCorrectSalawatRequest() async throws {
        let f = try NotificationContractFixture(); defer { f.cleanup() }
        let service = f.service(); await service.enable(store: f.store)
        let original = try XCTUnwrap(f.notifications.pending[FixedPrayerPolicy.salawatID])
        let addCount = f.notifications.additions.count, alarmCount = f.alarms.additions.count
        for _ in 0..<10 { await service.refresh(store: f.store) }
        await f.service().refresh(store: f.store)
        XCTAssertTrue(f.notifications.pending[FixedPrayerPolicy.salawatID] === original)
        XCTAssertEqual(f.notifications.additions.count, addCount); XCTAssertEqual(f.alarms.additions.count, alarmCount)
        XCTAssertNotNil(service.prayerCoverageThrough); XCTAssertNotNil(service.reminderCoverageThrough)
    }
    @MainActor func testObservedRemovedAlarmIsNotRecreatedAfterRefreshOrProcessRestart() async throws {
        let f = try NotificationContractFixture(); defer { f.cleanup() }
        let service = f.service(); await service.enable(store: f.store)
        let removed = try XCTUnwrap(f.alarms.active.keys.first)
        f.alarms.active.removeValue(forKey: removed)
        let count = f.alarms.additions.count
        await service.refresh(store: f.store); await f.service().refresh(store: f.store)
        XCTAssertEqual(f.alarms.additions.count, count); XCTAssertNil(f.alarms.active[removed])
        let bytes = try XCTUnwrap(f.defaults.data(forKey: "noor.fixedPrayer.alarmRecords.v2"))
        let records = try JSONDecoder().decode([String: PrayerAlarmRecord].self, from: bytes)
        XCTAssertEqual(records.values.first { $0.id == removed }?.state, .observedRemoved)
    }
    @MainActor func testPartialAlarmFailureRetainsHealthyRequestsAndRetriesOnlyMissingEvent() async throws {
        let f = try NotificationContractFixture(); defer { f.cleanup() }
        let first = try XCTUnwrap(FixedPrayerPolicy.make(data: f.store.data, now: f.now).first { $0.kind == .prayer })
        f.alarms.failedEvent = first.id
        let service = f.service(); await service.enable(store: f.store)
        XCTAssertEqual(service.scheduledCount, 14); XCTAssertNil(service.prayerCoverageThrough)
        let originalSalawat = try XCTUnwrap(f.notifications.pending[FixedPrayerPolicy.salawatID])
        let prior = f.alarms.additions.count
        f.alarms.failedEvent = nil; await service.refresh(store: f.store)
        XCTAssertEqual(service.scheduledCount, 15); XCTAssertEqual(f.alarms.additions.count, prior + 1)
        XCTAssertTrue(f.notifications.pending[FixedPrayerPolicy.salawatID] === originalSalawat)
    }
    @MainActor func testFailedQuietAdditionDoesNotResetSalawatOrRemoveForeignRequests() async throws {
        let f = try NotificationContractFixture(); defer { f.cleanup() }
        let foreign = UNNotificationRequest(identifier: "foreign.keep", content: UNMutableNotificationContent(), trigger: nil)
        f.notifications.pending[foreign.identifier] = foreign
        let service = f.service(); await service.enable(store: f.store)
        let salawat = try XCTUnwrap(f.notifications.pending[FixedPrayerPolicy.salawatID])
        let quiet = try XCTUnwrap(f.notifications.pending.keys.first { $0.hasSuffix(".duha") })
        f.notifications.pending.removeValue(forKey: quiet); f.notifications.failIDs = [quiet]
        await service.refresh(store: f.store)
        XCTAssertTrue(f.notifications.pending[FixedPrayerPolicy.salawatID] === salawat)
        XCTAssertTrue(f.notifications.pending[foreign.identifier] === foreign); XCTAssertNotNil(service.message)
        XCTAssertEqual(service.scheduledCount, 15)
    }
    @MainActor func testAcceptedCallsWithoutActualRegistrationCannotClaimCompleteCoverage() async throws {
        let f = try NotificationContractFixture(); defer { f.cleanup() }
        let events = FixedPrayerPolicy.make(data: f.store.data, now: f.now)
        f.alarms.omitAcceptedEvent = try XCTUnwrap(events.first { $0.kind == .prayer }).id
        f.notifications.omitAcceptedID = try XCTUnwrap(events.first { $0.kind != .prayer }).id
        let service = f.service(); await service.enable(store: f.store)
        XCTAssertEqual(service.scheduledCount, 14); XCTAssertNil(service.prayerCoverageThrough)
        XCTAssertNil(service.reminderCoverageThrough); XCTAssertNotNil(service.message)
        XCTAssertEqual(service.salawatCount, 1)
    }
    @MainActor func testFailedCancellationCannotCreateADuplicateAndLaterRepairUsesTheSameUUID() async throws {
        let f = try NotificationContractFixture(); defer { f.cleanup() }
        let service = f.service(); await service.enable(store: f.store)
        let id = try XCTUnwrap(f.alarms.active.keys.first)
        let expected = try XCTUnwrap(f.alarms.active[id]?.fireDate)
        f.alarms.active[id] = .init(id: id, fireDate: expected.addingTimeInterval(120))
        f.alarms.failCancellation = true
        let adds = f.alarms.additions.count
        await service.refresh(store: f.store)
        XCTAssertEqual(f.alarms.additions.count, adds); XCTAssertEqual(f.alarms.active.count, 15)
        XCTAssertEqual(service.scheduledCount, 14); XCTAssertNotNil(service.message)
        f.alarms.failCancellation = false; await service.refresh(store: f.store)
        XCTAssertEqual(f.alarms.active[id]?.fireDate, expected)
        XCTAssertEqual(f.alarms.additions.count, adds + 1); XCTAssertEqual(f.alarms.active.count, 15)
    }
    @MainActor func testSettledPruningAndClockRollbackCannotResurrectRemovedAlarmAndForwardTimeRecovers() async throws {
        let f = try NotificationContractFixture(); defer { f.cleanup() }
        let service = f.service(); await service.enable(store: f.store)
        let originalTime = f.now
        let removed = try XCTUnwrap(f.alarms.active.keys.first)
        f.alarms.active.removeValue(forKey: removed); await service.refresh(store: f.store)
        let salawat = try XCTUnwrap(f.notifications.pending[FixedPrayerPolicy.salawatID])
        // All remaining old one-shot events have now left the daemon too.
        f.alarms.active.removeAll(); f.now = originalTime.addingTimeInterval(70 * 24 * 60 * 60)
        await service.refresh(store: f.store)
        let data = try XCTUnwrap(f.defaults.data(forKey: "noor.fixedPrayer.alarmRecords.v2"))
        let records = try JSONDecoder().decode([String: PrayerAlarmRecord].self, from: data)
        XCTAssertFalse(records.values.contains { $0.id == removed })
        let forwardTime = f.now, adds = f.alarms.additions.count
        f.now = originalTime.addingTimeInterval(60 * 60); await service.refresh(store: f.store)
        XCTAssertEqual(f.alarms.additions.count, adds); XCTAssertEqual(service.scheduledCount, 0)
        XCTAssertNil(service.prayerCoverageThrough); XCTAssertNotNil(service.message)
        XCTAssertTrue(f.notifications.pending[FixedPrayerPolicy.salawatID] === salawat)
        XCTAssertEqual(service.salawatCount, 1)
        // Returning to a credible forward date resumes the dated policy.
        f.now = forwardTime.addingTimeInterval(60 * 60); await service.refresh(store: f.store)
        XCTAssertEqual(service.scheduledCount, 15); XCTAssertNotNil(service.prayerCoverageThrough)
        XCTAssertNil(f.alarms.active[removed])
    }
    @MainActor func testHistoryPruningPreservesActiveFailedCancellationIdentityEvenAfterSixtyFourDays() async throws {
        let f = try NotificationContractFixture(); defer { f.cleanup() }
        let service = f.service(); await service.enable(store: f.store)
        let id = try XCTUnwrap(f.alarms.active.keys.first)
        f.alarms.failCancellation = true
        f.now = f.now.addingTimeInterval(70 * 24 * 60 * 60)
        service.disable(); await service.refresh(store: f.store)
        let data = try XCTUnwrap(f.defaults.data(forKey: "noor.fixedPrayer.alarmRecords.v2"))
        let records = try JSONDecoder().decode([String: PrayerAlarmRecord].self, from: data)
        XCTAssertTrue(records.values.contains { $0.id == id }); XCTAssertNotNil(f.alarms.active[id])
        XCTAssertNotNil(service.message)
    }
    @MainActor func testTokyoRemovedFajrCannotResurrectInHawaiiAfterRollbackJustAboveHistoryFloor() async throws {
        let f = try NotificationContractFixture(); defer { f.cleanup() }
        func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
        f.now = date("2026-08-27T12:00:00Z")
        XCTAssertTrue(f.store.update {
            $0.city = City(id: "location.current", name: "طوكيو", latitude: 35.68, longitude: 139.76,
                timeZone: "Asia/Tokyo", region: nil, countryCode: "JP", sourceID: nil)
            $0.locationUpdatedAt = f.now
        })
        let eventID = "noor.fixedPrayer.v2.c1.2026-8-28.fajr"
        let floor = date("2026-08-28T00:00:00Z")
        let tokyoEvent = try XCTUnwrap(FixedPrayerPolicy.make(data: f.store.data, now: f.now).first { $0.id == eventID })
        XCTAssertLessThan(tokyoEvent.fireDate, floor)
        let service = f.service(); await service.enable(store: f.store)
        func records() throws -> [String: PrayerAlarmRecord] {
            try JSONDecoder().decode([String: PrayerAlarmRecord].self,
                from: XCTUnwrap(f.defaults.data(forKey: "noor.fixedPrayer.alarmRecords.v2")))
        }
        let original = try XCTUnwrap(records()[eventID])
        f.alarms.active.removeValue(forKey: original.id); await service.refresh(store: f.store)
        // Advance far enough to move the monotonic floor to August28.
        f.now = date("2026-10-31T00:00:00Z"); f.alarms.active.removeAll()
        await service.refresh(store: f.store)
        XCTAssertEqual(try records()[eventID]?.state, .observedRemoved)
        // This rollback is above the floor, so the ordinary clock guard does
        // not block scheduling. The same local-day Fajr is future in Hawaii.
        f.now = date("2026-08-28T00:01:00Z")
        XCTAssertTrue(f.store.update {
            $0.city = City(id: "location.current", name: "هونولولو", latitude: 21.31, longitude: -157.86,
                timeZone: "Pacific/Honolulu", region: nil, countryCode: "US", sourceID: nil)
            $0.locationUpdatedAt = f.now
        })
        let hawaiiEvent = try XCTUnwrap(FixedPrayerPolicy.make(data: f.store.data, now: f.now).first { $0.id == eventID })
        XCTAssertGreaterThan(hawaiiEvent.fireDate, f.now)
        await service.refresh(store: f.store)
        XCTAssertEqual(try records()[eventID]?.id, original.id)
        XCTAssertEqual(try records()[eventID]?.state, .observedRemoved)
        XCTAssertNil(f.alarms.active[original.id])
    }
    @MainActor func testMigrationRetiresOnlyKnownRoutesAndPreservesReadingAndLegacyArchiveBytes() async throws {
        let f = try NotificationContractFixture(); defer { f.cleanup() }
        let archive = Data("retained unreadable old preferences".utf8)
        f.defaults.set(archive, forKey: "noor.personalReminders.v1")
        for id in ["noor.friday.old", "noor.salawat.9", "noor.prayer.2026-10-31.fajr", "noor.personal.witr.old", "athar.123.fajr", "noor.khatmah.keep", "noor.personal.unknown.keep", "foreign.keep"] {
            f.notifications.pending[id] = .init(identifier: id, content: UNMutableNotificationContent(), trigger: nil)
        }
        let before = f.store.data
        let service = f.service(); await service.configureFirstUse(store: f.store)
        XCTAssertEqual(Set(f.notifications.pending.keys), ["noor.personal.unknown.keep", "foreign.keep"])
        XCTAssertEqual(f.defaults.data(forKey: "noor.personalReminders.v1"), archive)
        XCTAssertEqual(f.store.data.bookmarks, before.bookmarks); XCTAssertEqual(f.store.data.city, before.city)
        XCTAssertTrue(service.personalUnreadable)
    }
    @MainActor func testV2RetiresLegacyWardRequestsWithoutChangingUnrelatedRequestsOrPrompting() async throws {
        let f = try NotificationContractFixture(); defer { f.cleanup() }
        f.notifications.status = .notDetermined; f.alarms.status = .notDetermined
        let wardID = "noor.khatmah.00000000-0000-0000-0000-000000000001.1"
        let unrelatedID = "noor.khatmahElse.keep"
        let unrelated = UNNotificationRequest(identifier: unrelatedID, content: UNMutableNotificationContent(), trigger: nil)
        f.notifications.pending[wardID] = .init(identifier: wardID, content: UNMutableNotificationContent(), trigger: nil)
        f.notifications.pending[unrelatedID] = unrelated
        f.notifications.delivered = [wardID, "foreign.delivered"]
        let service = f.service(); await service.configureFirstUse(store: f.store)
        XCTAssertNil(f.notifications.pending[wardID])
        XCTAssertTrue(f.notifications.pending[unrelatedID] === unrelated)
        XCTAssertEqual(f.notifications.delivered, ["foreign.delivered"])
        XCTAssertEqual(f.notifications.permissionRequests, 0); XCTAssertEqual(f.alarms.permissionRequests, 0)
    }
    @MainActor func testLegacySoundFrequencyAdvanceAndPrayerSwitchesCannotAffectV2Policy() async throws {
        let f = try NotificationContractFixture(); defer { f.cleanup() }
        var preferences = PrayerNotificationPreferences(); preferences.prayers = [:]
        preferences.advanceMinutes = 15; preferences.soundEnabled = false; preferences.soundStyle = "silent"
        let bytes = try JSONEncoder().encode(preferences); f.defaults.set(bytes, forKey: "noor.prayerPreferences.v1")
        let service = f.service(); await service.enable(store: f.store)
        await service.setAdvance(10, store: f.store); await service.setPrayer("fajr", enabled: false, store: f.store)
        await service.setSalawatInterval(12, store: f.store)
        XCTAssertEqual(service.scheduledCount, 15); XCTAssertEqual(service.salawatCount, 1)
        XCTAssertEqual(f.defaults.data(forKey: "noor.prayerPreferences.v1"), bytes)
    }
    @MainActor func testUntrustedDefaultCitySchedulesOnlyIndependentSalawatUntilExplicitConfirmation() async throws {
        let f = try NotificationContractFixture(trusted: false); defer { f.cleanup() }
        let service = f.service(); await service.enable(store: f.store)
        XCTAssertFalse(service.locationIsTrusted); XCTAssertEqual(service.scheduledCount, 0)
        XCTAssertEqual(Set(f.notifications.pending.keys), [FixedPrayerPolicy.salawatID])
        await service.confirmLocation(store: f.store)
        XCTAssertTrue(service.locationIsTrusted); XCTAssertEqual(service.scheduledCount, 15)
    }
    @MainActor func testCorruptAlarmIdentityArchiveCannotCreateReplacementUUIDs() async throws {
        let f = try NotificationContractFixture(); defer { f.cleanup() }
        let bytes = Data("damaged identity map".utf8)
        f.defaults.set(bytes, forKey: "noor.fixedPrayer.alarmRecords.v2")
        let service = f.service(); await service.enable(store: f.store)
        XCTAssertTrue(f.alarms.active.isEmpty); XCTAssertNotNil(service.message)
        XCTAssertEqual(f.defaults.data(forKey: "noor.fixedPrayer.alarmRecords.v2"), bytes)
        XCTAssertEqual(service.salawatCount, 1)
    }
    @MainActor func testDisablingDuringInFlightAlarmScheduleEventuallyCancelsTheLateOwnedAlarm() async throws {
        let f = try NotificationContractFixture(); defer { f.cleanup() }
        f.alarms.holdSchedule = true
        let started = expectation(description: "Owned schedule reached system boundary")
        let cancelled = expectation(description: "Late owned alarm cancelled after disable")
        f.alarms.scheduled = { started.fulfill() }; f.alarms.cancelled = { cancelled.fulfill() }
        let service = f.service()
        let task = Task { await service.enable(store: f.store) }
        await fulfillment(of: [started], timeout: 2)
        service.disable(); task.cancel(); f.alarms.scheduleBarrier?.resume(); await task.value
        await fulfillment(of: [cancelled], timeout: 2)
        XCTAssertFalse(service.policyRequested); XCTAssertTrue(f.alarms.active.isEmpty)
        XCTAssertTrue(f.notifications.pending.isEmpty)
    }
    @MainActor func testDisablingWhilePermissionAwaitsCannotRequestTheSecondPermissionOrReactivate() async throws {
        let f = try NotificationContractFixture(); defer { f.cleanup() }
        f.alarms.status = .denied; f.notifications.status = .notDetermined; f.notifications.holdPermission = true
        let started = expectation(description: "Notification permission awaited")
        f.notifications.permissionStarted = { started.fulfill() }
        let service = f.service(); let task = Task { await service.enable(store: f.store) }
        await fulfillment(of: [started], timeout: 2)
        service.disable(); f.notifications.permission?.resume(returning: true); await task.value
        XCTAssertFalse(service.policyRequested); XCTAssertTrue(f.alarms.active.isEmpty)
        XCTAssertTrue(f.notifications.pending.isEmpty)
    }
    @MainActor func testDeliveredFallbackEventIsNotRecreatedWhenSystemDeliveredListIsCleared() async throws {
        let f = try NotificationContractFixture(); defer { f.cleanup() }
        f.alarms.available = false
        let service = f.service(); await service.enable(store: f.store)
        let delivered = try XCTUnwrap(f.notifications.pending.keys.first { $0.hasSuffix(".fajr") })
        f.notifications.delivered = [delivered]; await service.refresh(store: f.store)
        f.notifications.delivered = []; await f.service().refresh(store: f.store)
        XCTAssertNil(f.notifications.pending[delivered])
        XCTAssertEqual(service.salawatCount, 1)
    }
}
