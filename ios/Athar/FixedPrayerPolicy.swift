import Foundation
import UserNotifications

struct FixedPrayerEvent: Identifiable {
    enum Kind: String { case prayer, witr, duha }
    let id: String
    let kind: Kind
    let prayerID: String?
    let prayerName: String
    let fireDate: Date
    let title: String
    let body: String
    var destination: String { kind == .prayer ? "prayers" : "dhikr" }
}

/// Owner policy v2, independent of archived custom schedules. These are app
/// budgets, not claims about undocumented operating-system capacity guarantees.
enum FixedPrayerPolicy {
    static let version = 2
    static let prefix = "noor.fixedPrayer.v2."
    static let salawatID = prefix + "salawat.every-five-minutes"
    static let horizonDays = 3
    static let prayerBudget = 15
    static let notificationBudget = 24 // Includes legacy-OS prayer fallback.
    static let historyRetentionDays = 64

    static func historyFloor(previous: Date?, now: Date) -> Date {
        let candidate = now.addingTimeInterval(-Double(historyRetentionDays * 24 * 60 * 60))
        return max(previous ?? candidate, candidate)
    }
    static func retainAlarmHistory(_ records: [String: PrayerAlarmRecord], floor: Date,
                                   activeIDs: Set<UUID>) -> [String: PrayerAlarmRecord] {
        records.filter { key, record in
            // Preserve every live/uncertain cancellation identity and every
            // future or pending record, including a future removed tombstone.
            // The civil-day ID can be recalculated west of its original city.
            // Retain that identity through its conservative UTC day boundary.
            let expiry = max(record.fireDate, conservativeEventHistoryDate(key) ?? record.fireDate)
            return activeIDs.contains(record.id) || expiry >= floor ||
                ![PrayerAlarmRecord.State.observedRemoved, .cancelled, .expired].contains(record.state)
        }
    }
    static func conservativeEventHistoryDate(_ id: String) -> Date? {
        let pattern = #"^noor\.fixedPrayer\.v2\.c[0-9]+\.([0-9]{4})-([0-9]{1,2})-([0-9]{1,2})\."#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: id, range: NSRange(id.startIndex..., in: id)) else { return nil }
        let values = (1...3).compactMap { part -> Int? in
            guard let range = Range(match.range(at: part), in: id) else { return nil }
            return Int(id[range])
        }
        guard values.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let day = calendar.date(from: DateComponents(year: values[0], month: values[1], day: values[2])),
              calendar.component(.year, from: day) == values[0], calendar.component(.month, from: day) == values[1],
              calendar.component(.day, from: day) == values[2] else { return nil }
        // Local-night IDs can cross midnight and a time-zone boundary. Retain
        // up to two extra UTC days rather than expire a recent event early.
        return day.addingTimeInterval(2 * 24 * 60 * 60)
    }

    static func duhaDate(sunrise: Date, dhuhr: Date) -> Date? {
        let start = sunrise.addingTimeInterval(30 * 60)
        let end = dhuhr.addingTimeInterval(-30 * 60)
        guard start < end else { return nil }
        return start.addingTimeInterval(end.timeIntervalSince(start) / 2)
    }
    static func witrDate(isha: Date, nextFajr: Date) -> Date? {
        // Operational margins, not a general religious definition in minutes.
        let start = isha.addingTimeInterval(5 * 60)
        let end = nextFajr.addingTimeInterval(-15 * 60)
        guard start < end else { return nil }
        let preferred = isha.addingTimeInterval(60 * 60)
        return preferred > start && preferred < end ? preferred :
            start.addingTimeInterval(end.timeIntervalSince(start) / 2)
    }
    static func make(data: DeviceData, now: Date) -> [FixedPrayerEvent] {
        guard let zone = TimeZone(identifier: data.city.timeZone),
              data.city.latitude.isFinite, data.city.longitude.isFinite,
              (-90...90).contains(data.city.latitude), (-180...180).contains(data.city.longitude) else { return [] }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let today = calendar.startOfDay(for: now)
        var result: [FixedPrayerEvent] = []
        for offset in -1..<horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let tomorrow = calendar.date(byAdding: .day, value: 1, to: day) else { continue }
            let rows = PrayerCalculator.rows(data: data, date: day)
            let prayerIDs = ["fajr", "dhuhr", "asr", "maghrib", "isha"]
            let dailyPrayers = rows.filter { prayerIDs.contains($0.id) && !$0.sunrise }
            // Do not advertise coverage beyond a day whose five times could
            // not be calculated. No guessed dates or offsets fill that gap.
            if offset >= 0 && (dailyPrayers.count != 5 || Set(dailyPrayers.map(\.id)).count != 5 ||
                !zip(dailyPrayers, dailyPrayers.dropFirst()).allSatisfy({ pair in pair.0.date < pair.1.date })) { break }
            let parts = calendar.dateComponents([.year, .month, .day], from: day)
            let dayID = "c\(AutomaticPrayerProfile.version).\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
            if offset >= 0 {
                for row in dailyPrayers {
                    guard row.date > now else { continue }
                    result.append(.init(id: prefix + dayID + "." + row.id, kind: .prayer,
                        prayerID: row.id, prayerName: row.name, fireDate: row.date,
                        title: "حان وقت صلاة \(row.name)", body: "حيّ على الصلاة"))
                }
                if let sunrise = rows.first(where: { $0.id == "sunrise" })?.date,
                   let noon = rows.first(where: { $0.id == "dhuhr" })?.date,
                   let date = duhaDate(sunrise: sunrise, dhuhr: noon), date > now {
                    result.append(.init(id: prefix + dayID + ".duha", kind: .duha, prayerID: nil,
                        prayerName: "", fireDate: date, title: "تذكير صلاة الضحى", body: "وقت هادئ لصلاة الضحى إن تيسّر لك."))
                }
            }
            if let isha = rows.first(where: { $0.id == "isha" })?.date,
               let fajr = PrayerCalculator.rows(data: data, date: tomorrow).first(where: { $0.id == "fajr" })?.date,
               let date = witrDate(isha: isha, nextFajr: fajr), date > now {
                result.append(.init(id: prefix + dayID + ".witr", kind: .witr, prayerID: nil,
                    prayerName: "", fireDate: date, title: "تذكير الوتر", body: "بعد أداء العشاء، تذكّر الوتر إن لم تصلّه."))
            }
        }
        return result.sorted { $0.fireDate < $1.fireDate }
    }
    static func salawatRequest() -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "الصلاة على النبي ﷺ"
        content.body = "اللهم صلِّ وسلِّم على نبينا محمد"
        content.sound = nil; content.badge = nil
        content.threadIdentifier = "noor.fixed.salawat"
        content.userInfo = ["destination": "salawat", "policyVersion": version]
        return .init(identifier: salawatID, content: content,
                     trigger: UNTimeIntervalNotificationTrigger(timeInterval: 300, repeats: true))
    }
    static func notification(_ event: FixedPrayerEvent, timeZone: TimeZone) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = event.title; content.body = event.body
        content.sound = event.kind == .prayer ? PrayerAlertSound.sound(preferences: .init()) : nil
        content.badge = nil; content.threadIdentifier = "noor.fixed." + event.kind.rawValue
        content.userInfo = ["destination": event.destination, "policyVersion": version]
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: event.fireDate)
        components.calendar = calendar; components.timeZone = timeZone
        return .init(identifier: event.id, content: content,
                     trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
    }
    static func isLegacyID(_ id: String) -> Bool {
        if id.hasPrefix(PrayerNotificationPlan.prefix) || id.hasPrefix(SalawatNotificationPlan.prefix)
            || id.hasPrefix("noor.friday.") || id.hasPrefix(KhatmahReminderPlan.prefix) { return true }
        if NoorReminderKind.allCases.contains(where: { id.hasPrefix(NoorPersonalReminderPlan.prefix + $0.rawValue + ".") }) { return true }
        return id.range(of: #"^athar\.[0-9]+\.(fajr|dhuhr|asr|maghrib|isha)$"#, options: .regularExpression) != nil
    }
    static func owns(_ id: String) -> Bool { id.hasPrefix(prefix) || isLegacyID(id) }
}
