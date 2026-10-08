import Foundation
import Combine
import UserNotifications
import AlarmKit

@MainActor protocol NoorRetiredNotificationClient {
    func pendingIDs() async -> [String]
    func deliveredIDs() async -> [String]
    func removePending(_ ids: [String])
    func removeDelivered(_ ids: [String])
}

@MainActor protocol NoorRetiredAlarmClient {
    var available: Bool { get }
    func currentIDs() throws -> Set<UUID>
    func cancel(_ id: UUID) throws
}

@MainActor private final class NoorSystemRetiredNotifications: NoorRetiredNotificationClient {
    private let center = UNUserNotificationCenter.current()
    func pendingIDs() async -> [String] { await center.pendingNotificationRequests().map(\.identifier) }
    func deliveredIDs() async -> [String] { await center.deliveredNotifications().map { $0.request.identifier } }
    func removePending(_ ids: [String]) { center.removePendingNotificationRequests(withIdentifiers: ids) }
    func removeDelivered(_ ids: [String]) { center.removeDeliveredNotifications(withIdentifiers: ids) }
}

@MainActor private final class NoorSystemRetiredAlarms: NoorRetiredAlarmClient {
    var available: Bool { if #available(iOS 26.0, *) { return true }; return false }
    func currentIDs() throws -> Set<UUID> {
        if #available(iOS 26.0, *) { return Set(try AlarmManager.shared.alarms.map(\.id)) }
        return []
    }
    func cancel(_ id: UUID) throws {
        if #available(iOS 26.0, *) { try AlarmManager.shared.cancel(id: id) }
    }
}

/// Upgrade cleanup only: never schedules a reminder or asks for permission.
/// Keep old user records, and retain failed alarm IDs for the next retry.
@MainActor final class NoorRetiredFridayCleanup: ObservableObject {
    static let alarmIDsKey = "noor.friday.alarmIDs"
    private static let prefix = "noor.friday."
    @Published private(set) var message: String?
    @Published private(set) var busy = false
    private let defaults: UserDefaults
    private let notifications: NoorRetiredNotificationClient
    private let alarms: NoorRetiredAlarmClient
    private var inFlight: Task<Void, Never>?

    init(defaults: UserDefaults = .standard,
         notifications: NoorRetiredNotificationClient? = nil,
         alarms: NoorRetiredAlarmClient? = nil) {
        self.defaults = defaults
        self.notifications = notifications ?? NoorSystemRetiredNotifications()
        self.alarms = alarms ?? NoorSystemRetiredAlarms()
        disableOldFlags()
    }

    func cleanup() async {
        if let existing = inFlight { await existing.value; return }
        let task = Task { @MainActor in await self.performCleanup() }
        inFlight = task
        await task.value
        inFlight = nil
    }

    private func disableOldFlags() {
        defaults.set(false, forKey: "noor.friday.notifications")
        defaults.set(false, forKey: "noor.friday.alarms")
    }

    private func performCleanup() async {
        busy = true
        defer { busy = false }
        disableOldFlags()
        message = nil
        let pending = await notifications.pendingIDs().filter { $0.hasPrefix(Self.prefix) }
        let delivered = await notifications.deliveredIDs().filter { $0.hasPrefix(Self.prefix) }
        if !pending.isEmpty { notifications.removePending(pending) }
        if !delivered.isEmpty { notifications.removeDelivered(delivered) }

        guard let saved = defaults.stringArray(forKey: Self.alarmIDsKey) else {
            if defaults.object(forKey: Self.alarmIDsKey) != nil {
                message = "تعذّر قراءة معلومات التنبيهات القديمة. احتفظنا بها ولم نغيّر تنبيهاتك الأخرى."
            }
            return
        }
        guard !saved.isEmpty else { return }
        // Do not forget an owned alarm on an OS that cannot inspect AlarmKit.
        guard alarms.available else { return }
        do {
            let active = try alarms.currentIDs()
            var failed: Set<UUID> = []
            var processed: Set<UUID> = []
            for raw in saved {
                guard let id = UUID(uuidString: raw), processed.insert(id).inserted,
                      active.contains(id) else { continue }
                do { try alarms.cancel(id) }
                catch { failed.insert(id) }
            }
            let remaining = saved.filter { raw in
                guard let id = UUID(uuidString: raw) else { return true }
                return failed.contains(id)
            }
            if remaining.isEmpty { defaults.removeObject(forKey: Self.alarmIDsKey) }
            else {
                defaults.set(remaining, forKey: Self.alarmIDsKey)
                message = "تعذّر إلغاء بعض التنبيهات القديمة. أعد المحاولة؛ احتفظنا بمعلوماتها حتى تُلغى."
            }
        } catch {
            // Listing failure preserves every ID, including partial/corrupt records.
            message = "تعذّر التحقق من التنبيهات القديمة وإلغاؤها. أعد المحاولة."
        }
    }

    /// Used only by the user's existing explicit erase-data action.
    func eraseArchivedRecords() {
        defaults.removeObject(forKey: "noor.friday.preferences")
        defaults.removeObject(forKey: "noor.friday.days")
        disableOldFlags()
        // Failed cancellation identifiers must remain recoverable.
    }
}
