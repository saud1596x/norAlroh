import Foundation
import AVFoundation
import UserNotifications

enum PrayerAlertSound {
    static let filename = "prayer-adhan.caf"
    static func isValid(in bundle: Bundle = .main) -> Bool {
        guard let url = bundle.url(forResource: "prayer-adhan", withExtension: "caf"),
              let file = try? AVAudioFile(forReading: url), file.processingFormat.sampleRate > 0 else { return false }
        let duration = Double(file.length) / file.processingFormat.sampleRate
        return duration > 0 && duration < 30
    }
    static func sound(preferences: PrayerNotificationPreferences) -> UNNotificationSound? {
        guard preferences.soundEnabled else { return nil }
        guard (preferences.soundStyle ?? "system") == "adhan", isValid() else { return .default }
        return UNNotificationSound(named: UNNotificationSoundName(rawValue: filename))
    }
}
