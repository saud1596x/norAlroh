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
    func pendingRequests() async -> [UNNotificationRequest] { Array(pending.values) }
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
    @MainActor func testReminderRoutesOpenActualSectionsAndRejectUnknownPayload() {
        let router = NoorWidgetRouter()
        for kind in NoorReminderKind.allCases {
            XCTAssertTrue(router.openNotification(destination: kind.destination))
            XCTAssertEqual(router.destination?.host, kind.destination)
        }
        XCTAssertFalse(router.openNotification(destination: "personal-secret"))
    }
    @MainActor func testUnreadableLegacyArchiveRemainsExportableAndCustomEditorCannotOverwriteIt() async throws {
        let suite = "Noor.LegacyReminder." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
        let bytes = Data("damaged old preferences".utf8)
        defaults.set(bytes, forKey: "noor.personalReminders.v1")
        let client = PersonalNotificationClient()
        let service = PrayerNotifications(client: client, defaults: defaults)
        var old = NoorReminderPreference(kind: .dua); old.enabled = true
        await service.setReminder(.dua, preference: old, store: AtharStore(directory: folder))
        XCTAssertTrue(service.personalUnreadable)
        XCTAssertEqual(service.personalExport, bytes)
        XCTAssertEqual(defaults.data(forKey: "noor.personalReminders.v1"), bytes)
        XCTAssertFalse(service.policyRequested)
        XCTAssertTrue(client.pending.isEmpty)
    }
}
