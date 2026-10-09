import Foundation

enum NoorReminderKind: String, CaseIterable, Codable, Identifiable {
    case dua, morning, evening, salawat, hifz
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dua: "الدعاء"
        case .morning: "أذكار الصباح"
        case .evening: "أذكار المساء"
        case .salawat: "الصلاة على النبي ﷺ"
        case .hifz: "الحفظ والمراجعة"
        }
    }
    var destination: String { self == .hifz ? "review" : rawValue }
    var defaultMinute: Int {
        switch self { case .morning: 420; case .evening: 1080; case .hifz: 1200; default: 540 }
    }
}

struct NoorReminderPreference: Codable, Equatable {
    var enabled = false
    var startMinute: Int
    var endMinute: Int
    // Zero means once daily at startMinute. A repeated window never crosses midnight.
    var intervalMinutes = 0
    var weekdays = Set(1...7)
    var quietEnabled = false
    var quietStart = 1320
    var quietEnd = 360
    init(kind: NoorReminderKind) { startMinute = kind.defaultMinute; endMinute = kind.defaultMinute }
    var valid: Bool {
        (0..<1440).contains(startMinute) && (startMinute..<1440).contains(endMinute)
        && [0, 120, 240, 360, 720].contains(intervalMinutes)
        && !weekdays.isEmpty && weekdays.isSubset(of: Set(1...7))
        && (0..<1440).contains(quietStart) && (0..<1440).contains(quietEnd)
    }
    func quiet(at minute: Int) -> Bool {
        guard quietEnabled else { return false }
        if quietStart == quietEnd { return true }
        return quietStart < quietEnd ? (quietStart..<quietEnd).contains(minute)
            : minute >= quietStart || minute < quietEnd
    }
    var minutes: [Int] {
        guard valid else { return [] }
        let slots = intervalMinutes == 0 ? [startMinute] : Array(stride(from: startMinute, through: endMinute, by: intervalMinutes))
        return slots.filter { !quiet(at: $0) }
    }
}

struct NoorReminderArchive: Codable {
    var version = 1
    var values: [String: NoorReminderPreference] = [:]
    var valid: Bool {
        version == 1 && values.allSatisfy { NoorReminderKind(rawValue: $0.key) != nil && $0.value.valid }
    }
}

enum NoorPersonalReminderPlan {
    static let prefix = "noor.personal."
    struct Event { let id: String; let kind: NoorReminderKind; let date: Date }
    static func make(_ archive: NoorReminderArchive, now: Date, timeZone: TimeZone = .current) -> [Event] {
        guard archive.valid, now.timeIntervalSince1970.isFinite else { return [] }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: now)
        var events: [Event] = []
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            let components = calendar.dateComponents([.year, .month, .day], from: day)
            let dayID = String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
            for kind in NoorReminderKind.allCases {
                guard let preference = archive.values[kind.rawValue], preference.enabled,
                      preference.weekdays.contains(weekday) else { continue }
                for minute in preference.minutes {
                    // Foundation resolves a missing DST time forward and chooses the first
                    // repeated time; each authored daily slot appears at most once.
                    guard let date = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0,
                        of: day, matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward),
                        calendar.isDate(date, inSameDayAs: day), date > now,
                        !preference.quiet(at: calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)) else { continue }
                    events.append(.init(id: "\(prefix)\(kind.rawValue).\(dayID).\(minute)", kind: kind, date: date))
                }
            }
        }
        return events.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
    }
}
