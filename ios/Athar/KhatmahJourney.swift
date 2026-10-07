import Foundation
import Combine
import UserNotifications

struct KhatmahDay: Codable, Equatable, Identifiable {
    var date: Date
    var first: Int
    var last: Int
    var id: Date { date }
    var count: Int { last - first + 1 }
}
struct KhatmahSession: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var first: Int
    var last: Int
    var newlyCompleted: Int
}
struct KhatmahPlan: Codable, Identifiable {
    var id = UUID()
    var started: Date
    var firstPage: Int
    var weekdays: Set<Int>
    var dailyPages: Int?
    var deadline: Date?
    var timeZone: String
    var reminderMinutes: Int?
    var paused = false
    var completed: Set<Int> = []
    var days: [KhatmahDay]
    var sessions: [KhatmahSession] = []
    var finished: Date?
    var nextPage: Int { (firstPage...604).first { !completed.contains($0) } ?? 605 }
    var progress: Double { Double(completed.count) / Double(605 - firstPage) }
    var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: timeZone) ?? .current
        return result
    }
    var expectedFinish: Date? { finished ?? days.last?.date }
    func due(on now: Date) -> KhatmahDay? {
        guard !paused, finished == nil, nextPage <= 604 else { return nil }
        let endOfToday = calendar.startOfDay(for: now)
        guard let slot = days.last(where: { calendar.startOfDay(for: $0.date) <= endOfToday && $0.last >= nextPage }) else {
            guard let future = days.first(where: { $0.last >= nextPage }) else { return nil }
            return KhatmahDay(date: future.date, first: nextPage, last: future.last)
        }
        return KhatmahDay(date: slot.date, first: nextPage, last: slot.last)
    }
    func missedDay(on now: Date) -> Bool {
        guard !paused, finished == nil else { return false }
        let today = calendar.startOfDay(for: now)
        return days.contains { calendar.startOfDay(for: $0.date) < today && $0.last >= nextPage }
    }
    var valid: Bool {
        guard (1...604).contains(firstPage), !weekdays.isEmpty, weekdays.isSubset(of: Set(1...7)),
              TimeZone(identifier: timeZone) != nil, started.timeIntervalSince1970.isFinite,
              deadline.map({ $0.timeIntervalSince1970.isFinite }) ?? true,
              finished.map({ $0.timeIntervalSince1970.isFinite }) ?? true,
              reminderMinutes.map({ (0..<1440).contains($0) }) ?? true,
              dailyPages.map({ (1...604).contains($0) }) ?? true,
              (dailyPages == nil) != (deadline == nil), completed.isSubset(of: Set(firstPage...604)),
              completed == Set(firstPage..<nextPage), !days.isEmpty,
              (finished == nil) == (nextPage <= 604),
              sessions.allSatisfy({ $0.date.timeIntervalSince1970.isFinite && $0.first >= firstPage && $0.last <= 604 && $0.first <= $0.last && $0.newlyCompleted >= 0 && $0.newlyCompleted <= $0.last - $0.first + 1 }) else { return false }
        return (days.first?.first ?? 605) <= nextPage && zip(days, days.dropFirst()).allSatisfy { $0.date < $1.date && $0.last + 1 == $1.first }
            && days.allSatisfy { $0.date.timeIntervalSince1970.isFinite && $0.first >= firstPage && $0.last <= 604 && $0.first <= $0.last && weekdays.contains(calendar.component(.weekday, from: $0.date)) }
            && days.last?.last == 604
    }
}

struct KhatmahReminder: Equatable {
    let id: String
    let fire: Date
    let first: Int
    let last: Int
    var url: String { "nooralruh://reading/\(first)" }
}
enum KhatmahReminderPlan {
    static let prefix = "noor.khatmah."
    static func make(_ plan: KhatmahPlan, now: Date, otherPending: Int) -> [KhatmahReminder] {
        guard plan.valid, !plan.paused, plan.finished == nil, let minutes = plan.reminderMinutes else { return [] }
        let room = max(0, min(14, 60 - max(0, otherPending)))
        // Filter expired dates before taking the budget, so a missed week cannot
        // consume every available slot. Opening always resumes confirmed progress.
        return Array(plan.days.compactMap { day -> KhatmahReminder? in
            guard day.last >= plan.nextPage,
                  let fire = plan.calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day.date),
                  fire > now else { return nil }
            return KhatmahReminder(id: prefix + "\(plan.id).\(day.first)", fire: fire, first: plan.nextPage, last: day.last)
        }.prefix(room))
    }
}
enum KhatmahFailure: Error, LocalizedError {
    case invalid, noReadingDays, unavailable
    var errorDescription: String? {
        switch self {
        case .invalid: return "تحقق من البداية وأيام القراءة ومقدار الورد."
        case .noReadingDays: return "لا توجد أيام قراءة كافية قبل الموعد المختار. اختر موعدًا لاحقًا أو أيامًا إضافية."
        case .unavailable: return "تعذر حفظ الخطة. بقيت البيانات السابقة دون تغيير."
        }
    }
}
enum KhatmahCalculator {
    static func schedule(first: Int, from date: Date, weekdays: Set<Int>, daily: Int?, deadline: Date?, calendar: Calendar) throws -> [KhatmahDay] {
        guard (1...604).contains(first), !weekdays.isEmpty, weekdays.isSubset(of: Set(1...7)),
              (daily == nil) != (deadline == nil), daily.map({ (1...604).contains($0) }) ?? true else { throw KhatmahFailure.invalid }
        let remaining = 605 - first
        var dates: [Date] = []
        var cursor = calendar.startOfDay(for: date)
        let required = daily.map { (remaining + $0 - 1) / $0 }
        for _ in 0..<20000 {
            if let deadline, cursor > calendar.startOfDay(for: deadline) { break }
            if weekdays.contains(calendar.component(.weekday, from: cursor)) { dates.append(cursor) }
            if let required, dates.count >= required { break }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { throw KhatmahFailure.invalid }
            cursor = next
        }
        guard !dates.isEmpty, required.map({ dates.count == $0 }) ?? true else { throw KhatmahFailure.noReadingDays }
        dates = Array(dates.prefix(remaining))
        var page = first
        return dates.enumerated().map { index, day in
            let count = daily.map { min($0, 605 - page) } ?? (remaining / dates.count + (index < remaining % dates.count ? 1 : 0))
            let slot = KhatmahDay(date: day, first: page, last: page + count - 1)
            page += count
            return slot
        }
    }
    static func make(first: Int, date: Date, weekdays: Set<Int>, daily: Int?, deadline: Date?, reminder: Int?, calendar: Calendar = .current) throws -> KhatmahPlan {
        let slots = try schedule(first: first, from: date, weekdays: weekdays, daily: daily, deadline: deadline, calendar: calendar)
        let plan = KhatmahPlan(started: date, firstPage: first, weekdays: weekdays, dailyPages: daily, deadline: deadline, timeZone: calendar.timeZone.identifier, reminderMinutes: reminder, days: slots)
        guard plan.valid else { throw KhatmahFailure.invalid }
        return plan
    }
    static func revised(_ plan: KhatmahPlan, date: Date, weekdays: Set<Int>, daily: Int?, deadline: Date?, reminder: Int?) throws -> KhatmahPlan {
        guard plan.nextPage <= 604 else { throw KhatmahFailure.invalid }
        var result = plan
        result.weekdays = weekdays; result.dailyPages = daily; result.deadline = deadline; result.reminderMinutes = reminder
        result.days = try schedule(first: plan.nextPage, from: date, weekdays: weekdays, daily: daily, deadline: deadline, calendar: plan.calendar)
        guard result.valid else { throw KhatmahFailure.invalid }
        return result
    }
    static func confirm(_ plan: KhatmahPlan, first: Int, last: Int, date: Date) throws -> KhatmahPlan {
        guard !plan.paused, plan.finished == nil, first >= plan.firstPage, last <= 604, first <= last,
              first <= plan.nextPage else { throw KhatmahFailure.invalid }
        var result = plan
        let before = result.completed.count
        result.completed.formUnion(first...last)
        result.sessions.append(.init(date: date, first: first, last: last, newlyCompleted: result.completed.count - before))
        if result.nextPage == 605 { result.finished = date }
        guard result.valid else { throw KhatmahFailure.invalid }
        return result
    }
}

@MainActor final class KhatmahStore: ObservableObject {
    static let shared = KhatmahStore()
    struct Archive: Codable { var version = 1; var plans: [KhatmahPlan] = []; var activeID: UUID? }
    @Published private(set) var archive = Archive()
    @Published var error: String?
    @Published private(set) var notificationStatus = ""
    private let file: URL
    private var unreadable = false
    private var reminderTask: Task<Void, Never>?
    var active: KhatmahPlan? { archive.plans.first { $0.id == archive.activeID } }
    init(file: URL? = nil) {
        self.file = file ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("noor-khatmah-v1.json")
        if FileManager.default.fileExists(atPath: self.file.path) {
            do {
                let saved = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: self.file))
                guard saved.version == 1, saved.plans.allSatisfy(\.valid), Set(saved.plans.map(\.id)).count == saved.plans.count,
                      saved.activeID.map({ id in saved.plans.contains { $0.id == id } }) ?? true else { throw KhatmahFailure.invalid }
                archive = saved
            } catch { unreadable = true; self.error = "تعذر فتح سجل الختمة؛ لن نستبدله أو نحذف تقدمك. تواصل مع الدعم." }
        }
    }
    @discardableResult func adopt(_ plan: KhatmahPlan) -> Bool {
        guard plan.valid, active == nil || active?.finished != nil || active?.id == plan.id else { error = "عدّل الخطة الحالية للحفاظ على رحلة واحدة نشطة."; return false }
        var value = archive
        if let index = value.plans.firstIndex(where: { $0.id == plan.id }) { value.plans[index] = plan }
        else { value.plans.append(plan) }
        value.activeID = plan.id
        return persist(value)
    }
    @discardableResult func setPaused(_ paused: Bool) -> Bool {
        guard var plan = active, plan.finished == nil else { return false }
        plan.paused = paused
        return adopt(plan)
    }
    @discardableResult func confirm(first: Int, last: Int, date: Date = .now) -> Bool {
        do {
            guard let plan = active else { throw KhatmahFailure.invalid }
            return adopt(try KhatmahCalculator.confirm(plan, first: first, last: last, date: date))
        } catch { self.error = error.localizedDescription; return false }
    }
    private func persist(_ value: Archive) -> Bool {
        guard !unreadable else { error = "السجل يحتاج إصلاحًا؛ لم تتغير البيانات القديمة."; return false }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(value).write(to: file, options: .atomic)
            archive = value; error = nil
            Task { await refreshReminders() }
            return true
        } catch { self.error = KhatmahFailure.unavailable.localizedDescription; return false }
    }
    func enableReminderPermission() async {
        do { _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
        catch { notificationStatus = "تعذر طلب إذن التذكيرات." }
        await refreshReminders()
    }
    func refreshReminders() async {
        let previous = reminderTask
        let next = Task { @MainActor in
            if let previous { await previous.value }
            await self.scheduleReminders()
        }
        reminderTask = next
        await next.value
    }
    private func scheduleReminders() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("noor.khatmah.") }.map(\.identifier))
        let settings = await center.notificationSettings()
        guard let plan = active, !plan.paused, plan.finished == nil, let minutes = plan.reminderMinutes else { notificationStatus = "التذكير غير مفعّل"; return }
        guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else { notificationStatus = "التذكير يحتاج إذن الإشعارات من إعدادات الجهاز"; return }
        // Leave room for prayer/adhkar requests in iOS's shared 64-request budget.
        let reminders = KhatmahReminderPlan.make(plan, now: .now, otherPending: pending.filter { !$0.identifier.hasPrefix(KhatmahReminderPlan.prefix) }.count)
        for reminder in reminders {
            let content = UNMutableNotificationContent()
            content.title = "رحلة الختمة"
            content.body = "تابع رحلتك من الصفحة \(reminder.first). اقرأ في الوقت المناسب لك."
            content.sound = .default
            content.userInfo = ["url": reminder.url]
            var components = plan.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fire)
            components.timeZone = plan.calendar.timeZone
            do { try await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))) }
            catch { notificationStatus = "تعذرت جدولة التذكير؛ الخطة محفوظة."; return }
        }
        notificationStatus = reminders.isEmpty ? "لا توجد تذكيرات قادمة متاحة؛ راجع موعد الورد وإعدادات التذكير" : "التذكير مفعّل للأيام القادمة"
    }
}
