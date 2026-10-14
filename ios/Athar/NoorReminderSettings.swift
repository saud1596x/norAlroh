import SwiftUI
import UIKit

struct NoorReminderSettings: View {
    @EnvironmentObject private var notifications: PrayerNotifications
    var body: some View {
        List {
            Section {
                NavigationLink("تنبيهات الصلاة") { PrayerNotificationSettings() }
            }
            Section("تذكيرات مستقلة") {
                ForEach([NoorReminderKind.morning, .evening, .witr, .duha, .salawat]) { kind in
                    NavigationLink {
                        NoorReminderEditor(kind: kind, initial: notifications.reminder(kind))
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(kind.title)
                            Text(notifications.reminder(kind).enabled ? "مفعّل" : "متوقف")
                                .font(.caption).foregroundStyle(.secondary)
                        }.frame(minHeight: 44)
                    }.accessibilityIdentifier("reminders.\(kind.rawValue)")
                }
            }
            Section {
                if notifications.personalUnreadable { Text("تعذر قراءة الإعدادات؛ بقيت محفوظة دون تغيير. صدّر بياناتك من الإعدادات.") }
                if let message = notifications.message { Text(message).foregroundStyle(.secondary) }
                Button("إعدادات إشعارات iPhone") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                Text("الصلوات بصوت حسب اختيارك، والأذكار والصلاة على النبي رسائل صامتة. يتحكم iPhone في ظهور التنبيهات عند تفعيل التركيز.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.noorScreenChrome().navigationTitle("تذكيراتي").tint(Theme.gold)
    }
}

struct NoorReminderEditor: View {
    @EnvironmentObject private var notifications: PrayerNotifications
    @EnvironmentObject private var store: AtharStore
    @Environment(\.dismiss) private var dismiss
    let kind: NoorReminderKind
    @State private var saving = false
    @State private var draft: NoorReminderPreference
    init(kind: NoorReminderKind, initial: NoorReminderPreference) {
        self.kind = kind
        var value = initial
        if kind == .salawat {
            value.intervalMinutes = 5; value.startMinute = 0; value.endMinute = 1439
            value.weekdays = Set(1...7); value.quietEnabled = false
        }
        _draft = State(initialValue: value)
    }
    private let days = [(1,"الأحد"),(2,"الاثنين"),(3,"الثلاثاء"),(4,"الأربعاء"),(5,"الخميس"),(6,"الجمعة"),(7,"السبت")]
    var body: some View {
        Form {
            Section {
                Toggle("تفعيل التذكير", isOn: $draft.enabled).accessibilityIdentifier("reminder.enabled")
                if kind != .salawat || draft.intervalMinutes != 5 {
                    time("وقت التذكير", value: $draft.startMinute, id: "start")
                }
                if kind != .salawat {
                Picker("التكرار", selection: $draft.intervalMinutes) {
                    Text("مرة يوميًا").tag(0)
                    Text("كل ساعتين").tag(120)
                    Text("كل 4 ساعات").tag(240)
                    Text("كل 6 ساعات").tag(360)
                    Text("كل 12 ساعة").tag(720)
                }.accessibilityIdentifier("reminder.frequency")
                }
                if draft.intervalMinutes > 5 { time("نهاية التذكيرات", value: $draft.endMinute, id: "end") }
                if kind == .salawat && draft.intervalMinutes == 5 {
                    Text("❀ اللهم صلِّ على نبينا محمد ﷺ ❀")
                    Text("رسالة صامتة كل خمس دقائق طوال اليوم، حتى توقف هذا التذكير.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if kind != .salawat || draft.intervalMinutes != 5 {
            Section("أيام التذكير") {
                ForEach(days, id: \.0) { day, title in
                    Toggle(title, isOn: Binding(get: { draft.weekdays.contains(day) }, set: { value in
                        if value { draft.weekdays.insert(day) }
                        else if draft.weekdays.count > 1 { draft.weekdays.remove(day) }
                    })).accessibilityIdentifier("reminder.weekday.\(day)")
                }
            }
            Section("أوقات الهدوء") {
                Toggle("إيقاف التذكير خلال الهدوء", isOn: $draft.quietEnabled).accessibilityIdentifier("reminder.quiet")
                if draft.quietEnabled {
                    time("بداية الهدوء", value: $draft.quietStart, id: "quietStart")
                    time("نهاية الهدوء", value: $draft.quietEnd, id: "quietEnd")
                    Text("يمكن أن يمتد الهدوء إلى اليوم التالي. تطابق البداية والنهاية يعني هدوءًا طوال اليوم.").font(.caption)
                }
            }
            }
            Section {
                if !draft.valid { Text("اجعل نهاية التذكيرات بعد بدايتها، واختر يومًا واحدًا على الأقل.") }
                if draft.enabled && draft.minutes.isEmpty { Text("كل المواعيد تقع في وقت الهدوء؛ لن يُرسل هذا التذكير.") }
                if let message = notifications.message { Text(message).foregroundStyle(.secondary) }

            }
        }.disabled(saving)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    Divider()
                    Button {
                        guard !saving else { return }
                        let preference = draft
                        saving = true
                        Task {
                            await notifications.setReminder(kind, preference: preference, store: store)
                            saving = false
                            if notifications.personal.values[kind.rawValue] == preference { dismiss() }
                        }
                    } label: {
                        Text(saving ? "جارٍ حفظ التذكير…" : "حفظ التذكير")
                            .frame(maxWidth: .infinity, minHeight: 48).contentShape(Rectangle())
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.gold).foregroundStyle(Theme.buttonInk)
                    .accessibilityIdentifier("reminder.save")
                    .disabled(saving || !draft.valid || notifications.requestingPermission || notifications.personalUnreadable)
                    .padding(.horizontal, 20).padding(.vertical, 10)
                }.background(Theme.background)
            }
            .noorScreenChrome().navigationTitle(kind.title).tint(Theme.gold)
            .onChange(of: draft.startMinute) { _, value in draft.endMinute = max(value, draft.endMinute) }
            .onChange(of: draft.intervalMinutes) { _, value in
                if kind == .salawat && value == 5 {
                    draft.startMinute = 0; draft.endMinute = 1439
                    draft.weekdays = Set(1...7); draft.quietEnabled = false
                }
            }
    }
    private func time(_ title: String, value: Binding<Int>, id: String) -> some View {
        DatePicker(title, selection: Binding(get: {
            Calendar.current.date(bySettingHour: value.wrappedValue / 60, minute: value.wrappedValue % 60,
                second: 0, of: Date()) ?? Date()
        }, set: { date in
            let fields = Calendar.current.dateComponents([.hour, .minute], from: date)
            value.wrappedValue = (fields.hour ?? 0) * 60 + (fields.minute ?? 0)
        }), displayedComponents: .hourAndMinute)
            .environment(\.locale, Locale(identifier: "en_GB"))
            .accessibilityIdentifier("reminder.\(id)")
    }
}
