import SwiftUI
import UIKit

struct PrayerNotificationSettings: View {
    @EnvironmentObject var store: AtharStore
    @EnvironmentObject var notifications: PrayerNotifications
    private let rows = [("fajr", "الفجر"), ("dhuhr", "الظهر"), ("asr", "العصر"), ("maghrib", "المغرب"), ("isha", "العشاء")]

    var body: some View {
        Form {
            Section {
                Toggle("تنبيهات الصلاة", isOn: Binding(get: { notifications.enabled }, set: { enabled in
                    if enabled { Task { await notifications.enable(store: store) } }
                    else { notifications.disable() }
                })).disabled(notifications.requestingPermission)
                if let message = notifications.message {
                    Text(message).font(.subheadline).foregroundStyle(.secondary)
                    Button("إعدادات iPhone") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
            } footer: {
                Text("نجدول مواقيت الأيام العشرة القادمة ونجدّدها عند فتح التطبيق. صوت التنبيه هو صوت النظام.")
            }
            Section("الصلوات") {
                ForEach(rows, id: \.0) { id, name in
                    Toggle(name, isOn: Binding(get: { notifications.preferences.prayers[id] == true }, set: { value in
                        Task { await notifications.setPrayer(id, enabled: value, store: store) }
                    }))
                }
            }
            Section("طريقة التنبيه") {
                Picker("وقت التنبيه", selection: Binding(get: { notifications.preferences.advanceMinutes }, set: { value in
                    Task { await notifications.setAdvance(value, store: store) }
                })) {
                    Text("عند دخول الوقت").tag(0)
                    Text("قبل الصلاة بـ٥ دقائق").tag(5)
                    Text("قبل الصلاة بـ١٠ دقائق").tag(10)
                    Text("قبل الصلاة بـ١٥ دقيقة").tag(15)
                }
                Toggle("صوت النظام", isOn: Binding(get: { notifications.preferences.soundEnabled }, set: { value in
                    Task { await notifications.setSound(value, store: store) }
                }))
            }
            Section("المدينة") {
                Label(store.data.city.name, systemImage: "mappin.and.ellipse")
                if notifications.enabled { Text("\(notifications.scheduledCount) تنبيه مجدول").foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("تنبيهات الصلاة")
        .tint(Theme.gold)
    }
}
