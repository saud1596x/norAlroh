import Foundation

struct NoorReadingEvent: Identifiable {
    let planID: UUID
    let session: KhatmahSession
    var id: String { "\(planID):\(session.id)" }
}
struct NoorJourneyIndex {
    let events: [NoorReadingEvent]
    let calendar: Calendar
    init(archive: KhatmahStore.Archive, calendar: Calendar = .current) {
        self.calendar = calendar
        events = archive.plans.flatMap { plan in plan.sessions.map { NoorReadingEvent(planID: plan.id, session: $0) } }
            .sorted { $0.session.date == $1.session.date ? $0.id < $1.id : $0.session.date > $1.session.date }
    }
    var readingDays: Set<Date> { Set(events.map { calendar.startOfDay(for: $0.session.date) }) }
    var newlyCompletedPages: Int { events.reduce(0) { $0 + $1.session.newlyCompleted } }
    func events(on date: Date) -> [NoorReadingEvent] { events.filter { calendar.isDate($0.session.date, inSameDayAs: date) } }
    func days(in month: Date) -> [Date] {
        guard let interval = calendar.dateInterval(of: .month, for: month), let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        return range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: interval.start) }
    }
    func leadingDays(in month: Date) -> Int {
        guard let first = days(in: month).first else { return 0 }
        return (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
    }
}
