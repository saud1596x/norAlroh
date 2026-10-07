import Foundation

struct FridayPreferences: Codable, Equatable {
    var target = 100
    var mosqueMinutes = 13 * 60
    var ghuslMinutes = 9 * 60
    var earlyMinutes = 60
    var reminderMinutes = 120
    var wakeAdvance = 10
    var valid: Bool {
        (1...1_000_000).contains(target) && (0..<1440).contains(mosqueMinutes)
            && (0..<1440).contains(ghuslMinutes) && [30, 60, 90, 120].contains(earlyMinutes)
            && [60, 120, 180, 240].contains(reminderMinutes) && [0, 5, 10, 15, 30].contains(wakeAdvance)
    }
}
struct FridayDay: Codable, Equatable {
    var count = 0
    var completed: Set<String> = []
}
struct FridayEvent: Identifiable {
    let id: String
    let date: Date
    let title: String
    let body: String
    let prayer: Bool
}
enum FridayPlan {
    static let prefix = "noor.friday."
    static func calendar(for city: City) -> Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: city.timeZone) ?? .current; return c
    }
    static func active(at date: Date, city: City) -> Bool { calendar(for: city).component(.weekday, from: date) == 6 }
    static func dayKey(_ date: Date, city: City) -> String { MemorizationProgress.dayKey(date, calendar: calendar(for: city)) }
    static func events(data: DeviceData, preferences p: FridayPreferences, now: Date = Date()) -> [FridayEvent] {
        guard p.valid else { return [] }
        let c = calendar(for: data.city)
        // Only the upcoming Friday: prayer times change every week. Refresh on each app opening.
        guard let day = (0...7).compactMap({ c.date(byAdding: .day, value: $0, to: c.startOfDay(for: now)) }).first(where: {
            active(at: $0, city: data.city) && (c.date(byAdding: .day, value: 1, to: $0) ?? $0) > now
        }) else { return [] }
        let key = dayKey(day, city: data.city)
        func time(_ minutes: Int) -> Date? { c.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day) }
        var result: [FridayEvent] = []
        func append(_ suffix: String, _ date: Date?, _ title: String, _ body: String, prayer: Bool = false) {
            guard let date, date > now, active(at: date, city: data.city) else { return }
            result.append(.init(id: prefix + key + "." + suffix, date: date, title: title, body: body, prayer: prayer))
        }
        for row in PrayerCalculator.rows(data: data, date: day) where !row.sunrise {
            let fire = row.id == "fajr" ? row.date.addingTimeInterval(-Double(p.wakeAdvance * 60)) : row.date
            append(row.id, fire, row.id == "fajr" && p.wakeAdvance > 0 ? "استعد لصلاة الفجر" : "صلاة \(row.name)", "\(data.city.name) · مواقيت محسوبة حسب موقعك المحفوظ.", prayer: true)
        }
        append("ghusl", time(p.ghuslMinutes), "الاستعداد للجمعة", "تذكير بالغسل والاستعداد لصلاة الجمعة.")
        append("early", time(max(0, p.mosqueMinutes - p.earlyMinutes)), "وقت التبكير", "استعد للخروج للمسجد؛ الموعد الذي اخترته أنت، وليس وقتًا مؤكّدًا للخطبة.")
        for minutes in stride(from: 8 * 60, through: 20 * 60, by: p.reminderMinutes) {
            // Quiet period around the user's chosen mosque time, to avoid interrupting the khutbah.
            guard minutes < p.mosqueMinutes - 30 || minutes > p.mosqueMinutes + 90 else { continue }
            append("salawat.\(minutes)", time(minutes), "الصلاة على النبي ﷺ", "اللهم صل وسلم على نبينا محمد. أكمل هدفك الشخصي بهدوء.")
        }
        // Leave room for the 42 prayer and 7 salawat notifications under iOS's pending request budget.
        return Array(result.sorted { $0.date < $1.date }.prefix(14))
    }
}
