import Foundation

struct NoorSalawatCounts: Codable, Equatable {
    var days: [String: Int] = [:]
    var goal: Int? = nil
    var valid: Bool { days.values.allSatisfy { $0 >= 0 } && (goal.map { $0 > 0 } ?? true) }
    static func dayKey(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
    func count(at date: Date, timeZone: TimeZone = .current) -> Int {
        days[Self.dayKey(date, timeZone: timeZone)] ?? 0
    }
}

struct NoorKhatmahWidgetState: Codable {
    struct Day: Codable { let date: Date; let first: Int; let last: Int }
    let firstPage: Int
    let nextPage: Int
    let completed: Int
    let paused: Bool
    let timeZone: String
    let days: [Day]
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: timeZone) ?? .current
        return c
    }
    var valid: Bool {
        (1...604).contains(firstPage) && (firstPage...605).contains(nextPage)
            && completed == nextPage - firstPage && TimeZone(identifier: timeZone) != nil
            && !days.isEmpty && days.last?.last == 604 && (days.first?.first ?? 606) <= nextPage
            && days.allSatisfy { $0.date.timeIntervalSince1970.isFinite && $0.first >= firstPage && $0.last <= 604 && $0.first <= $0.last }
            && zip(days, days.dropFirst()).allSatisfy { $0.date < $1.date && $0.last + 1 == $1.first }
    }
    func ward(at date: Date) -> Day? {
        guard !paused, nextPage <= 604 else { return nil }
        let today = calendar.startOfDay(for: date)
        let slot = days.last { calendar.startOfDay(for: $0.date) <= today && $0.last >= nextPage }
            ?? days.first { $0.last >= nextPage }
        return slot.map { Day(date: $0.date, first: nextPage, last: $0.last) }
    }
    func wardTitle(at date: Date) -> String {
        guard let ward = ward(at: date) else { return paused ? "الرحلة متوقفة مؤقتًا" : "اكتملت الختمة" }
        let scheduled = calendar.startOfDay(for: ward.date), today = calendar.startOfDay(for: date)
        return scheduled > today ? "الورد القادم" : scheduled < today ? "ورد متبقٍ" : "ورد اليوم"
    }
}

struct NoorWidgetSnapshot: Codable {
    let version: Int
    let updated: Date
    let prayer: PrayerInputs
    let page: Int
    let dailyTarget: Int
    let practiced: [String: Int]
    let reviewDates: [Date]
    let dua: String
    let duaTitle: String
    var khatmah: NoorKhatmahWidgetState? = nil
    var salawat: NoorSalawatCounts? = nil
    var salawatTimeZone: String? = nil
    static let group = "group.com.saud1596x.nooralruh"
    static func file() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.appendingPathComponent("noor-widget-v1.json")
    }
    static func load() -> Self? {
        guard let file = file(), let bytes = try? Data(contentsOf: file), bytes.count < 2_000_000,
              let value = try? JSONDecoder().decode(Self.self, from: bytes), value.version == 1,
              (1...604).contains(value.page), (0...50).contains(value.dailyTarget),
              value.khatmah?.valid ?? true, value.salawat?.valid ?? true,
              value.salawatTimeZone.map({ TimeZone(identifier: $0) != nil }) ?? true,
              TimeZone(identifier: value.prayer.city.timeZone) != nil,
              (-90...90).contains(value.prayer.city.latitude), (-180...180).contains(value.prayer.city.longitude) else { return nil }
        return value
    }
    func completed(at date: Date) -> Int {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return practiced["\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"] ?? 0
    }
    func due(at date: Date) -> Int { reviewDates.filter { $0 <= Calendar.current.startOfDay(for: date) }.count }
}
