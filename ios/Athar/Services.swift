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
    func authorizationStatus() async -> PrayerAuthorizationState
    func requestAuthorization() async throws -> Bool
    func isAuthorized() async -> Bool
    func pendingIdentifiers() async -> [String]
    func pendingRequests() async -> [UNNotificationRequest]
    func deliveredIdentifiers() async -> [String]
    func add(_ request: UNNotificationRequest) async throws
    func removePending(_ identifiers: [String])
    func removeDelivered(_ identifiers: [String])
}
extension PrayerNotificationClient {
    // Compatibility for existing injected clients. New permission-contract
    // fixtures override this so denied and undetermined remain distinguishable.
    func authorizationStatus() async -> PrayerAuthorizationState {
        await isAuthorized() ? .authorized : .notDetermined
    }
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
    func authorizationStatus() async -> PrayerAuthorizationState {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: return .notDetermined
        case .authorized, .provisional, .ephemeral: return .authorized
        case .denied: return .denied
        @unknown default: return .unavailable
        }
    }
    func pendingIdentifiers() async -> [String] { await center.pendingNotificationRequests().map(\.identifier) }
    func pendingRequests() async -> [UNNotificationRequest] { await center.pendingNotificationRequests() }
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
    @Published private(set) var requestingPermission = false
    @Published private(set) var prayerAuthorization: PrayerAuthorizationState = .notDetermined
    @Published private(set) var notificationAuthorization: PrayerAuthorizationState = .notDetermined
    @Published private(set) var policyRequested: Bool
    @Published private(set) var locationIsTrusted = false
    @Published private(set) var prayerCoverageThrough: Date?
    @Published private(set) var reminderCoverageThrough: Date?
    var usesAlarmKit: Bool { alarms.available }
    var personalExport: Data? { defaults.data(forKey: personalKey) }
    private let personalKey = "noor.personalReminders.v1"
    private let policyKey = "noor.fixedPrayer.requested.v2"
    private let recordsKey = "noor.fixedPrayer.alarmRecords.v2"
    private let consumedKey = "noor.fixedPrayer.delivered.v2"
    private let floorKey = "noor.fixedPrayer.historyFloor.v2"
    private let client: any PrayerNotificationClient
    private let alarms: any PrayerAlarmClient
    private let defaults: UserDefaults
    private let now: () -> Date
    private var records: [String: PrayerAlarmRecord] = [:]
    private var recordsUnreadable = false
    private var revision = 0
    private var authorizationRevision = 0
    private var refreshing = false
    private var latestData: DeviceData?

    init(client: (any PrayerNotificationClient)? = nil, alarms: (any PrayerAlarmClient)? = nil,
         defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.client = client ?? SystemPrayerNotificationClient()
        self.alarms = alarms ?? SystemPrayerAlarmClient()
        self.defaults = defaults; self.now = now
        policyRequested = defaults.bool(forKey: "noor.fixedPrayer.requested.v2")
        // Archives are retained for export/migration, never used as v2 policy inputs.
        if let bytes = defaults.data(forKey: "noor.prayerPreferences.v1"),
           let value = try? JSONDecoder().decode(PrayerNotificationPreferences.self, from: bytes) { preferences = value }
        if let bytes = defaults.data(forKey: personalKey) {
            if let value = try? JSONDecoder().decode(NoorReminderArchive.self, from: bytes), value.valid { personal = value }
            else { personalUnreadable = true }
        }
        if let bytes = defaults.data(forKey: recordsKey) {
            if let value = try? JSONDecoder().decode([String: PrayerAlarmRecord].self, from: bytes),
               Set(value.values.map(\.id)).count == value.count,
               value.keys.allSatisfy({ $0.hasPrefix(FixedPrayerPolicy.prefix) }) { records = value }
            else { recordsUnreadable = true }
        }
    }

    static func hasTrustedLocation(_ data: DeviceData, defaults: UserDefaults = .standard, now: Date = Date()) -> Bool {
        let city = data.city
        guard city.latitude.isFinite, city.longitude.isFinite,
              (-90...90).contains(city.latitude), (-180...180).contains(city.longitude),
              TimeZone(identifier: city.timeZone) != nil, City.normalized(city) == city else { return false }
        if defaults.string(forKey: "noor.fixedPrayer.locationConfirmedCity.v2") == city.id { return true }
        guard city.id.hasPrefix("location."), let updated = data.locationUpdatedAt else { return false }
        return updated.timeIntervalSince1970 > 0 && updated <= now.addingTimeInterval(300)
    }
    func confirmLocation(store: AtharStore) async {
        guard City.normalized(store.data.city) == store.data.city else { return }
        defaults.set(store.data.city.id, forKey: "noor.fixedPrayer.locationConfirmedCity.v2")
        await refresh(store: store)
    }
    /// Read-only permission refresh. The launch path must never surprise a user
    /// with either OS prompt before the policy has been explained in the UI.
    func configureFirstUse(store: AtharStore) async { await refresh(store: store) }

    /// Called only by the explicit action next to the policy description.
    func enable(store: AtharStore) async {
        guard !requestingPermission else { return }
        requestingPermission = true
        policyRequested = true; defaults.set(true, forKey: policyKey)
        let generation = authorizationRevision
        defer { requestingPermission = false }
        var errors = false
        if usesAlarmKit && alarms.authorizationStatus() == .notDetermined {
            do { _ = try await alarms.requestAuthorization() } catch { errors = true }
        }
        guard generation == authorizationRevision, !Task.isCancelled else { return }
        let notificationStatus = await client.authorizationStatus()
        guard generation == authorizationRevision, !Task.isCancelled else { return }
        if notificationStatus == .notDetermined {
            do { _ = try await client.requestAuthorization() } catch { errors = true }
        }
        guard generation == authorizationRevision, !Task.isCancelled else { return }
        await refresh(store: store)
        if errors { message = "تعذر إكمال طلب أحد الإذنين. بقيت الصلاحية الأخرى مستقلة؛ راجع حالة النظام وأعد المحاولة." }
    }
    func disable() {
        authorizationRevision += 1; revision += 1
        policyRequested = false; defaults.set(false, forKey: policyKey)
        enabled = false
        if latestData == nil { latestData = DeviceData() } // Cleanup only; policy is off.
        Task { await self.reconcileLatest() }
    }
    func erasePreferences() {
        disable()
        for key in [personalKey, "noor.prayerPreferences.v1", "noor.salawat.preferences.v1", "athar.prayerNotifications"] {
            defaults.removeObject(forKey: key)
        }
        preferences = .init(); personal = .init(); personalUnreadable = false
        // Keep failed cancellation identities and observed-removed tombstones.
    }
    // Compatibility for old internal callers/exported archives only. No v1
    // frequency/sound/prayer selection can change the fixed production policy.
    func reminder(_ kind: NoorReminderKind) -> NoorReminderPreference {
        var value = NoorReminderPreference(kind: kind)
        value.enabled = policyRequested && [.salawat, .witr, .duha].contains(kind)
        if kind == .salawat { value.intervalMinutes = 5; value.startMinute = 0; value.endMinute = 1439 }
        return value
    }
    func setReminder(_ kind: NoorReminderKind, preference: NoorReminderPreference, store: AtharStore) async { await refresh(store: store) }
    func setPrayer(_ id: String, enabled: Bool, store: AtharStore) async { await refresh(store: store) }
    func setAdvance(_ value: Int, store: AtharStore) async { await refresh(store: store) }
    func setAfterPrayer(_ minutes: Int?, store: AtharStore) async { await refresh(store: store) }
    func setSound(_ value: Bool, store: AtharStore) async { await refresh(store: store) }
    func setSoundStyle(_ value: String, store: AtharStore) async { await refresh(store: store) }
    func setSalawatInterval(_ hours: Int, store: AtharStore) async { await refresh(store: store) }
    func setSalawatEnabled(_ value: Bool, store: AtharStore) async { await refresh(store: store) }

    func refresh(store: AtharStore) async {
        latestData = store.data; revision += 1
        await reconcileLatest()
    }
    private func reconcileLatest() async {
        guard !refreshing, latestData != nil else { return }
        refreshing = true
        var handledGeneration = revision
        defer {
            refreshing = false
            // A cancelled background task must not strand a newer foreground
            // disable/location change behind its in-flight scheduling call.
            if handledGeneration != revision { Task { await self.reconcileLatest() } }
        }
        repeat {
            let generation = revision
            handledGeneration = generation
            guard let data = latestData else { return }
            await reconcile(data: data, generation: generation)
            if Task.isCancelled {
                scheduledCount = 0; prayerCoverageThrough = nil; reminderCoverageThrough = nil
                message = "توقف التحقق من الجداول قبل اكتماله؛ المواعيد السابقة لم تُعتبر تغطية مؤكدة."
                return
            }
            if generation == revision { return }
        } while true
    }
    private func persistRecords() -> Bool {
        guard !recordsUnreadable, let bytes = try? JSONEncoder().encode(records) else { return false }
        defaults.set(bytes, forKey: recordsKey)
        return defaults.data(forKey: recordsKey) == bytes
    }
    private func matches(_ actual: UNNotificationRequest, _ wanted: UNNotificationRequest) -> Bool {
        actual.identifier == wanted.identifier && actual.content == wanted.content && actual.trigger == wanted.trigger
    }
    private func coverage(_ events: [FixedPrayerEvent], matching ids: Set<String>) -> Date? {
        var last: Date?
        for event in events.sorted(by: { $0.fireDate < $1.fireDate }) {
            guard ids.contains(event.id) else { break }
            last = event.fireDate
        }
        return last
    }
    private func reconcile(data: DeviceData, generation: Int) async {
        let currentTime = now()
        locationIsTrusted = Self.hasTrustedLocation(data, defaults: defaults, now: currentTime)
        notificationAuthorization = await client.authorizationStatus()
        guard generation == revision, !Task.isCancelled else { return }
        prayerAuthorization = usesAlarmKit ? alarms.authorizationStatus() : notificationAuthorization
        enabled = policyRequested && prayerAuthorization == .authorized && locationIsTrusted
        var errors: [String] = []
        let savedFloor = defaults.object(forKey: floorKey) as? Date
        let floorReadable = defaults.object(forKey: floorKey) == nil || savedFloor != nil
        let floor = FixedPrayerPolicy.historyFloor(previous: savedFloor, now: currentTime)
        let clockUnsafe = !floorReadable || currentTime < floor
        if floorReadable { defaults.set(floor, forKey: floorKey) }
        if clockUnsafe {
            errors.append("تاريخ الجهاز أقدم من سجل الجدولة الموثوق أو تعذر قراءة حده؛ صحّح التاريخ ثم أعد الفتح. أبقينا التذكير المتكرر ولم ننشئ أحداثاً مؤرخة قد تتكرر.")
        }
        let events = policyRequested && locationIsTrusted && !clockUnsafe ? FixedPrayerPolicy.make(data: data, now: currentTime) : []
        let prayers = Array(events.filter { $0.kind == .prayer }.prefix(FixedPrayerPolicy.prayerBudget))
        let quiet = events.filter { $0.kind != .prayer }
        let delivered = Set(await client.deliveredIdentifiers())
        guard generation == revision, !Task.isCancelled else { return }
        let oldConsumed = defaults.stringArray(forKey: consumedKey)
        let decodedConsumed = defaults.data(forKey: consumedKey).flatMap { try? JSONDecoder().decode([String: Date].self, from: $0) }
        let consumedReadable = defaults.object(forKey: consumedKey) == nil || oldConsumed != nil || decodedConsumed != nil
        var consumedDates = decodedConsumed ?? Dictionary(uniqueKeysWithValues: Set(oldConsumed ?? []).map {
            ($0, FixedPrayerPolicy.conservativeEventHistoryDate($0) ?? currentTime)
        })
        for id in delivered where id.hasPrefix(FixedPrayerPolicy.prefix) && id != FixedPrayerPolicy.salawatID {
            if consumedDates[id] == nil { consumedDates[id] = FixedPrayerPolicy.conservativeEventHistoryDate(id) ?? currentTime }
        }
        if !clockUnsafe { consumedDates = consumedDates.filter { $0.value >= floor } }
        let consumed = Set(consumedDates.keys)
        if consumedReadable, let bytes = try? JSONEncoder().encode(consumedDates) { defaults.set(bytes, forKey: consumedKey) }
        else { errors.append("تعذر قراءة سجل الإشعارات السابقة؛ احتفظنا به ولم نعد إنشاء أحداث مؤرخة مفقودة.") }
        let pending = await client.pendingRequests()
        guard generation == revision, !Task.isCancelled else { return }
        // Clean only IDs owned by replaced versions; no reading/account data.
        let retiredPending = pending.map(\.identifier).filter(FixedPrayerPolicy.isLegacyID)
        if !retiredPending.isEmpty { client.removePending(retiredPending) }
        let retiredDelivered = delivered.filter(FixedPrayerPolicy.isLegacyID)
        if !retiredDelivered.isEmpty { client.removeDelivered(Array(retiredDelivered)) }
        defaults.set(FixedPrayerPolicy.version, forKey: "noor.fixedPrayer.policyVersion")

        var alarmMatches: Set<String> = []
        if usesAlarmKit {
            if recordsUnreadable { errors.append("تعذر قراءة سجل المنبهات؛ احتفظنا به ولم ننشئ معرفات بديلة قد تكرر المنبهات.") }
            else {
                do {
                    let actual = try alarms.currentAlarms()
                    let actualByID = Dictionary(uniqueKeysWithValues: actual.map { ($0.id, $0) })
                    let desired = prayerAuthorization == .authorized && policyRequested ? prayers : []
                    let desiredByID = Dictionary(uniqueKeysWithValues: desired.map { ($0.id, $0) })
                    for key in Array(records.keys) {
                        guard var record = records[key] else { continue }
                        if actualByID[record.id] == nil && (record.state == .scheduled || record.state == .pending) {
                            // Absence proves removal, not whether a person tapped stop.
                            record.state = .observedRemoved; records[key] = record
                        }
                        if actualByID[record.id] == nil && record.state == .retryable && record.fireDate < currentTime {
                            record.state = .expired; records[key] = record
                        }
                        if actualByID[record.id] != nil && desiredByID[key] == nil &&
                            (!policyRequested || (!clockUnsafe && record.fireDate > currentTime)) {
                            do { try alarms.cancel(id: record.id); record.state = .cancelled; records[key] = record }
                            catch { errors.append("تعذر إلغاء منبه سابق؛ احتفظنا بمعرفه لإعادة المحاولة.") }
                        }
                    }
                    if !clockUnsafe {
                        records = FixedPrayerPolicy.retainAlarmHistory(records, floor: floor, activeIDs: Set(actualByID.keys))
                    }
                    guard persistRecords() else { throw CocoaError(.fileWriteUnknown) }
                    for event in desired {
                        guard generation == revision, !Task.isCancelled else { return }
                        guard event.fireDate > now() else { continue }
                        if let record = records[event.id], record.state == .observedRemoved || record.state == .expired { continue }
                        var record = records[event.id] ?? .init(id: UUID(), fireDate: event.fireDate, state: .retryable)
                        if let actual = actualByID[record.id], actual.fireDate == event.fireDate {
                            record.state = .scheduled; record.fireDate = event.fireDate; records[event.id] = record
                            alarmMatches.insert(event.id)
                            if !persistRecords() { errors.append("تعذر حفظ حالة أحد المنبهات.") }
                            continue
                        }
                        if actualByID[record.id] != nil {
                            do { try alarms.cancel(id: record.id) }
                            catch { errors.append("تعذر استبدال منبه سابق؛ لم نضف منبهاً مكرراً."); continue }
                        }
                        record.fireDate = event.fireDate; record.state = .pending; records[event.id] = record
                        guard persistRecords() else { errors.append("تعذر حفظ معرف المنبه قبل جدولتِه."); continue }
                        do {
                            try await alarms.schedule(id: record.id, event: event)
                            record.state = .scheduled; records[event.id] = record
                            if !persistRecords() { errors.append("تعذر حفظ تأكيد الجدولة؛ نحتاج التحقق عند الفتح التالي.") }
                            if generation == revision { alarmMatches.insert(event.id) }
                        } catch {
                            record.state = error is CancellationError ? .pending : .retryable
                            records[event.id] = record
                            _ = persistRecords()
                            errors.append("لم تكتمل إضافة أحد المنبهات؛ قد تكون سعة النظام غير متاحة.")
                        }
                    }
                } catch { errors.append("تعذر التحقق من منبهات النظام أو حفظ سجلها. لم نحذف المواعيد السليمة.") }
            }
        }
        guard generation == revision, !Task.isCancelled else { return }
        let notificationsAllowed = notificationAuthorization == .authorized && policyRequested
        let fallback = !usesAlarmKit && enabled ? prayers : []
        var desiredRequests = notificationsAllowed ? fallback.map { FixedPrayerPolicy.notification($0,
            timeZone: TimeZone(identifier: data.city.timeZone) ?? .current) } : []
        if notificationsAllowed {
            desiredRequests.append(FixedPrayerPolicy.salawatRequest())
            desiredRequests += quiet.map { FixedPrayerPolicy.notification($0,
                timeZone: TimeZone(identifier: data.city.timeZone) ?? .current) }
        }
        desiredRequests = Array(desiredRequests.filter { !consumed.contains($0.identifier) }
            .prefix(FixedPrayerPolicy.notificationBudget))
        let desiredIDs = Set(desiredRequests.map(\.identifier))
        let obsolete = pending.map(\.identifier).filter {
            $0.hasPrefix(FixedPrayerPolicy.prefix) && !desiredIDs.contains($0) &&
                (!clockUnsafe || !policyRequested || $0 == FixedPrayerPolicy.salawatID)
        }
        if !obsolete.isEmpty { client.removePending(obsolete) }
        var notificationMatches: Set<String> = []
        for request in desiredRequests {
            guard generation == revision, !Task.isCancelled else { return }
            if let old = pending.first(where: { $0.identifier == request.identifier }), matches(old, request) {
                notificationMatches.insert(request.identifier); continue
            }
            guard consumedReadable || request.identifier == FixedPrayerPolicy.salawatID else { continue }
            if let event = events.first(where: { $0.id == request.identifier }), event.fireDate <= now() { continue }
            do {
                // UN replaces only this identifier; valid repeats and all
                // unrelated requests survive a failed neighbouring addition.
                try await client.add(request)
                if generation == revision { notificationMatches.insert(request.identifier) }
            } catch { errors.append("لم تكتمل إضافة بعض الإشعارات. بقيت الطلبات السليمة؛ أعد المحاولة لتجديد التغطية.") }
        }
        guard generation == revision, !Task.isCancelled else { return }
        // Accepted API calls are not proof that the entire desired queue
        // remains registered after a capacity/daemon change. Read it back.
        let finalPending = await client.pendingRequests()
        guard generation == revision, !Task.isCancelled else { return }
        notificationMatches = Set(desiredRequests.filter { wanted in
            finalPending.contains { matches($0, wanted) }
        }.map(\.identifier))
        if notificationMatches.count < desiredRequests.count {
            errors.append("الطلبات المسجلة فعلياً أقل من الخطة؛ التغطية المعروضة تخص ما أمكن التحقق منه فقط.")
        }
        if usesAlarmKit && prayerAuthorization == .authorized && !recordsUnreadable {
            do {
                let finalAlarms = try alarms.currentAlarms()
                alarmMatches = Set(prayers.filter { event in
                    guard let record = records[event.id], record.state == .scheduled else { return false }
                    return finalAlarms.contains { $0.id == record.id && $0.fireDate == event.fireDate }
                }.map(\.id))
                if enabled && alarmMatches.count < prayers.count {
                    errors.append("نافذة منبهات الصلاة غير مكتملة؛ التغطية المعروضة تخص المنبهات المسجلة فعلياً فقط.")
                }
            } catch {
                alarmMatches = []
                errors.append("تعذر تأكيد قائمة المنبهات النهائية؛ لم نعتبر الطلبات غير المتحققة تغطية ناجحة.")
            }
        }
        let matchedPrayers = usesAlarmKit ? alarmMatches : notificationMatches
        scheduledCount = prayers.filter { matchedPrayers.contains($0.id) }.count
        salawatCount = notificationMatches.contains(FixedPrayerPolicy.salawatID) ? 1 : 0
        salawat.enabled = salawatCount == 1
        personalCounts = ["witr": quiet.filter { $0.kind == .witr && notificationMatches.contains($0.id) }.count,
                          "duha": quiet.filter { $0.kind == .duha && notificationMatches.contains($0.id) }.count]
        prayerCoverageThrough = coverage(prayers, matching: matchedPrayers)
        reminderCoverageThrough = coverage(quiet.filter { !consumed.contains($0.id) }, matching: notificationMatches)
        if policyRequested && !locationIsTrusted { errors.append("اختر مدينتك أو أكّد الموقع أولاً؛ لم نجدول مواقيت لمكان افتراضي.") }
        if policyRequested && prayerAuthorization == .denied { errors.append("إذن منبهات الصلاة غير متاح. يمكنك تغييره من إعدادات iPhone.") }
        if policyRequested && notificationAuthorization == .denied { errors.append("الإشعارات النصية غير مسموحة؛ إذن منبهات الصلاة مستقل عنها.") }
        if policyRequested && locationIsTrusted && prayers.isEmpty { errors.append("لم تتوفر مواقيت صالحة ضمن نافذة التغطية؛ لم نخترع موعداً.") }
        if usesAlarmKit && policyRequested && prayerAuthorization == .authorized && !alarms.fixedSoundAvailable {
            errors.append("ملف صوت الصلاة غير صالح حالياً؛ يستخدم منبّه النظام صوته الافتراضي بدلاً منه.")
        }
        if usesAlarmKit && prayers.contains(where: { records[$0.id]?.state == .observedRemoved }) {
            errors.append("رصدنا منبهاً أزيل من النظام؛ لن نعيد إنشاء الحدث نفسه تلقائياً.")
        }
        var seen: Set<String> = []
        message = errors.isEmpty ? nil : errors.filter { seen.insert($0).inserted }.joined(separator: " ")
    }
}
