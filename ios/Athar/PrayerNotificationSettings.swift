import SwiftUI
import UIKit

/// Explain the fixed policy before requesting either independent system permission.
struct PrayerNotificationSettings: View {
    @EnvironmentObject private var store: AtharStore
    @EnvironmentObject private var notifications: PrayerNotifications
    @State private var choosingCity = false

    var body: some View {
        Form {
            Section("تنبيهاتك باختصار") {
                Label("الصلوات الخمس عند دخول وقتها، بصوت التنبيه", systemImage: "alarm")
                    .accessibilityIdentifier("notifications.policy.prayers")
                Label("الصلاة على النبي ﷺ كل خمس دقائق، برسالة صامتة طوال اليوم والليل", systemImage: "text.bubble")
                    .accessibilityIdentifier("notifications.policy.salawat")
                Text("❀ اللهم صلِّ على نبينا محمد ﷺ ❀")
                Label("تذكير صامت واحد للضحى، وآخر للوتر بعد أداء العشاء", systemImage: "moon.stars")
                    .accessibilityIdentifier("notifications.policy.quiet")
                Text(notifications.usesAlarmKit
                     ? "سيطلب iPhone إذن منبهات الصلاة وإذن الإشعارات النصية بصورة مستقلة. يمكنك رفض أي منهما ومواصلة القراءة."
                     : "يستخدم إصدار iOS الحالي إشعارات الصلاة العادية؛ ظهورها وصوتها يخضعان للصامت والتركيز وإعدادات iPhone. يمكنك رفضها ومواصلة القراءة.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if !notifications.policyRequested || needsPermission {
                    Button {
                        Task { await notifications.enable(store: store) }
                    } label: {
                        Text(notifications.requestingPermission ? "جارٍ طلب الإذن…" : "متابعة إلى أذونات iPhone")
                            .frame(minHeight: 44)
                    }
                    .disabled(notifications.requestingPermission)
                    .accessibilityIdentifier("notifications.permissions")
                }
            }
            Section {
                status(notifications.usesAlarmKit ? "منبهات الصلاة" : "إشعارات الصلاة", notifications.prayerAuthorization)
                    .accessibilityIdentifier("notifications.status.prayers")
                status("الرسائل الصامتة", notifications.notificationAuthorization)
                    .accessibilityIdentifier("notifications.status.messages")
                Button("فتح إعدادات iPhone") { openSettings() }.frame(minHeight: 44)
                    .accessibilityIdentifier("notifications.systemSettings")
            } header: { Text("حالة الأذونات") } footer: {
                Text("عند رفض إذن، لا نكرر طلبه. يمكنك تغييره من إعدادات iPhone؛ الإذنان مستقلان على الأنظمة التي تدعم المنبهات.")
            }
            Section("مكان مواقيت الصلاة") {
                if notifications.locationIsTrusted {
                    Label(store.data.city.name, systemImage: "location.fill")
                } else {
                    Text("اختر مكانك أولًا. لا نستخدم مدينة افتراضية لعرض المواقيت أو جدولة الصلاة.")
                        .foregroundStyle(.secondary)
                }
                Button("اختيار المدينة") { choosingCity = true }.frame(minHeight: 44)
                    .accessibilityIdentifier("notifications.city")
            }
            Section("التغطية الحالية") {
                coverage("منبهات الصلاة حتى", date: notifications.prayerCoverageThrough)
                coverage("تذكيرات الوتر والضحى حتى", date: notifications.reminderCoverageThrough)
                Text("نجدّد المواعيد عند فتح التطبيق وتغيّر المكان والوقت. افتح التطبيق دوريًا؛ التحديث في الخلفية والسفر أثناء الإغلاق لا يضمنان تجديدًا فوريًا.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if let message = notifications.message {
                    Text(message).font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityIdentifier("notifications.message")
                }
            }
        }
        .noorScreenChrome().navigationTitle("التنبيهات")
        .tint(Theme.gold)
        .sheet(isPresented: $choosingCity) { NavigationStack { SaudiCityPicker() } }
        .task { await notifications.refresh(store: store) }
    }

    private var needsPermission: Bool {
        notifications.notificationAuthorization == .notDetermined ||
            (notifications.usesAlarmKit && notifications.prayerAuthorization == .notDetermined)
    }
    private func status(_ title: String, _ value: PrayerAuthorizationState) -> some View {
        LabeledContent(title) { Text(statusText(value)) }
    }
    private func statusText(_ value: PrayerAuthorizationState) -> String {
        switch value {
        case .notDetermined: return "لم يُطلب بعد"
        case .authorized: return "مسموح"
        case .denied: return "غير مسموح"
        case .unavailable: return "غير متاح"
        }
    }
    private func coverage(_ title: String, date: Date?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline)
            if let date {
                let city = PrayerCalculator.location(store.data.city)
                Text(PrayerDisplay.gregorian(date, city: city) + " · " + PrayerDisplay.isolatedClock(date, city: city))
                    .font(.subheadline.monospacedDigit())
            } else { Text("لا توجد تغطية مؤكدة بعد").foregroundStyle(.secondary) }
        }
    }
    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}
