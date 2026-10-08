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
                Text("تنبيهات محلية للأيام القادمة تعمل بعد إغلاق التطبيق. نجددها عند الفتح وتغير الموقع، وعند السماح بالتحديث في الخلفية. افتح التطبيق دوريًا لتجديدها.")
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
                    Text("قبل الصلاة بـ5 دقائق").tag(5)
                    Text("قبل الصلاة بـ10 دقائق").tag(10)
                    Text("قبل الصلاة بـ15 دقيقة").tag(15)
                }
                Picker("صوت تنبيه الصلاة", selection: Binding(get: {
                    notifications.preferences.soundEnabled ? notifications.preferences.soundStyle ?? "system" : "silent"
                }, set: { value in Task { await notifications.setSoundStyle(value, store: store) } })) {
                    Text("أذان قصير").tag("adhan")
                    Text("صوت النظام").tag("system")
                    Text("بدون صوت").tag("silent")
                }
                Text("مقطع الأذان 24 ثانية. إذا تعذر تشغيله نستخدم صوت النظام. الصوت يخضع لإعدادات الصامت والتركيز في iPhone.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("الصلاة على النبي ﷺ") {
                Toggle("تذكير هادئ", isOn: Binding(get: { notifications.salawat.enabled }, set: { value in
                    Task { await notifications.setSalawatEnabled(value, store: store) }
                })).disabled(notifications.requestingPermission)
                Picker("التكرار", selection: Binding(get: { notifications.salawat.intervalHours }, set: { value in
                    Task { await notifications.setSalawatInterval(value, store: store) }
                })) {
                    Text("كل ساعتين").tag(2)
                    Text("كل 4 ساعات").tag(4)
                    Text("كل 6 ساعات").tag(6)
                    Text("مرة يوميًا").tag(12)
                }
                Text("تذكيرات صامتة بين 09:00 و21:00، بحد أقصى 7 يوميًا. لا نكرر تذكيرات الجمعة عند تفعيل هذا الخيار.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("الموقع المحفوظ") {
                Label(store.data.city.name, systemImage: "mappin.and.ellipse")
                if notifications.enabled { Text("\(notifications.scheduledCount) تنبيه مجدول").foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("تنبيهات الصلاة")
        .tint(Theme.gold)
    }
}
