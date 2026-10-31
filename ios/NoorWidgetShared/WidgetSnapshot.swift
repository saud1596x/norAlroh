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
    var planID: UUID? = nil
    var dailyPages: Int? = nil
    var completedByDay: [String: Int]? = nil
    var stoppedPage: Int? = nil
    var finished: Bool? = nil
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: timeZone) ?? .current
        return c
    }
    var valid: Bool {
        (1...604).contains(firstPage) && (firstPage...605).contains(nextPage)
            && completed == nextPage - firstPage && TimeZone(identifier: timeZone) != nil
            && (dailyPages.map({ (1...604).contains($0) }) ?? true)
            && (completedByDay.map({ $0.count <= 8 && $0.values.allSatisfy { (0...604).contains($0) } }) ?? true)
            && (stoppedPage.map({ (firstPage...604).contains($0) }) ?? true)
            && (finished.map({ $0 == (nextPage == 605) }) ?? true)
            && !days.isEmpty && days.last?.last == 604 && (days.first?.first ?? 606) <= nextPage
            && days.allSatisfy { $0.date.timeIntervalSince1970.isFinite && $0.first >= firstPage && $0.last <= 604 && $0.first <= $0.last }
            && zip(days, days.dropFirst()).allSatisfy { $0.date < $1.date && $0.last + 1 == $1.first }
    }
    func target(at date: Date) -> Int? {
        let today = calendar.startOfDay(for: date)
        let slot = days.last { calendar.startOfDay(for: $0.date) <= today } ?? days.first
        return dailyPages ?? slot.map { $0.last - $0.first + 1 }
    }
    func completedToday(at date: Date) -> Int? {
        guard let completedByDay else { return nil }
        return completedByDay[NoorSalawatCounts.dayKey(date, timeZone: calendar.timeZone)] ?? 0
    }
    func ward(at date: Date) -> Day? {
        guard !paused, finished != true, nextPage <= 604,
              let target = target(at: date), let completedToday = completedToday(at: date) else { return nil }
        let remaining = max(0, target - completedToday)
        guard remaining > 0 else { return nil }
        let today = calendar.startOfDay(for: date)
        return Day(date: today, first: nextPage, last: min(604, nextPage + remaining - 1))
    }
    func resumePage(at date: Date) -> Int? {
        guard let ward = ward(at: date) else { return nil }
        return stoppedPage.flatMap { (ward.first...ward.last).contains($0) ? $0 : nil } ?? ward.first
    }
    func wardURL(at date: Date) -> URL? {
        guard let planID, let page = resumePage(at: date) else { return nil }
        return NoorWidgetLink.ward(id: "khatmah:\(planID.uuidString)", page: page)
    }
    func wardTitle(at date: Date) -> String {
        if paused { return "الرحلة متوقفة مؤقتًا" }
        if nextPage == 605 || finished == true { return "اكتملت الختمة" }
        guard completedByDay != nil else { return "افتح التطبيق لتحديث الورد" }
        return ward(at: date) == nil ? "أتممت ورد اليوم" : "ورد اليوم"
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
    var hasReadingPosition: Bool? = nil
    var readingChapterName: String? = nil
    var wardID: String? = nil
    var wardPage: Int? = nil
    var duaCatalogVersion: Int? = nil
    var prayerTrusted: Bool? = nil
    var canDisplayPrayerTimes: Bool { prayerTrusted == true }
    static let group = "group.com.saud1596x.nooralruh"
    static func file() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.appendingPathComponent("noor-widget-v1.json")
    }
    static func load() -> Self? {
        guard let file = file(), let bytes = try? Data(contentsOf: file) else { return nil }
        return decode(bytes)
    }
    static func decode(_ bytes: Data) -> Self? {
        guard bytes.count < 256_000,
              let value = try? JSONDecoder().decode(Self.self, from: bytes), [1, 2].contains(value.version),
              value.updated.timeIntervalSince1970.isFinite,
              (1...604).contains(value.page), (0...50).contains(value.dailyTarget),
              value.practiced.count <= 370, value.practiced.values.allSatisfy({ $0 >= 0 }),
              value.reviewDates.count <= 10_000, value.reviewDates.allSatisfy({ $0.timeIntervalSince1970.isFinite }),
              value.wardID.map(NoorWidgetLink.validWardID) ?? true,
              value.wardPage.map({ (1...604).contains($0) }) ?? true,
              value.khatmah?.valid ?? true, value.salawat?.valid ?? true,
              value.salawatTimeZone.map({ TimeZone(identifier: $0) != nil }) ?? true,
              TimeZone(identifier: value.prayer.city.timeZone) != nil,
              (-90...90).contains(value.prayer.city.latitude), (-180...180).contains(value.prayer.city.longitude) else { return nil }
        return value
    }
    func write(to file: URL) throws {
        let bytes = try JSONEncoder().encode(self)
        guard Self.decode(bytes) != nil else { throw CocoaError(.coderInvalidValue) }
        try bytes.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    // Only displayed values participate. Opening the app changes `updated`,
    // which is deliberately not a reason to spend WidgetKit's reload budget.
    func changedKinds(from previous: Self?) -> Set<String> {
        guard let previous else { return Set(["nextPrayer", "prayerDay", "reading", "ward", "review", "khatmah", "salawat", "dua", "shortDhikr"].map { "noor." + $0 }) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        func differs<T: Encodable>(_ a: T, _ b: T) -> Bool { (try? encoder.encode(a)) != (try? encoder.encode(b)) }
        var result = Set<String>()
        if duaCatalogVersion != previous.duaCatalogVersion || salawatTimeZone != previous.salawatTimeZone { result.formUnion(["noor.dua", "noor.shortDhikr"]) }
        if differs(prayer, previous.prayer) || prayerTrusted != previous.prayerTrusted { result.formUnion(["noor.nextPrayer", "noor.prayerDay"]) }
        if page != previous.page || hasReadingPosition != previous.hasReadingPosition || readingChapterName != previous.readingChapterName { result.insert("noor.reading") }
        if dailyTarget != previous.dailyTarget || practiced != previous.practiced || wardID != previous.wardID || wardPage != previous.wardPage { result.insert("noor.ward") }
        if reviewDates != previous.reviewDates { result.insert("noor.review") }
        if differs(khatmah, previous.khatmah) { result.formUnion(["noor.khatmah", "noor.ward"]) }
        if salawat != previous.salawat || salawatTimeZone != previous.salawatTimeZone { result.insert("noor.salawat") }
        return result
    }
    func completed(at date: Date) -> Int {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return practiced["\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"] ?? 0
    }
    func due(at date: Date) -> Int { reviewDates.filter { $0 <= Calendar.current.startOfDay(for: date) }.count }
}
