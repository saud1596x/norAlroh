import SwiftUI
import WidgetKit

struct NoorEntry: TimelineEntry {
    let date: Date
    let snapshot: NoorWidgetSnapshot?
}
struct NoorProvider: TimelineProvider {
    func placeholder(in context: Context) -> NoorEntry { .init(date: Date(), snapshot: nil) }
    func getSnapshot(in context: Context, completion: @escaping (NoorEntry) -> Void) {
        completion(.init(date: Date(), snapshot: NoorWidgetSnapshot.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<NoorEntry>) -> Void) {
        let now = Date(), snapshot = NoorWidgetSnapshot.load()
        var dates = [now]
        if let snapshot {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: snapshot.prayer.city.timeZone) ?? .current
            for offset in 0...2 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
                dates += PrayerCalculator.rows(data: snapshot.prayer, date: day).map(\.date).filter { $0 > now }
                let midnight = calendar.startOfDay(for: day)
                if midnight > now { dates.append(midnight) }
            }
            // Memorization day uses the device calendar, independently of city time.
            if let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) { dates.append(midnight) }
            for zone in [snapshot.khatmah?.timeZone, snapshot.salawatTimeZone].compactMap({ $0 }) {
                var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: zone) ?? .current
                for offset in 1...2 {
                    if let midnight = c.date(byAdding: .day, value: offset, to: c.startOfDay(for: now)) { dates.append(midnight) }
                }
            }
        }
        let entries = Set(dates).sorted().map { NoorEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(6 * 3600))))
    }
}

enum NoorWidgetKind: String, CaseIterable {
    case nextPrayer, prayerDay, dua, reading, ward, review, khatmah, salawat
    var title: String {
        switch self {
        case .nextPrayer: "الصلاة القادمة"
        case .prayerDay: "مواقيت اليوم"
        case .dua: "دعاء قصير"
        case .reading: "تابع القراءة"
        case .ward: "ورد اليوم"
        case .review: "المراجعة المستحقة"
        case .khatmah: "رحلة الختمة"
        case .salawat: "الصلاة على النبي ﷺ"
        }
    }
    var symbol: String {
        switch self {
        case .nextPrayer: "sun.horizon"
        case .prayerDay: "clock"
        case .dua: "hands.sparkles"
        case .reading: "book"
        case .ward: "checkmark.circle"
        case .review: "arrow.clockwise"
        case .khatmah: "book.closed"
        case .salawat: "plus.circle"
        }
    }
    var families: [WidgetFamily] {
        switch self {
        case .prayerDay: [.systemMedium, .systemLarge]
        case .dua: [.systemMedium, .systemLarge]
        default: [.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline]
        }
    }
    func url(page: Int) -> URL? {
        let route: String
        switch self {
        case .nextPrayer, .prayerDay: route = "prayers"
        case .dua: route = "dhikr"
        case .reading: route = "reading/\(page)"
        case .ward: route = "ward"
        case .review: route = "review"
        case .khatmah: route = "khatmah"
        case .salawat: route = "salawat"
        }
        return URL(string: "nooralruh://" + route)
    }
}
struct NoorWidgetView: View {
    let entry: NoorEntry
    let kind: NoorWidgetKind
    @Environment(\.widgetFamily) private var family
    private var inline: Bool { family == .accessoryInline }
    private var lockScreen: Bool { inline || family == .accessoryRectangular }
    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                if inline { Label(summary(snapshot), systemImage: kind.symbol) }
                else {
                    VStack(alignment: .leading, spacing: lockScreen ? 3 : 9) {
                        Label(kind.title, systemImage: kind.symbol).font(.caption).foregroundStyle(.secondary)
                        content(snapshot)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
            } else {
                Label("افتح نور الروح لإعداد الأداة", systemImage: kind.symbol).font(.subheadline)
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Locale(identifier: "ar_SA"))
        .containerBackground(.background, for: .widget)
        .widgetURL(kind.url(page: entry.snapshot?.page ?? 1))
    }
    private func summary(_ snapshot: NoorWidgetSnapshot) -> String {
        switch kind {
        case .nextPrayer, .prayerDay:
            guard let next = PrayerCalculator.next(data: snapshot.prayer, now: entry.date) else { return "افتح التطبيق لتحديث المواقيت" }
            return "\(next.name) \(PrayerDisplay.isolatedClock(next.date, city: snapshot.prayer.city))"
        case .reading: return "الصفحة \(snapshot.page.formatted(.number.locale(Locale(identifier: "ar_SA"))))"
        case .ward: return "\(snapshot.completed(at: entry.date)) من \(snapshot.dailyTarget) آيات"
        case .review: return "\(snapshot.due(at: entry.date)) آيات للمراجعة"
        case .dua: return snapshot.duaTitle
        case .khatmah:
            guard let plan = snapshot.khatmah else { return "ابدأ رحلة الختمة" }
            guard let ward = plan.ward(at: entry.date) else { return plan.wardTitle(at: entry.date) }
            return "\(plan.wardTitle(at: entry.date)) · \(ward.first)–\(ward.last)"
        case .salawat:
            let zone = snapshot.salawatTimeZone.flatMap(TimeZone.init(identifier:)) ?? .current
            return "عدد اليوم: \(snapshot.salawat?.count(at: entry.date, timeZone: zone) ?? 0)"
        }
    }
    @ViewBuilder private func content(_ snapshot: NoorWidgetSnapshot) -> some View {
        switch kind {
        case .nextPrayer:
            if let next = PrayerCalculator.next(data: snapshot.prayer, now: entry.date) {
                Text(summary(snapshot)).font(lockScreen ? .headline : .title2.bold())
                Text(timerInterval: entry.date...next.date, countsDown: true).font(.caption).monospacedDigit()
                    .environment(\.locale, Locale(identifier: "en_US_POSIX"))
                    .environment(\.layoutDirection, .leftToRight)
                if !lockScreen {
                    HStack {
                        Text(snapshot.prayer.city.name)
                        Spacer()
                        Text(PrayerDisplay.date(next.date, city: snapshot.prayer.city, format: "d MMMM"))
                    }.font(.caption).foregroundStyle(.secondary)
                }
            } else { Text("افتح التطبيق لتحديث المواقيت") }
        case .prayerDay:
            Text(snapshot.prayer.city.name).font(.headline)
            Text(PrayerDisplay.gregorian(entry.date, city: snapshot.prayer.city)).font(.caption).foregroundStyle(.secondary)
            if family == .systemLarge {
                Text(PrayerDisplay.hijri(entry.date, city: snapshot.prayer.city)).font(.caption).foregroundStyle(.secondary)
            }
            let rows = PrayerCalculator.rows(data: snapshot.prayer, date: entry.date)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: family == .systemLarge ? 2 : 3), spacing: 7) {
                ForEach(rows) { row in
                    VStack(spacing: 2) {
                        Text(row.name).font(.caption)
                        Text(PrayerCalculator.time(row.date, city: snapshot.prayer.city)).font(.subheadline.bold()).monospacedDigit()
                            .environment(\.layoutDirection, .leftToRight)
                    }
                }
            }
        case .dua:
            if snapshot.dua.isEmpty { Text("افتح التطبيق لتحميل الدعاء") }
            else {
                Text(snapshot.duaTitle).font(.caption)
                Text(snapshot.dua).font(.body).fixedSize(horizontal: false, vertical: true)
            }
        case .reading:
            Text(summary(snapshot)).font(lockScreen ? .headline : .title2.bold())
            Text("أكمل من حيث توقفت").font(.caption).foregroundStyle(.secondary)
        case .ward:
            Text(summary(snapshot)).font(.headline)
            ProgressView(value: Double(min(snapshot.completed(at: entry.date), snapshot.dailyTarget)), total: Double(max(1, snapshot.dailyTarget)))
            if !lockScreen {
                Text(entry.date, style: .date).font(.caption).foregroundStyle(.secondary)
                Text("تقدم التدريب المسجّل").font(.caption).foregroundStyle(.secondary)
            }
        case .review:
            Text(summary(snapshot)).font(.headline)
            Text(snapshot.updated, style: .date).font(.caption).foregroundStyle(.secondary)
        case .khatmah:
            Text(summary(snapshot)).font(.headline)
            if let plan = snapshot.khatmah {
                Text("\(plan.completed) من \(605 - plan.firstPage) صفحة").font(.caption)
                if !lockScreen {
                    ProgressView(value: Double(plan.completed), total: Double(605 - plan.firstPage))
                    Text("القراءة المؤكدة في التطبيق").font(.caption).foregroundStyle(.secondary)
                }
            }
        case .salawat:
            Text(summary(snapshot)).font(lockScreen ? .headline : .title2.bold())
            if let goal = snapshot.salawat?.goal {
                Text("هدفك الشخصي: \(goal)").font(.caption).foregroundStyle(.secondary)
            } else if !lockScreen { Text("افتح العداد لمتابعة الذكر").font(.caption).foregroundStyle(.secondary) }
        }
    }
}
struct NoorWidget: Widget {
    let type: NoorWidgetKind
    init() { type = .nextPrayer }
    init(type: NoorWidgetKind) { self.type = type }
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "noor." + type.rawValue, provider: NoorProvider()) { entry in NoorWidgetView(entry: entry, kind: type) }
            .configurationDisplayName(type.title)
            .description("تابع القراءة والعبادة من شاشتك.")
            .supportedFamilies(type.families)
    }
}
@main struct NoorWidgets: WidgetBundle {
    var body: some Widget {
        NoorWidget(type: .nextPrayer)
        NoorWidget(type: .prayerDay)
        NoorWidget(type: .dua)
        NoorWidget(type: .reading)
        NoorWidget(type: .ward)
        NoorWidget(type: .review)
        NoorWidget(type: .khatmah)
        NoorWidget(type: .salawat)
    }
}
