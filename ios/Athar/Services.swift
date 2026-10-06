import Foundation
import Combine
import UserNotifications
import Adhan

extension PrayerCalculator {
    static func rows(data: DeviceData, date: Date = Date()) -> [PrayerRow] { rows(data: inputs(data), date: date) }
    static func next(data: DeviceData, now: Date) -> PrayerRow? { next(data: inputs(data), now: now) }
    static func time(_ date: Date, city: City) -> String { time(date, city: location(city)) }
    static func location(_ city: City) -> PrayerLocation {
        .init(name: city.name, latitude: city.latitude, longitude: city.longitude, timeZone: city.timeZone)
    }
    static func inputs(_ data: DeviceData) -> PrayerInputs { .init(city: location(data.city), method: data.method, hanafi: data.hanafi) }
}

private final class PrayerNotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        notification.request.content.sound == nil ? [.banner] : [.banner, .sound]
    }
}

@MainActor protocol PrayerNotificationClient {
    func requestAuthorization() async throws -> Bool
    func isAuthorized() async -> Bool
    func pendingIdentifiers() async -> [String]
    func deliveredIdentifiers() async -> [String]
    func add(_ request: UNNotificationRequest) async throws
    func removePending(_ identifiers: [String])
    func removeDelivered(_ identifiers: [String])
}
@MainActor final class SystemPrayerNotificationClient: PrayerNotificationClient {
    private let center = UNUserNotificationCenter.current()
    private let presenter = PrayerNotificationPresenter()
    init() { center.delegate = presenter }
    func requestAuthorization() async throws -> Bool { try await center.requestAuthorization(options: [.alert, .sound]) }
    func isAuthorized() async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }
    func pendingIdentifiers() async -> [String] { await center.pendingNotificationRequests().map(\.identifier) }
    func deliveredIdentifiers() async -> [String] { await center.deliveredNotifications().map { $0.request.identifier } }
    func add(_ request: UNNotificationRequest) async throws { try await center.add(request) }
    func removePending(_ ids: [String]) { center.removePendingNotificationRequests(withIdentifiers: ids) }
    func removeDelivered(_ ids: [String]) { center.removeDeliveredNotifications(withIdentifiers: ids) }
}

@MainActor
final class PrayerNotifications: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var scheduledCount = 0
    @Published private(set) var preferences = PrayerNotificationPreferences()
    @Published var message: String?
    private let client: any PrayerNotificationClient
    private let defaults: UserDefaults
    private let now: () -> Date
    @Published private(set) var requestingPermission = false
    private var authorizationRevision = 0
    private let enabledKey = "athar.prayerNotifications"
    private let preferencesKey = "noor.prayerPreferences.v1"
    private var revision = 0
    private var refreshing = false
    private var latestData: DeviceData?

    init(client: (any PrayerNotificationClient)? = nil, defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.client = client ?? SystemPrayerNotificationClient()
        self.defaults = defaults; self.now = now
        if let bytes = defaults.data(forKey: preferencesKey),
           let saved = try? JSONDecoder().decode(PrayerNotificationPreferences.self, from: bytes) {
            preferences = saved
        }
    }

    private var requested: Bool { defaults.bool(forKey: enabledKey) }
    private func isOwned(_ id: String) -> Bool {
        id.hasPrefix(PrayerNotificationPlan.prefix) || id.range(of: #"^athar\.[0-9]+\.(fajr|dhuhr|asr|maghrib|isha)$"#, options: .regularExpression) != nil
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: preferencesKey) }
    }

    func setPrayer(_ id: String, enabled value: Bool, store: AtharStore) async {
        guard preferences.prayers[id] != nil else { return }
        preferences.prayers[id] = value
        persist()
        await refresh(store: store)
    }
    func setAdvance(_ value: Int, store: AtharStore) async {
        guard [0, 5, 10, 15].contains(value) else { return }
        preferences.advanceMinutes = value
        persist()
        await refresh(store: store)
    }
    func setSound(_ value: Bool, store: AtharStore) async {
        preferences.soundEnabled = value
        persist()
        await refresh(store: store)
    }
    func enable(store: AtharStore) async {
        guard !requestingPermission else { return }
        requestingPermission = true
        let attempt = authorizationRevision
        defer { requestingPermission = false }
        do {
            let allowed = try await client.requestAuthorization()
            guard attempt == authorizationRevision else { return }
            guard allowed else {
                enabled = false
                message = "لم يُمنح إذن التنبيهات. يمكنك تغييره في إعدادات iPhone."
                return
            }
            defaults.set(true, forKey: enabledKey)
            await refresh(store: store)
        } catch {
            guard attempt == authorizationRevision else { return }
            message = "تعذر تفعيل التنبيهات. حاول مجددًا من الإعدادات."
        }
    }
    func disable() {
        authorizationRevision += 1
        defaults.set(false, forKey: enabledKey)
        revision += 1
        enabled = false
        scheduledCount = 0
        message = nil
        Task {
            let pending = await client.pendingIdentifiers()
            guard !requested else { return }
            client.removePending(pending.filter(isOwned))
            let delivered = await client.deliveredIdentifiers()
            guard !requested else { return }
            client.removeDelivered(delivered.filter(isOwned))
        }
    }

    func erasePreferences() {
        disable()
        preferences = PrayerNotificationPreferences()
        defaults.removeObject(forKey: preferencesKey)
        message = nil
    }

    // One reconciliation worker serializes updates; permission/preferences may change while center.add awaits.
    func refresh(store: AtharStore) async {
        latestData = store.data
        revision += 1
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        while let data = latestData {
            let generation = revision
            let allowed = await client.isAuthorized()
            guard generation == revision else { continue }
            enabled = requested && allowed
            let pending = await client.pendingIdentifiers()
            guard generation == revision else { continue }
            client.removePending(pending.filter(isOwned))
            scheduledCount = 0
            guard enabled else {
                message = requested && !allowed ? "تنبيهات النظام غير مفعلة. افتح إعدادات iPhone لتغيير الإذن." : nil
                return
            }
            let plan = PrayerNotificationPlan.make(data: data, preferences: preferences, now: now())
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: data.city.timeZone) ?? .current
            message = nil
            do {
                for event in plan {
                    guard generation == revision else { break }
                    let content = UNMutableNotificationContent()
                    content.title = "نور الروح · " + event.title
                    content.body = "\(event.cityName) · حسب إعدادات حساب المواقيت."
                    content.sound = event.soundEnabled ? .default : nil
                    var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: event.fireDate)
                    components.timeZone = calendar.timeZone
                    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                    try await client.add(UNNotificationRequest(identifier: event.id, content: content, trigger: trigger))
                    guard generation == revision else { break }
                    scheduledCount += 1
                }
                if generation == revision { return }
            } catch {
                if generation != revision { continue }
                client.removePending(plan.map(\.id))
                enabled = false
                scheduledCount = 0
                message = "تعذرت جدولة التنبيهات. أعد التفعيل للمحاولة مجددًا."
                return
            }
        }
    }
}
