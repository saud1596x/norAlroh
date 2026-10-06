import SwiftUI
import UserNotifications
import AlarmKit
import CryptoKit

@MainActor final class FridayStore: ObservableObject {
    @Published private(set) var preferences = FridayPreferences()
    @Published private(set) var days: [String: FridayDay] = [:]
    @Published private(set) var notificationsEnabled = false
    @Published private(set) var busy = false
    @Published var message: String?
    private let defaults: UserDefaults
    private var generation = 0
    private let center = UNUserNotificationCenter.current()
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let d = defaults.data(forKey: "noor.friday.preferences"), let p = try? JSONDecoder().decode(FridayPreferences.self, from: d), p.valid { preferences = p }
        if let d = defaults.data(forKey: "noor.friday.days"), let value = try? JSONDecoder().decode([String: FridayDay].self, from: d), value.values.allSatisfy({ $0.count >= 0 && $0.completed.isSubset(of: ["ghusl", "early", "listen"]) }) { days = value }
        notificationsEnabled = defaults.bool(forKey: "noor.friday.notifications")
    }
    func day(at date: Date = Date(), city: City) -> FridayDay { days[FridayPlan.dayKey(date, city: city)] ?? FridayDay() }
    func update(_ value: FridayPreferences) {
        guard value.valid else { return }
        do { defaults.set(try JSONEncoder().encode(value), forKey: "noor.friday.preferences"); preferences = value }
        catch { message = "تعذّر حفظ إعدادات الجمعة." }
    }
    private func change(at date: Date, city: City, action: (inout FridayDay) -> Void) {
        guard FridayPlan.active(at: date, city: city) else { return }
        var next = days; let key = FridayPlan.dayKey(date, city: city); var value = next[key] ?? FridayDay(); action(&value); next[key] = value
        do { defaults.set(try JSONEncoder().encode(next), forKey: "noor.friday.days"); days = next }
        catch { message = "تعذّر حفظ تقدم الجمعة." }
    }
    func count(at date: Date = Date(), city: City, delta: Int) { change(at: date, city: city) { $0.count = max(0, min(1_000_000_000, $0.count + delta)) } }
    func set(_ id: String, completed: Bool, at date: Date = Date(), city: City) {
        guard ["ghusl", "early", "listen"].contains(id) else { return }
        change(at: date, city: city) { if completed { $0.completed.insert(id) } else { $0.completed.remove(id) } }
    }
    func enableNotifications(data: DeviceData) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        let revision = generation
        do {
            guard try await center.requestAuthorization(options: [.alert, .sound]) else { message = "امنح إذن الإشعارات من إعدادات الجهاز."; return }
            guard revision == generation else { return }
            notificationsEnabled = true; defaults.set(true, forKey: "noor.friday.notifications")
        } catch { message = "تعذّر طلب إذن الإشعارات."; return }
        await refresh(data: data)
    }
    func disableNotifications() {
        generation += 1; notificationsEnabled = false; defaults.set(false, forKey: "noor.friday.notifications")
        Task { let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(FridayPlan.prefix) }; guard !notificationsEnabled else { return }; center.removePendingNotificationRequests(withIdentifiers: ids) }
    }
    func refresh(data: DeviceData) async {
        generation += 1; let revision = generation
        let pending = await center.pendingNotificationRequests()
        guard revision == generation else { return }
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(FridayPlan.prefix) })
        guard notificationsEnabled else { return }
        let capacity = max(0, 64 - pending.filter { !$0.identifier.hasPrefix(FridayPlan.prefix) }.count)
        let events = Array(FridayPlan.events(data: data, preferences: preferences).prefix(capacity))
        // Existing prayer notifications already cover these times; avoid a second reminder for each prayer.
        let prayersEnabled = defaults.bool(forKey: "athar.prayerNotifications")
        let existingPrayers = (defaults.data(forKey: "noor.prayerPreferences.v1").flatMap { try? JSONDecoder().decode(PrayerNotificationPreferences.self, from: $0) }) ?? PrayerNotificationPreferences()
        do {
            for event in events {
                guard revision == generation else { return }
                let suffix = event.id.split(separator: ".").last.map(String.init) ?? ""
                if event.prayer && prayersEnabled && existingPrayers.prayers[suffix] == true { continue }
                let content = UNMutableNotificationContent(); content.title = "نور الروح · " + event.title; content.body = event.body; content.sound = .default
                var components = FridayPlan.calendar(for: data.city).dateComponents([.year, .month, .day, .hour, .minute, .second], from: event.date)
                components.timeZone = TimeZone(identifier: data.city.timeZone)
                try await center.add(.init(identifier: event.id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
                if revision != generation { center.removePendingNotificationRequests(withIdentifiers: [event.id]); return }
            }
        } catch { center.removePendingNotificationRequests(withIdentifiers: events.map(\.id)); message = "تعذّرت جدولة تذكيرات الجمعة. أعد التفعيل." }
    }
    func erase() { disableNotifications(); days = [:]; preferences = FridayPreferences(); defaults.removeObject(forKey: "noor.friday.days"); defaults.removeObject(forKey: "noor.friday.preferences") }
}

@available(iOS 26.0, *) private struct FridayAlarmMetadata: AlarmMetadata {}
@MainActor final class FridayAlarms: ObservableObject {
    @Published private(set) var enabled = UserDefaults.standard.bool(forKey: "noor.friday.alarms")
    @Published private(set) var busy = false
    @Published var message: String?
    private var ids: [UUID] { (UserDefaults.standard.stringArray(forKey: "noor.friday.alarmIDs") ?? []).compactMap(UUID.init(uuidString:)) }
    private func id(_ value: String) -> UUID {
        let hex = SHA256.hash(data: Data(value.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
        return UUID(uuidString: "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20))")!
    }
    func disable() {
        guard !busy else { return }
        if #available(iOS 26.0, *) {
            do { for value in try AlarmManager.shared.alarms.map(\.id) where ids.contains(value) { try AlarmManager.shared.cancel(id: value) } }
            catch { message = "تعذّر إلغاء بعض المنبهات. أزلها من إعدادات منبهات الجهاز."; return }
        }
        enabled = false; UserDefaults.standard.set(false, forKey: "noor.friday.alarms"); UserDefaults.standard.removeObject(forKey: "noor.friday.alarmIDs")
    }
    func schedule(data: DeviceData, preferences: FridayPreferences, requestPermission: Bool = false) async {
        guard !busy, requestPermission || enabled else { return }
        guard #available(iOS 26.0, *) else { message = "منبه الاستيقاظ يحتاج iOS 26 أو أحدث؛ الإشعارات وحدها لا تضمن إيقاظك."; return }
        busy = true; defer { busy = false }
        do {
            let manager = AlarmManager.shared
            let permission = requestPermission ? try await manager.requestAuthorization() : manager.authorizationState
            guard permission == .authorized else { enabled = false; message = "إذن منبهات الاستيقاظ غير مفعّل. راجع إعدادات الجهاز."; return }
            for value in try manager.alarms.map(\.id) where ids.contains(value) { try manager.cancel(id: value) }
            let events = FridayPlan.events(data: data, preferences: preferences).filter(\.prayer)
            let values = events.map { id($0.id) }
            UserDefaults.standard.set(values.map(\.uuidString), forKey: "noor.friday.alarmIDs")
            for (event, value) in zip(events, values) {
                let stop = AlarmButton(text: "إيقاف", textColor: .white, systemImageName: "stop.circle")
                let alert = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: event.title), stopButton: stop)
                let attributes = AlarmAttributes<FridayAlarmMetadata>(presentation: AlarmPresentation(alert: alert), tintColor: Theme.gold)
                let config = AlarmManager.AlarmConfiguration<FridayAlarmMetadata>(schedule: .fixed(event.date), attributes: attributes)
                _ = try await manager.schedule(id: value, configuration: config)
            }
            enabled = true; UserDefaults.standard.set(true, forKey: "noor.friday.alarms")
            message = events.isEmpty ? "انتهت مواقيت الجمعة اليوم؛ افتح التطبيق خلال الأسبوع لتجهيز الجمعة القادمة." : "تمت جدولة \(events.count) منبهات للجمعة القادمة. افتح التطبيق أسبوعيًا لتحديث المواقيت."
        } catch {
            if #available(iOS 26.0, *) { for value in ids { try? AlarmManager.shared.cancel(id: value) } }
            enabled = false; UserDefaults.standard.set(false, forKey: "noor.friday.alarms"); message = "تعذّرت جدولة منبهات الجمعة. لا تعتمد عليها حتى ينجح التفعيل."
        }
    }
}

struct FridayView: View {
    @EnvironmentObject private var store: AtharStore
    @EnvironmentObject private var friday: FridayStore
    @EnvironmentObject private var alarms: FridayAlarms
    @State private var settings = false
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Form {
                if FridayPlan.active(at: context.date, city: store.data.city) {
                    Section("خطوات الجمعة") {
                        step("ghusl", "الغسل والاستعداد", date: context.date)
                        step("early", "التبكير إلى المسجد", date: context.date)
                        step("listen", "الإنصات للخطبة", date: context.date)
                    }
                    Section("الصلاة على النبي ﷺ") {
                        Text("اللهم صل وسلم على نبينا محمد").font(.title3)
                        let value = friday.day(at: context.date, city: store.data.city).count
                        Text("\(value) / \(friday.preferences.target)").font(.largeTitle.monospacedDigit()).accessibilityIdentifier("friday.count")
                        Button("إضافة صلاة على النبي ﷺ") { friday.count(city: store.data.city, delta: 1) }.frame(minHeight: 56)
                        Button("تراجع عن آخر ضغطة") { friday.count(city: store.data.city, delta: -1) }.disabled(value == 0)
                        Text("الهدف عدد تختاره أنت للتنظيم، ولا ينسب التطبيق فضلًا مخصوصًا لهذا العدد.").font(.caption).foregroundStyle(.secondary)
                    }
                    Section { Button("إعدادات الجمعة") { settings = true } }
                } else { Section { Text("تفتح قائمة يوم الجمعة يوم الجمعة حسب توقيت \(store.data.city.name).") } }
            }.navigationTitle("يوم الجمعة")
        }
        .sheet(isPresented: $settings) { NavigationStack { FridaySettingsView() } }
    }
    private func step(_ id: String, _ title: String, date: Date) -> some View {
        Toggle(title, isOn: Binding(get: { friday.day(at: date, city: store.data.city).completed.contains(id) }, set: { friday.set(id, completed: $0, city: store.data.city) }))
    }
}
struct FridaySettingsView: View {
    @EnvironmentObject private var store: AtharStore
    @EnvironmentObject private var friday: FridayStore
    @EnvironmentObject private var alarms: FridayAlarms
    @Environment(\.dismiss) private var dismiss
    @State private var draft = FridayPreferences()
    @State private var goal = "100"
    private func time(_ key: WritableKeyPath<FridayPreferences, Int>) -> Binding<Date> {
        Binding(get: { FridayPlan.calendar(for: store.data.city).date(from: DateComponents(year: 2026, month: 1, day: 15, hour: draft[keyPath: key] / 60, minute: draft[keyPath: key] % 60)) ?? Date() }, set: {
            let c = FridayPlan.calendar(for: store.data.city).dateComponents([.hour, .minute], from: $0); draft[keyPath: key] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        })
    }
    var body: some View {
        Form {
            Section("خطتك") {
                TextField("هدفك الشخصي للصلاة على النبي ﷺ", text: $goal).keyboardType(.numberPad)
                DatePicker("موعد المسجد الذي تختاره", selection: time(\.mosqueMinutes), displayedComponents: .hourAndMinute)
                DatePicker("تذكير الغسل", selection: time(\.ghuslMinutes), displayedComponents: .hourAndMinute)
                Picker("التبكير قبل موعدك", selection: $draft.earlyMinutes) { ForEach([30, 60, 90, 120], id: \.self) { Text("\($0) دقيقة").tag($0) } }
                Picker("تكرار الصلاة على النبي ﷺ", selection: $draft.reminderMinutes) { ForEach([60, 120, 180, 240], id: \.self) { Text("كل \($0) دقيقة").tag($0) } }
                Picker("الاستيقاظ قبل الفجر", selection: $draft.wakeAdvance) { ForEach([0, 5, 10, 15, 30], id: \.self) { Text("\($0) دقيقة").tag($0) } }
                Text("الأوقات بتوقيت المدينة المختارة. تذكيرات الصلاة على النبي ﷺ بين 8 صباحًا و8 مساءً، مع فترة هدوء حول موعد المسجد.").font(.caption)
                Button("حفظ خطة الجمعة") {
                    guard let target = Int(goal.compactMap { $0.wholeNumberValue.map(String.init) }.joined()), goal.allSatisfy({ $0.wholeNumberValue != nil }), (1...1_000_000).contains(target) else { friday.message = "اختر هدفًا صحيحًا بين 1 ومليون."; return }
                    draft.target = target; friday.update(draft)
                    Task { await friday.refresh(data: store.data); await alarms.schedule(data: store.data, preferences: friday.preferences) }
                }
            }
            Section("التذكيرات") {
                Button(friday.notificationsEnabled ? "إيقاف تذكيرات الجمعة" : "تفعيل تذكيرات الجمعة") {
                    if friday.notificationsEnabled { friday.disableNotifications() } else { Task { await friday.enableNotifications(data: store.data) } }
                }.disabled(friday.busy)
                Text("تذكيرات أسبوع الجمعة القادم تُحدّث عند فتح التطبيق. الإشعارات تتأثر بوضع الصامت والتركيز.").font(.caption)
            }
            Section("منبه الاستيقاظ للصلاة") {
                if #available(iOS 26.0, *) {
                    Button(alarms.enabled ? "إيقاف منبهات الجمعة" : "تفعيل منبهات الجمعة") {
                        if alarms.enabled { alarms.disable() } else { Task { await alarms.schedule(data: store.data, preferences: friday.preferences, requestPermission: true) } }
                    }.disabled(alarms.busy)
                } else { Text("يحتاج منبه الاستيقاظ iOS 26 أو أحدث. يمكنك استخدام منبه الجهاز مع تذكيرات التطبيق.") }
                if let text = alarms.message { Text(text).font(.caption) }
            }
            if let text = friday.message { Section { Text(text).foregroundStyle(.secondary) } }
        }.environment(\.timeZone, TimeZone(identifier: store.data.city.timeZone) ?? .current).navigationTitle("إعدادات الجمعة")
            .onAppear { draft = friday.preferences; goal = String(draft.target) }
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("تم") { dismiss() } } }
    }
}
