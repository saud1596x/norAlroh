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
    static func inputs(_ data: DeviceData) -> PrayerInputs {
        let profile = AutomaticPrayerProfile.resolve(countryCode: data.city.countryCode)
        return .init(city: location(data.city), method: profile.method, hanafi: profile.lateAsr)
    }
}

private final class PrayerNotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        notification.request.content.sound == nil ? [.banner] : [.banner, .sound]
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        let info = response.notification.request.content.userInfo
        if response.notification.request.identifier.hasPrefix("noor.khatmah."),
           let raw = info["url"] as? String, let url = URL(string: raw), url.scheme == "nooralruh", url.host == "reading" {
            await MainActor.run { _ = NoorWidgetRouter.shared.open(url) }
        } else if let destination = info["destination"] as? String {
            await MainActor.run { _ = NoorWidgetRouter.shared.openNotification(destination: destination) }
        }
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
    @Published private(set) var salawat = SalawatPreferences()
    @Published private(set) var salawatCount = 0
    @Published private(set) var personal = NoorReminderArchive()
    @Published private(set) var personalCounts: [String: Int] = [:]
    @Published private(set) var personalUnreadable = false
    private let personalKey = "noor.personalReminders.v1"
    var personalExport: Data? { defaults.data(forKey: personalKey) }
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
        if let bytes = defaults.data(forKey: personalKey) {
            if let saved = try? JSONDecoder().decode(NoorReminderArchive.self, from: bytes), saved.valid { personal = saved }
            else { personalUnreadable = true }
        }
        if let bytes = defaults.data(forKey: "noor.salawat.preferences.v1"),
           let saved = try? JSONDecoder().decode(SalawatPreferences.self, from: bytes), saved.valid { salawat = saved }
    }

    private var requested: Bool { defaults.bool(forKey: enabledKey) }
    private func isOwned(_ id: String) -> Bool {
        id.hasPrefix(PrayerNotificationPlan.prefix) || id.range(of: #"^athar\.[0-9]+\.(fajr|dhuhr|asr|maghrib|isha)$"#, options: .regularExpression) != nil
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: preferencesKey) }
    }

    func reminder(_ kind: NoorReminderKind) -> NoorReminderPreference {
        if let value = personal.values[kind.rawValue] { return value }
        var value = NoorReminderPreference(kind: kind)
        if kind == .salawat {
            value.enabled = salawat.enabled; value.startMinute = 540; value.endMinute = 1260
            value.intervalMinutes = salawat.intervalHours * 60
        }
        return value
    }
    func setReminder(_ kind: NoorReminderKind, preference: NoorReminderPreference, store: AtharStore) async {
        guard preference.valid, !personalUnreadable else {
            message = "تعذر حفظ التذكير. صدّر الإعدادات المحفوظة قبل إصلاحها."; return
        }
        // Every edit invalidates an in-flight permission request, including disabling.
        authorizationRevision += 1
        let attempt = authorizationRevision
        if preference.enabled && !reminder(kind).enabled {
            guard !requestingPermission else { return }
            requestingPermission = true
            defer { requestingPermission = false }
            do {
                let allowed = try await client.requestAuthorization()
                guard attempt == authorizationRevision else { return }
                guard allowed else { message = "إذن الإشعارات غير متاح. افتح إعدادات iPhone."; return }
            } catch { message = "تعذر طلب إذن الإشعارات."; return }
        }
        guard attempt == authorizationRevision else { return }
        var next = personal; next.values[kind.rawValue] = preference
        guard let bytes = try? JSONEncoder().encode(next) else { return }
        defaults.set(bytes, forKey: personalKey)
        guard defaults.data(forKey: personalKey) == bytes else { message = "تعذر حفظ إعدادات التذكير."; return }
        personal = next
        // Explicitly editing salawat adopts the new independent schedule, preserving
        // untouched legacy preferences until that action. Never schedule both.
        if kind == .salawat { salawat.enabled = false; persistSalawat() }
        await refresh(store: store)
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
    func setSoundStyle(_ value: String, store: AtharStore) async {
        guard ["adhan", "system", "silent"].contains(value) else { return }
        preferences.soundStyle = value; preferences.soundEnabled = value != "silent"
        persist(); await refresh(store: store)
    }
    private func persistSalawat() {
        if let bytes = try? JSONEncoder().encode(salawat) { defaults.set(bytes, forKey: "noor.salawat.preferences.v1") }
    }
    func setSalawatInterval(_ hours: Int, store: AtharStore) async {
        guard [2, 4, 6, 12].contains(hours) else { return }
        salawat.intervalHours = hours; persistSalawat(); await refresh(store: store)
    }
    func setSalawatEnabled(_ value: Bool, store: AtharStore) async {
        if !value {
            authorizationRevision += 1; salawat.enabled = false; persistSalawat()
            await refresh(store: store); return
        }
        guard !requestingPermission else { return }
        requestingPermission = true; let attempt = authorizationRevision
        defer { requestingPermission = false }
        do {
            guard try await client.requestAuthorization(), attempt == authorizationRevision else {
                message = "إذن الإشعارات غير متاح. يمكنك تفعيله من إعدادات iPhone."; return
            }
            salawat.enabled = true; persistSalawat(); await refresh(store: store)
        } catch { message = "تعذر طلب إذن الإشعارات. حاول مجددًا." }
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
        salawat = SalawatPreferences(); defaults.removeObject(forKey: "noor.salawat.preferences.v1")
        personal = .init(); personalUnreadable = false; personalCounts = [:]
        defaults.removeObject(forKey: personalKey)
        revision += 1
        Task {
            let ids = await client.pendingIdentifiers()
            guard !salawat.enabled && !personal.values.values.contains(where: { $0.enabled }) else { return }
            client.removePending(ids.filter { $0.hasPrefix(SalawatNotificationPlan.prefix) || $0.hasPrefix(NoorPersonalReminderPlan.prefix) })
            let delivered = await client.deliveredIdentifiers()
            guard !salawat.enabled && !personal.values.values.contains(where: { $0.enabled }) else { return }
            client.removeDelivered(delivered.filter { $0.hasPrefix(SalawatNotificationPlan.prefix) || $0.hasPrefix(NoorPersonalReminderPlan.prefix) })
        }
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
            let delivered = Set(await client.deliveredIdentifiers())
            guard generation == revision else { continue }
            guard !Task.isCancelled else { return }
            let owns: (String) -> Bool = { self.isOwned($0) || $0.hasPrefix(SalawatNotificationPlan.prefix) || $0.hasPrefix(NoorPersonalReminderPlan.prefix) }
            client.removePending(pending.filter(owns))
            let personalEnabled = personal.values.values.contains { $0.enabled }
            let retiredDelivered = delivered.filter { id in
                if id.hasPrefix(SalawatNotificationPlan.prefix) {
                    return !salawat.enabled || personal.values[NoorReminderKind.salawat.rawValue] != nil
                }
                guard id.hasPrefix(NoorPersonalReminderPlan.prefix) else { return false }
                return !NoorReminderKind.allCases.contains { kind in
                    id.hasPrefix(NoorPersonalReminderPlan.prefix + kind.rawValue + ".") && personal.values[kind.rawValue]?.enabled == true
                }
            }
            client.removeDelivered(Array(retiredDelivered))
            scheduledCount = 0; salawatCount = 0; personalCounts = [:]
            guard allowed && (requested || salawat.enabled || personalEnabled) else {
                message = (requested || salawat.enabled || personalEnabled) && !allowed ? "تنبيهات النظام غير مفعلة. افتح إعدادات iPhone لتغيير الإذن." : nil
                return
            }
            let slots = personal.values[NoorReminderKind.salawat.rawValue] == nil ? SalawatNotificationPlan.slots(salawat) : []
            let personalEvents = NoorPersonalReminderPlan.make(personal, now: now())
                .filter { !delivered.contains($0.id) }
            let foreignCount = pending.filter { !owns($0) }.count
            let prayerCapacity = max(0, min(PrayerNotificationPlan.maximumRequests, 64 - foreignCount))
            // Travel or a clock change can move an already delivered prayer
            // back into the future. Do not alert again for that prayer/day ID.
            let plan = enabled ? Array(PrayerNotificationPlan.make(data: data, preferences: preferences, now: now())
                .filter { !delivered.contains($0.id) }.prefix(prayerCapacity)) : []
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: data.city.timeZone) ?? .current
            message = nil
            do {
                for event in plan {
                    guard generation == revision, !Task.isCancelled else { break }
                    // A slow scheduler must not submit an already elapsed prayer.
                    guard event.fireDate > now() else { continue }
                    let content = UNMutableNotificationContent()
                    content.title = event.title
                    content.body = "حيّ على الصلاة · " + event.cityName
                    content.threadIdentifier = "noor.prayers"
                    content.userInfo = ["destination": "prayers", "prayer": event.prayer.id]
                    content.sound = PrayerAlertSound.sound(preferences: preferences)
                    var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: event.fireDate)
                    components.timeZone = calendar.timeZone
                    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                    try await client.add(UNNotificationRequest(identifier: event.id, content: content, trigger: trigger))
                    guard generation == revision else { break }
                    scheduledCount += 1
                }
                let remaining = max(0, 64 - foreignCount - scheduledCount)
                for slot in slots.prefix(remaining) {
                    guard generation == revision, !Task.isCancelled else { break }
                    let content = UNMutableNotificationContent()
                    content.title = "الصلاة على النبي ﷺ"; content.body = slot.body
                    content.threadIdentifier = "noor.salawat"; content.sound = nil
                    content.userInfo = ["destination": "dhikr"]
                    var components = DateComponents(); components.hour = slot.hour; components.minute = 0
                    // Keep quiet reminders on the phone's local clock during
                    // travel, even before the saved prayer location updates.
                    try await client.add(.init(identifier: slot.id, content: content,
                        trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)))
                    guard generation == revision else { break }
                    salawatCount += 1
                }
                let personalCapacity = max(0, 64 - foreignCount - scheduledCount - salawatCount)
                for event in personalEvents.prefix(personalCapacity) {
                    guard generation == revision, !Task.isCancelled else { break }
                    guard event.date > now() else { continue }
                    let content = UNMutableNotificationContent()
                    content.title = event.kind.title
                    content.body = "موعدك مع " + event.kind.title
                    content.threadIdentifier = "noor.personal." + event.kind.rawValue
                    content.userInfo = ["destination": event.kind.destination]; content.sound = nil
                    var local = Calendar(identifier: .gregorian); local.timeZone = .current
                    var components = local.dateComponents([.year, .month, .day, .hour, .minute, .second], from: event.date)
                    components.calendar = local; components.timeZone = local.timeZone
                    try await client.add(.init(identifier: event.id, content: content,
                        trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
                    guard generation == revision else { break }
                    personalCounts[event.kind.rawValue, default: 0] += 1
                }
                if generation == revision {
                    if personalEnabled && personalEvents.isEmpty {
                        message = "لا يوجد موعد قادم خلال 7 أيام؛ راجع أيام القراءة وأوقات الهدوء."
                    } else if personalCounts.values.reduce(0, +) < personalEvents.count {
                        message = "جُدولت أقرب التذكيرات حسب المساحة المتاحة. افتح التطبيق لتجديدها؛ الأولوية لتنبيهات الصلاة."
                    }
                    if enabled && plan.isEmpty { message = "لم تتوفر مواقيت صالحة أو مساحة لجدولة الصلاة. حدّث الموقع وراجع التذكيرات." }
                    else if salawat.enabled && salawatCount < slots.count {
                        message = "مساحة الإشعارات ممتلئة. قلّل التذكيرات الأخرى ثم أعد المحاولة؛ أعطينا أولوية لتنبيهات الصلاة."
                    }
                    return
                }
            } catch {
                if generation != revision { continue }
                client.removePending(plan.map(\.id) + slots.map(\.id) + personalEvents.map(\.id))
                enabled = false; scheduledCount = 0; salawatCount = 0; personalCounts = [:]
                message = "تعذرت جدولة التنبيهات. حاول مجددًا من إعدادات التنبيهات."
                return
            }
        }
    }
}
