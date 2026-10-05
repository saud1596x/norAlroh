import Foundation

struct PrayerNotificationPreferences: Codable, Equatable {
    var prayers: [String: Bool] = ["fajr": true, "dhuhr": true, "asr": true, "maghrib": true, "isha": true]
    var advanceMinutes: Int = 0
    var soundEnabled: Bool = true
}

struct PlannedPrayerNotification: Identifiable {
    let id: String
    let prayer: PrayerRow
    let fireDate: Date
    let cityName: String
    let advanceMinutes: Int
    let soundEnabled: Bool

    var title: String {
        advanceMinutes == 0 ? "حان وقت صلاة \(prayer.name)" : "\(prayer.name) بعد \(advanceMinutes) دقائق"
    }
}

enum PrayerNotificationPlan {
    static let prefix = "noor.prayer."
    static let horizonDays = 10
    static let maximumRequests = 50

    static func make(data: DeviceData, preferences: PrayerNotificationPreferences, now: Date = Date()) -> [PlannedPrayerNotification] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: data.city.timeZone) ?? .current
        let advance = [0, 5, 10, 15].contains(preferences.advanceMinutes) ? preferences.advanceMinutes : 0
        var result: [PlannedPrayerNotification] = []
        for offset in 0..<horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            for row in PrayerCalculator.rows(data: data, date: day) where !row.sunrise && preferences.prayers[row.id] == true {
                let fire = row.date.addingTimeInterval(-Double(advance * 60))
                guard fire > now else { continue }
                let components = calendar.dateComponents([.year, .month, .day], from: row.date)
                let dayID = "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
                result.append(.init(id: prefix + dayID + "." + row.id, prayer: row, fireDate: fire,
                                    cityName: data.city.name, advanceMinutes: advance, soundEnabled: preferences.soundEnabled))
            }
        }
        return Array(result.sorted { $0.fireDate < $1.fireDate }.prefix(maximumRequests))
    }
}
