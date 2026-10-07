import Foundation
import BackgroundTasks

enum PrayerBackgroundRefresh {
    static let identifier = "com.saud1596x.nooralruh.prayer-refresh"
    // Opportunistic replenishment. iOS chooses execution time; never a midnight alarm.
    static func submit() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date().addingTimeInterval(6 * 60 * 60)
        do { try BGTaskScheduler.shared.submit(request) }
        catch { /* Foreground reconciliation and previously scheduled requests remain available. */ }
    }
}

extension DeviceData {
    var prayerScheduleKey: String {
        "\(city.id)|\(city.latitude)|\(city.longitude)|\(city.timeZone)|\(city.countryCode ?? "")|\(AutomaticPrayerProfile.version)"
    }
}
